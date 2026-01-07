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
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Ebooks.MetadataExtractor
  alias FuzzyCatalog.Catalog
  alias FuzzyCatalog.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ebook_id" => ebook_id} = args}) do
    # Get fuzzy matching setting from args, or fall back to config
    default_fuzzy = Application.get_env(:fuzzy_catalog, :ebooks)[:enable_fuzzy_matching]
    enable_fuzzy = Map.get(args, "enable_fuzzy_matching", default_fuzzy)

    Logger.info("Processing ebook #{ebook_id}")

    # Get ebook - this will raise if not found, which is expected
    ebook = Repo.get!(FuzzyCatalog.Ebooks.Ebook, ebook_id)

    with :ok <- verify_file_exists(ebook),
         :ok <- verify_file_integrity(ebook),
         {:ok, metadata} <- extract_metadata(ebook),
         {:ok, cover_key} <- extract_and_store_cover(ebook),
         {:ok, book_id} <- match_to_book(metadata, enable_fuzzy) do
      update_attrs = %{
        extracted_title: metadata.title,
        extracted_author: metadata.author,
        extracted_isbn: metadata.isbn,
        extracted_publisher: metadata.publisher,
        extracted_language: metadata.language,
        extracted_description: metadata.description,
        cover_thumbnail_key: cover_key,
        book_id: book_id,
        processing_status: "completed",
        last_processed_at: DateTime.utc_now()
      }

      case Ebooks.update_ebook(ebook, update_attrs) do
        {:ok, _updated} ->
          Logger.info("Successfully processed ebook #{ebook_id}")
          :ok

        {:error, reason} ->
          handle_error(ebook, "Failed to update: #{inspect(reason)}")
      end
    else
      {:error, reason} ->
        handle_error(ebook, reason)
    end
  end

  # Private functions

  defp verify_file_exists(ebook) do
    if File.exists?(ebook.file_path) do
      :ok
    else
      {:error, "file not found: #{ebook.file_path}"}
    end
  end

  defp verify_file_integrity(ebook) do
    current_hash = calculate_file_hash(ebook.file_path)

    if is_nil(ebook.file_hash) or current_hash == ebook.file_hash do
      :ok
    else
      {:error, "file hash mismatch - file may have been modified"}
    end
  end

  defp calculate_file_hash(file_path) do
    {:ok, content} = File.read(file_path)
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp extract_metadata(ebook) do
    case MetadataExtractor.extract(ebook.file_path) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, reason} ->
        {:error, "metadata extraction failed: #{reason}"}
    end
  end

  defp extract_and_store_cover(ebook) do
    case MetadataExtractor.extract_cover(ebook.file_path) do
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

  defp match_to_book(metadata, enable_fuzzy) do
    cond do
      # Try ISBN match first
      metadata.isbn ->
        match_by_isbn(metadata.isbn)

      # Try fuzzy matching if enabled
      enable_fuzzy and metadata.title and metadata.author ->
        match_by_fuzzy(metadata.title, metadata.author)

      # No match
      true ->
        {:ok, nil}
    end
  end

  defp match_by_isbn(isbn) do
    case Catalog.get_book_by_isbn(isbn) do
      nil -> {:ok, nil}
      book -> {:ok, book.id}
    end
  end

  defp match_by_fuzzy(title, author) do
    # Use existing Catalog function for fuzzy title/author matching
    case Catalog.find_book_by_title_and_author(title, author) do
      nil -> {:ok, nil}
      book -> {:ok, book.id}
    end
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
end
