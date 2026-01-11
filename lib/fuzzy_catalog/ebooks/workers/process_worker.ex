defmodule FuzzyCatalog.Ebooks.Workers.ProcessWorker do
  @moduledoc """
  Oban worker that processes ebook files.

  Responsibilities:
  - Extract metadata from ebook files
  - Generate and store cover thumbnails
  - Match ebooks to existing Book records (ISBN or fuzzy matching)
  - Verify file integrity
  """

  use Oban.Worker,
    queue: :ebook_process,
    max_attempts: 3

  require Logger
  import Ecto.Query

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.MetadataExtractor
  alias FuzzyCatalog.Catalog
  alias FuzzyCatalog.Collections
  alias FuzzyCatalog.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ebook_id" => ebook_id} = args}) do
    try do
      do_perform(ebook_id, args)
    rescue
      e in Postgrex.Error ->
        # Extract detailed error information from Postgrex errors
        error_msg = format_postgres_error(e, ebook_id)
        Logger.error(error_msg)

        # Try to mark ebook as failed
        try do
          ebook = Repo.get!(FuzzyCatalog.Ebooks.Ebook, ebook_id)

          Ebooks.update_ebook(ebook, %{
            processing_status: "failed",
            processing_error: error_msg,
            last_processed_at: DateTime.utc_now()
          })

          update_library_progress(ebook.library_id)
        rescue
          _ -> :ok
        end

        reraise e, __STACKTRACE__

      e ->
        Logger.error("Unexpected error processing ebook #{ebook_id}: #{Exception.message(e)}")

        # Try to mark ebook as failed
        try do
          ebook = Repo.get!(FuzzyCatalog.Ebooks.Ebook, ebook_id)

          Ebooks.update_ebook(ebook, %{
            processing_status: "failed",
            processing_error: "Unexpected error: #{Exception.message(e)}",
            last_processed_at: DateTime.utc_now()
          })

          update_library_progress(ebook.library_id)
        rescue
          _ -> :ok
        end

        reraise e, __STACKTRACE__
    end
  end

  defp format_postgres_error(%Postgrex.Error{postgres: postgres}, ebook_id)
       when is_map(postgres) do
    code = Map.get(postgres, :code)
    message = Map.get(postgres, :message)

    # For string_data_right_truncation errors, try to extract more context
    case code do
      :string_data_right_truncation ->
        # Try to find which field in the stacktrace
        "Database error for ebook #{ebook_id}: #{message}. Check recent log messages above to see which field is too long."

      _ ->
        "Database error for ebook #{ebook_id}: #{message}"
    end
  end

  defp format_postgres_error(error, ebook_id) do
    "Unexpected database error for ebook #{ebook_id}: #{Exception.message(error)}"
  end

  defp inspect_attrs(attrs) do
    # Log string field lengths to help identify which field is too long
    attrs
    |> Enum.map(fn {key, value} ->
      case value do
        s when is_binary(s) ->
          {key, "\"#{String.slice(s, 0..50)}...\" (length: #{String.length(s)})"}

        v ->
          {key, inspect(v)}
      end
    end)
    |> Enum.into(%{})
    |> inspect()
  end

  defp do_perform(ebook_id, args) do
    # Get fuzzy matching setting from args, or fall back to config
    default_fuzzy = Application.get_env(:fuzzy_catalog, :ebooks)[:enable_fuzzy_matching]
    enable_fuzzy = Map.get(args, "enable_fuzzy_matching", default_fuzzy)

    Logger.info("Processing ebook #{ebook_id}")

    # Get ebook - this will raise if not found, which is expected
    ebook = Repo.get!(FuzzyCatalog.Ebooks.Ebook, ebook_id)
    Logger.info("Processing ebook #{ebook_id}: #{Path.basename(ebook.file_path)}")

    with :ok <- log_progress(ebook_id, "Verifying file"),
         :ok <- verify_file_exists(ebook),
         :ok <- log_progress(ebook_id, "Calculating hash"),
         current_hash <- calculate_file_hash(ebook.file_path),
         :ok <- log_file_change_status(ebook, current_hash),
         :ok <- log_progress(ebook_id, "Extracting metadata"),
         {:ok, epub_metadata} <- extract_metadata(ebook),
         {:ok, opf_metadata} <- extract_opf_metadata(ebook),
         metadata <- merge_metadata(epub_metadata, opf_metadata),
         :ok <- log_progress(ebook_id, "Extracting cover"),
         {:ok, cover_key} <- extract_and_store_cover(ebook),
         :ok <- log_progress(ebook_id, "Matching to book"),
         {:ok, book_id} <- match_or_create_book(metadata, cover_key, enable_fuzzy),
         :ok <- ensure_book_in_collection(book_id) do
      update_attrs = %{
        extracted_title: epub_metadata.title,
        extracted_author: epub_metadata.author,
        extracted_isbn: epub_metadata.isbn,
        extracted_publisher: epub_metadata.publisher,
        extracted_language: epub_metadata.language,
        extracted_description: epub_metadata.description,
        cover_thumbnail_key: cover_key,
        book_id: book_id,
        file_hash: current_hash,
        processing_status: "completed",
        last_processed_at: DateTime.utc_now()
      }

      Logger.debug("Updating ebook #{ebook_id} with attributes: #{inspect_attrs(update_attrs)}")

      case Ebooks.update_ebook(ebook, update_attrs) do
        {:ok, updated_ebook} ->
          Logger.info("Successfully processed ebook #{ebook_id}")
          update_library_progress(updated_ebook.library_id)
          :ok

        {:error, reason} ->
          handle_error(ebook, "Failed to update: #{inspect(reason)}")
      end
    else
      {:error, reason} ->
        result = handle_error(ebook, reason)
        update_library_progress(ebook.library_id)
        result
    end
  end

  defp log_progress(ebook_id, stage) do
    Logger.info("Ebook #{ebook_id}: #{stage}")
    :ok
  end

  defp update_library_progress(nil), do: :ok

  defp update_library_progress(library_id) do
    # Count total and completed ebooks for this library
    total =
      from(e in FuzzyCatalog.Ebooks.Ebook,
        where: e.library_id == ^library_id,
        select: count(e.id)
      )
      |> Repo.one()

    completed =
      from(e in FuzzyCatalog.Ebooks.Ebook,
        where: e.library_id == ^library_id,
        where: e.processing_status in ["completed", "failed"],
        select: count(e.id)
      )
      |> Repo.one()

    library = Libraries.get_library!(library_id)

    if completed >= total do
      # All ebooks processed, mark library as complete
      Libraries.mark_scan_complete(library)
      Libraries.clear_scan_progress(library)
      Logger.info("Library #{library_id} processing complete: #{completed}/#{total} ebooks")
    else
      # Still processing, update progress
      Libraries.update_scan_progress(library, "processing", completed, total)
      Logger.debug("Library #{library_id} progress: #{completed}/#{total} ebooks processed")
    end

    :ok
  rescue
    e ->
      Logger.warning("Failed to update library progress for library #{library_id}: #{inspect(e)}")

      :ok
  end

  # Private functions

  defp verify_file_exists(ebook) do
    if File.exists?(ebook.file_path) do
      :ok
    else
      {:error, "file not found: #{ebook.file_path}"}
    end
  end

  defp log_file_change_status(ebook, current_hash) do
    cond do
      is_nil(ebook.file_hash) ->
        Logger.info("Processing ebook #{ebook.id} for the first time")
        :ok

      current_hash == ebook.file_hash ->
        Logger.debug("Reprocessing ebook #{ebook.id} (file unchanged)")
        :ok

      true ->
        Logger.info("Reprocessing ebook #{ebook.id} (file has been modified)")
        :ok
    end
  end

  defp calculate_file_hash(file_path) do
    # Stream file in 64KB chunks to avoid loading entire file into memory
    file_path
    |> File.stream!([], 65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp extract_metadata(ebook) do
    case MetadataExtractor.extract(ebook.file_path) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, reason} ->
        # Pass through user-friendly errors without wrapping
        if user_friendly_error?(reason) do
          {:error, reason}
        else
          {:error, "metadata extraction failed: #{reason}"}
        end
    end
  end

  defp extract_opf_metadata(ebook) do
    case MetadataExtractor.extract_opf_metadata(ebook.file_path) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, reason} ->
        Logger.warning("OPF metadata extraction failed for #{ebook.id}: #{reason}")
        {:ok, nil}
    end
  end

  defp merge_metadata(epub_metadata, nil), do: epub_metadata

  defp merge_metadata(epub_metadata, opf_metadata) do
    # OPF metadata takes precedence over EPUB metadata
    Map.merge(epub_metadata, opf_metadata, fn
      _key, epub_value, nil -> epub_value
      _key, _epub_value, opf_value -> opf_value
    end)
  end

  defp extract_and_store_cover(ebook) do
    # Try Calibre cover.jpg first, fall back to EPUB embedded cover
    result =
      case MetadataExtractor.extract_calibre_cover(ebook.file_path) do
        {:ok, cover_binary} ->
          {:ok, cover_binary}

        {:error, :no_cover} ->
          MetadataExtractor.extract_cover(ebook.file_path)
      end

    case result do
      {:ok, cover_binary} ->
        store_cover_thumbnail(cover_binary, ebook.file_format)

      {:error, :no_cover} ->
        {:ok, nil}

      {:error, reason} ->
        Logger.warning("Cover extraction failed for #{ebook.id}: #{reason}")
        {:ok, nil}
    end
  end

  defp store_cover_thumbnail(binary, format) do
    content_type =
      case format do
        "epub" -> "image/jpeg"
        "pdf" -> "image/jpeg"
        _ -> "image/jpeg"
      end

    case Storage.store_cover(binary, content_type: content_type) do
      {:ok, storage_key} ->
        {:ok, storage_key}

      {:error, reason} ->
        Logger.warning("Failed to store cover: #{reason}")
        {:ok, nil}
    end
  end

  defp match_or_create_book(metadata, cover_key, enable_fuzzy) do
    book =
      cond do
        # Try ISBN match first
        not is_nil(metadata.isbn) ->
          Catalog.get_book_by_isbn(metadata.isbn)

        # Try fuzzy matching if enabled
        enable_fuzzy and not is_nil(metadata.title) and not is_nil(metadata.author) ->
          Catalog.find_book_by_title_and_author(metadata.title, metadata.author)

        # No match criteria
        true ->
          nil
      end

    case book do
      nil ->
        # No existing book found, create a new one
        create_book_from_metadata(metadata, cover_key)

      existing_book ->
        # Update existing book with metadata
        update_book_with_metadata(existing_book, metadata, cover_key)
    end
  end

  defp create_book_from_metadata(metadata, cover_key) do
    # Build book attributes from metadata
    attrs = %{
      title: metadata.title || "Unknown Title",
      author: metadata.author || "Unknown Author",
      isbn13: metadata.isbn,
      publisher: metadata.publisher,
      language: metadata.language,
      description: metadata.description,
      series: metadata[:series],
      series_number: metadata[:series_index],
      rating: metadata[:rating],
      tags: normalize_tags(metadata[:tags] || []),
      custom_metadata: metadata[:custom_metadata] || %{},
      cover_image_key: cover_key
    }

    # Log attributes with lengths for debugging
    Logger.debug("Creating book with attributes: #{inspect_attrs(attrs)}")

    case Catalog.create_book_without_collection(attrs) do
      {:ok, book} ->
        {:ok, book.id}

      {:error, reason} ->
        Logger.warning("Failed to create book: #{inspect(reason)}")
        {:ok, nil}
    end
  end

  defp update_book_with_metadata(book, metadata, cover_key) do
    # Update book with new metadata (fill in missing fields)
    # Only set cover if book doesn't have one and we extracted one
    attrs = %{
      publisher: book.publisher || metadata.publisher,
      language: book.language || metadata.language,
      description: book.description || metadata.description,
      series: book.series || metadata[:series],
      series_number: book.series_number || metadata[:series_index],
      rating: book.rating || metadata[:rating],
      tags: merge_tags(book.tags, metadata[:tags]),
      custom_metadata: Map.merge(book.custom_metadata || %{}, metadata[:custom_metadata] || %{}),
      cover_image_key: book.cover_image_key || cover_key
    }

    case Catalog.update_book(book, attrs) do
      {:ok, updated_book} ->
        {:ok, updated_book.id}

      {:error, reason} ->
        Logger.warning("Failed to update book #{book.id}: #{inspect(reason)}")
        {:ok, book.id}
    end
  end

  # Normalize tags by splitting semicolon-separated strings and trimming
  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.flat_map(fn tag ->
      if is_binary(tag) and String.contains?(tag, ";") do
        # Split semicolon-separated tags
        tag
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      else
        [tag]
      end
    end)
    |> Enum.uniq()
  end

  defp normalize_tags(_), do: []

  defp merge_tags(existing_tags, nil), do: normalize_tags(existing_tags || [])
  defp merge_tags(nil, new_tags), do: normalize_tags(new_tags || [])

  defp merge_tags(existing_tags, new_tags) do
    (existing_tags ++ new_tags)
    |> normalize_tags()
  end

  defp ensure_book_in_collection(nil), do: :ok

  defp ensure_book_in_collection(book_id) do
    book = Catalog.get_book!(book_id)

    case Collections.add_to_collection(book, "ebook") do
      {:ok, _collection_item} ->
        Logger.info("Added book #{book_id} to ebook collection")
        :ok

      {:error, %Ecto.Changeset{errors: [book_id: {_, [constraint: :unique, constraint_name: _]}]}} ->
        # Already in collection with this media type, that's fine
        Logger.debug("Book #{book_id} already in ebook collection")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to add book #{book_id} to collection: #{inspect(reason)}")
        # Don't fail the whole job just because collection add failed
        :ok
    end
  end

  # Lifecycle callbacks to handle job failures
  # These are optional Oban hooks, not required behaviour callbacks

  def handle_exhausted(%Oban.Job{args: args}) do
    # Job has exhausted all retries
    case Map.get(args, "ebook_id") do
      nil ->
        Logger.error("Processing job exhausted without ebook_id: #{inspect(args)}")

      ebook_id ->
        Logger.error("Ebook #{ebook_id} processing job exhausted all retries")

        try do
          ebook = Repo.get!(FuzzyCatalog.Ebooks.Ebook, ebook_id)

          Ebooks.update_ebook(ebook, %{
            processing_status: "failed",
            processing_error: "Processing job exhausted all retry attempts",
            last_processed_at: DateTime.utc_now()
          })

          update_library_progress(ebook.library_id)
        rescue
          Ecto.NoResultsError ->
            Logger.error("Ebook #{ebook_id} not found when handling exhausted job")
        end
    end

    :discard
  end

  def handle_cancelled(%Oban.Job{args: args}) do
    # Job was cancelled manually
    case Map.get(args, "ebook_id") do
      nil ->
        Logger.warning("Processing job cancelled without ebook_id: #{inspect(args)}")

      ebook_id ->
        Logger.warning("Ebook #{ebook_id} processing job was cancelled")

        try do
          ebook = Repo.get!(FuzzyCatalog.Ebooks.Ebook, ebook_id)

          Ebooks.update_ebook(ebook, %{
            processing_status: "failed",
            processing_error: "Processing job was cancelled",
            last_processed_at: DateTime.utc_now()
          })

          update_library_progress(ebook.library_id)
        rescue
          Ecto.NoResultsError ->
            Logger.error("Ebook #{ebook_id} not found when handling cancelled job")
        end
    end

    :ok
  end

  defp handle_error(ebook, reason) do
    Logger.error("Processing failed for ebook #{ebook.id}: #{reason}")

    Ebooks.update_ebook(ebook, %{
      processing_status: "failed",
      processing_error: to_string(reason),
      last_processed_at: DateTime.utc_now()
    })

    {:error, reason}
  end

  # Check if an error message is already user-friendly (starts with "EPUB file" or "PDF file")
  defp user_friendly_error?(message) when is_binary(message) do
    String.starts_with?(message, "EPUB file") or String.starts_with?(message, "PDF file")
  end

  defp user_friendly_error?(_), do: false
end
