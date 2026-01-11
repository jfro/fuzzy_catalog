defmodule FuzzyCatalog.Ebooks.Workers.ScanWorker do
  @moduledoc """
  Oban worker that scans directories for ebook files and creates Ebook records.

  Responsibilities:
  - Discover files recursively or non-recursively
  - Calculate file hashes for deduplication
  - Create Ebook records
  - Enqueue ProcessWorker jobs for new files
  """

  use Oban.Worker,
    queue: :ebook_scan,
    max_attempts: 3

  require Logger
  import Ecto.Query
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Workers.ProcessWorker
  alias FuzzyCatalog.Repo

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "directory" => directory,
            "recursive" => recursive
          } = args
      }) do
    library_id = Map.get(args, "library_id")

    Logger.info(
      "Starting ebook scan in #{directory} (recursive: #{recursive}, library_id: #{inspect(library_id)})"
    )

    result =
      with :ok <- validate_directory(directory),
           {:ok, files} <- discover_files(directory, recursive) do
        total_files = length(files)

        Logger.info("Found #{total_files} files to scan")

        # Process files with progress tracking
        {:ok, results} = process_files_with_progress(files, library_id, total_files)

        Logger.info(
          "Scan completed: #{results.new} new, #{results.reprocessed} reprocessed, #{results.skipped} skipped"
        )

        :ok
      else
        {:error, reason} ->
          Logger.error("Scan failed: #{inspect(reason)}")
          {:error, reason}
      end

    # Update library status if library_id provided
    if library_id do
      case result do
        :ok ->
          # Scan completed successfully, but check if there are pending ebooks to process
          library = Libraries.get_library!(library_id)
          pending_count = count_pending_ebooks(library_id)

          if pending_count > 0 do
            # Keep scanning status, but switch to processing stage
            Libraries.update_scan_progress(library, "processing", 0, pending_count)

            Logger.info(
              "Library #{library_id} scan complete, now processing #{pending_count} ebooks"
            )
          else
            # No ebooks to process, mark as complete
            Libraries.mark_scan_complete(library)
            Libraries.clear_scan_progress(library)
          end

        {:error, _reason} ->
          # Scan failed
          update_library_status(library_id, result)
          library = Libraries.get_library!(library_id)
          Libraries.clear_scan_progress(library)
      end
    end

    result
  end

  defp count_pending_ebooks(library_id) do
    from(e in FuzzyCatalog.Ebooks.Ebook,
      where: e.library_id == ^library_id,
      where: e.processing_status in ["pending", "processing"]
    )
    |> Repo.all()
    |> length()
  end

  # Lifecycle callbacks to ensure library status is cleaned up even on job failure
  # These are optional Oban hooks, not required behaviour callbacks

  def handle_exhausted(%Oban.Job{args: args}) do
    # Job has exhausted all retries
    library_id = Map.get(args, "library_id")

    if library_id do
      try do
        library = Libraries.get_library!(library_id)
        Libraries.mark_scan_failed(library, "Scan job exhausted all retry attempts")
        Logger.error("Library #{library_id} scan job exhausted all retries")
      rescue
        Ecto.NoResultsError ->
          Logger.error("Library #{library_id} not found when handling exhausted scan job")
      end
    end

    :discard
  end

  def handle_cancelled(%Oban.Job{args: args}) do
    # Job was cancelled manually
    library_id = Map.get(args, "library_id")

    if library_id do
      try do
        library = Libraries.get_library!(library_id)
        Libraries.mark_scan_failed(library, "Scan job was cancelled")
        Logger.warning("Library #{library_id} scan job was cancelled")
      rescue
        Ecto.NoResultsError ->
          Logger.error("Library #{library_id} not found when handling cancelled scan job")
      end
    end

    :ok
  end

  # Update library status based on scan result
  defp update_library_status(library_id, result) do
    library = Libraries.get_library!(library_id)

    case result do
      :ok ->
        Libraries.mark_scan_complete(library)

      {:error, reason} ->
        error_message =
          case reason do
            reason when is_binary(reason) -> reason
            _ -> inspect(reason)
          end

        Libraries.mark_scan_failed(library, error_message)
    end
  end

  @doc """
  Calculate SHA256 hash of a file using streaming to avoid loading entire file into memory.
  Public for testing purposes.
  """
  def calculate_file_hash(file_path) do
    # Stream file in 64KB chunks to avoid loading entire file into memory
    file_path
    |> File.stream!([], 65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  # Private functions

  defp validate_directory(directory) do
    if File.dir?(directory) do
      :ok
    else
      {:error, "directory not found: #{directory}"}
    end
  end

  defp discover_files(directory, recursive) do
    # Get supported formats from config
    supported_formats =
      Application.get_env(:fuzzy_catalog, :ebooks)[:supported_formats]
      |> Enum.join(",")

    pattern =
      if recursive do
        Path.join([directory, "**", "*.{#{supported_formats}}"])
      else
        Path.join([directory, "*.{#{supported_formats}}"])
      end

    files = Path.wildcard(pattern, match_dot: false)
    {:ok, files}
  end

  defp process_files_with_progress(files, library_id, total) do
    {results, _count} =
      Enum.reduce(files, {%{new: 0, reprocessed: 0, skipped: 0}, 0}, fn file, {acc, processed} ->
        # Process the file
        updated_acc =
          case process_single_file(file, library_id) do
            {:ok, :new} ->
              Map.update!(acc, :new, &(&1 + 1))

            {:ok, :reprocessing} ->
              Map.update!(acc, :reprocessed, &(&1 + 1))

            {:ok, :existing} ->
              Map.update!(acc, :skipped, &(&1 + 1))

            {:error, reason} ->
              Logger.warning("Failed to process #{file}: #{inspect(reason)}")
              acc
          end

        # Update progress
        new_processed = processed + 1

        # Update library progress if library_id provided
        if library_id do
          library = Libraries.get_library!(library_id)
          Libraries.update_scan_progress(library, "scanning", new_processed, total)
        end

        # Log progress every 10 files
        if rem(new_processed, 10) == 0 or new_processed == total do
          percent = if total > 0, do: floor(new_processed * 100 / total), else: 0
          Logger.info("Scan progress: #{new_processed}/#{total} files (#{percent}%)")
        end

        {updated_acc, new_processed}
      end)

    {:ok, results}
  end

  defp process_single_file(file_path, library_id) do
    # Check if already exists
    case Ebooks.get_ebook_by_path(file_path) do
      nil ->
        create_ebook_record(file_path, library_id)

      existing ->
        # Re-process if: failed, or file changed since last processing
        should_reprocess =
          existing.processing_status == "failed" or
            file_modified_since_last_process?(file_path, existing)

        if should_reprocess do
          # Update status to pending and enqueue processing
          case Ebooks.update_ebook(existing, %{processing_status: "pending"}) do
            {:ok, updated} ->
              %{"ebook_id" => updated.id}
              |> ProcessWorker.new()
              |> Oban.insert()

              Logger.info("Re-processing #{file_path} (#{existing.processing_status})")
              {:ok, :reprocessing}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:ok, :existing}
        end
    end
  end

  defp file_modified_since_last_process?(file_path, ebook) do
    case File.stat(file_path) do
      {:ok, file_stat} ->
        file_mtime =
          file_stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

        # Compare with last_processed_at (if available) or last_modified_at (from when ebook was created)
        last_processed = ebook.last_processed_at || ebook.last_modified_at

        if last_processed do
          DateTime.compare(file_mtime, last_processed) == :gt
        else
          # No timestamp, reprocess to be safe
          true
        end

      {:error, _} ->
        # Can't read file, don't reprocess
        false
    end
  end

  defp create_ebook_record(file_path, library_id) do
    file_stat = File.stat!(file_path)
    max_file_size = Application.get_env(:fuzzy_catalog, :ebooks)[:max_file_size]

    # Validate file size
    if file_stat.size > max_file_size do
      Logger.warning(
        "Skipping #{file_path}: file too large (#{file_stat.size} bytes, max: #{max_file_size})"
      )

      {:error, :file_too_large}
    else
      attrs =
        %{
          file_path: file_path,
          file_format: determine_format(file_path),
          file_size: file_stat.size,
          # Will be calculated by ProcessWorker to avoid blocking scan
          file_hash: nil,
          last_modified_at:
            file_stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC"),
          processing_status: "pending"
        }
        |> maybe_put_library_id(library_id)

      case Ebooks.create_ebook(attrs) do
        {:ok, ebook} ->
          # Enqueue processing job
          %{"ebook_id" => ebook.id}
          |> ProcessWorker.new()
          |> Oban.insert()

          {:ok, :new}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp determine_format(file_path) do
    case Path.extname(file_path) do
      ".epub" -> "epub"
      ".pdf" -> "pdf"
      _ -> "unknown"
    end
  end

  defp maybe_put_library_id(attrs, nil), do: attrs
  defp maybe_put_library_id(attrs, library_id), do: Map.put(attrs, :library_id, library_id)
end
