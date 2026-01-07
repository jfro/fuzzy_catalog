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
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Ebooks.Workers.ProcessWorker

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "directory" => directory,
          "recursive" => recursive
        }
      }) do
    Logger.info("Starting ebook scan in #{directory} (recursive: #{recursive})")

    with :ok <- validate_directory(directory),
         {:ok, files} <- discover_files(directory, recursive),
         {:ok, results} <- process_files(files) do
      Logger.info("Scan completed: #{results.new} new, #{results.skipped} skipped")
      :ok
    else
      {:error, reason} ->
        Logger.error("Scan failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculate SHA256 hash of a file.
  Public for testing purposes.
  """
  def calculate_file_hash(file_path) do
    {:ok, content} = File.read(file_path)
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
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

  defp process_files(files) do
    results =
      Enum.reduce(files, %{new: 0, skipped: 0}, fn file, acc ->
        case process_single_file(file) do
          {:ok, :new} ->
            Map.update!(acc, :new, &(&1 + 1))

          {:ok, :existing} ->
            Map.update!(acc, :skipped, &(&1 + 1))

          {:error, reason} ->
            Logger.warning("Failed to process #{file}: #{inspect(reason)}")
            acc
        end
      end)

    {:ok, results}
  end

  defp process_single_file(file_path) do
    # Check if already exists
    case Ebooks.get_ebook_by_path(file_path) do
      nil ->
        create_ebook_record(file_path)

      _existing ->
        {:ok, :existing}
    end
  end

  defp create_ebook_record(file_path) do
    file_stat = File.stat!(file_path)
    max_file_size = Application.get_env(:fuzzy_catalog, :ebooks)[:max_file_size]

    # Validate file size
    if file_stat.size > max_file_size do
      Logger.warning(
        "Skipping #{file_path}: file too large (#{file_stat.size} bytes, max: #{max_file_size})"
      )

      {:error, :file_too_large}
    else
      attrs = %{
        file_path: file_path,
        file_format: determine_format(file_path),
        file_size: file_stat.size,
        file_hash: calculate_file_hash(file_path),
        last_modified_at:
          file_stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC"),
        processing_status: "pending"
      }

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
end
