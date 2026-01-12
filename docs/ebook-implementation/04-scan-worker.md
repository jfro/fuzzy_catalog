# Phase 4: ScanWorker (File Discovery)

Implement an Oban worker that discovers ebook files in directories and creates Ebook records.

## Overview

The ScanWorker is responsible for:
- Recursively (or non-recursively) scanning directories for EPUB/PDF files
- Calculating file hashes for deduplication
- Creating Ebook records in the database
- Enqueueing ProcessWorker jobs for each discovered file

## Step 4.1: Write ScanWorker Tests

**File:** `test/fuzzy_catalog/ebooks/workers/scan_worker_test.exs`

```elixir
defmodule FuzzyCatalog.Ebooks.Workers.ScanWorkerTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  alias FuzzyCatalog.Ebooks.Workers.{ScanWorker, ProcessWorker}
  alias FuzzyCatalog.Ebooks
  import FuzzyCatalog.AccountsFixtures
  import FuzzyCatalog.EbooksFixtures

  describe "perform/1" do
    @tag :tmp_dir
    test "discovers ebook files in directory", %{tmp_dir: tmp_dir} do
      user = user_fixture()

      # Create test files
      epub_path = Path.join(tmp_dir, "book1.epub")
      pdf_path = Path.join(tmp_dir, "book2.pdf")
      File.write!(epub_path, "fake epub content")
      File.write!(pdf_path, "fake pdf content")

      # Enqueue job
      assert :ok = perform_job(ScanWorker, %{
        "directory" => tmp_dir,
        "user_id" => user.id,
        "recursive" => false
      })

      # Verify ebooks were created
      ebooks = Ebooks.list_ebooks(user.id)
      assert length(ebooks) == 2

      paths = Enum.map(ebooks, & &1.file_path)
      assert epub_path in paths
      assert pdf_path in paths
    end

    @tag :tmp_dir
    test "scans recursively when enabled", %{tmp_dir: tmp_dir} do
      user = user_fixture()

      # Create nested structure
      subdir = Path.join(tmp_dir, "subfolder")
      File.mkdir_p!(subdir)

      File.write!(Path.join(tmp_dir, "root.epub"), "content")
      File.write!(Path.join(subdir, "nested.epub"), "content")

      assert :ok = perform_job(ScanWorker, %{
        "directory" => tmp_dir,
        "user_id" => user.id,
        "recursive" => true
      })

      ebooks = Ebooks.list_ebooks(user.id)
      assert length(ebooks) == 2
    end

    @tag :tmp_dir
    test "scans only top level when recursive is false", %{tmp_dir: tmp_dir} do
      user = user_fixture()

      # Create nested structure
      subdir = Path.join(tmp_dir, "subfolder")
      File.mkdir_p!(subdir)

      File.write!(Path.join(tmp_dir, "root.epub"), "content")
      File.write!(Path.join(subdir, "nested.epub"), "content")

      assert :ok = perform_job(ScanWorker, %{
        "directory" => tmp_dir,
        "user_id" => user.id,
        "recursive" => false
      })

      ebooks = Ebooks.list_ebooks(user.id)
      assert length(ebooks) == 1
    end

    @tag :tmp_dir
    test "skips already-scanned files", %{tmp_dir: tmp_dir} do
      user = user_fixture()

      # Create file
      epub_path = Path.join(tmp_dir, "existing.epub")
      File.write!(epub_path, "content")

      # Create existing ebook record
      _existing = ebook_fixture(
        user_id: user.id,
        file_path: epub_path
      )

      # Scan again
      assert :ok = perform_job(ScanWorker, %{
        "directory" => tmp_dir,
        "user_id" => user.id,
        "recursive" => false
      })

      # Should still only have 1 ebook
      assert length(Ebooks.list_ebooks(user.id)) == 1
    end

    @tag :tmp_dir
    test "enqueues ProcessWorker jobs for new ebooks", %{tmp_dir: tmp_dir} do
      user = user_fixture()
      File.write!(Path.join(tmp_dir, "book.epub"), "content")

      assert :ok = perform_job(ScanWorker, %{
        "directory" => tmp_dir,
        "user_id" => user.id,
        "recursive" => false
      })

      # Check that ProcessWorker job was enqueued
      assert_enqueued worker: ProcessWorker
    end

    test "handles directory not found" do
      user = user_fixture()

      assert {:error, reason} = perform_job(ScanWorker, %{
        "directory" => "/nonexistent/path",
        "user_id" => user.id,
        "recursive" => false
      })

      assert reason =~ "directory not found"
    end

    @tag :tmp_dir
    test "ignores non-ebook files", %{tmp_dir: tmp_dir} do
      user = user_fixture()

      File.write!(Path.join(tmp_dir, "readme.txt"), "content")
      File.write!(Path.join(tmp_dir, "image.jpg"), "content")

      assert :ok = perform_job(ScanWorker, %{
        "directory" => tmp_dir,
        "user_id" => user.id,
        "recursive" => false
      })

      assert length(Ebooks.list_ebooks(user.id)) == 0
    end
  end

  describe "calculate_file_hash/1" do
    @tag :tmp_dir
    test "calculates consistent hash for file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.epub")
      File.write!(path, "test content")

      hash1 = ScanWorker.calculate_file_hash(path)
      hash2 = ScanWorker.calculate_file_hash(path)

      assert hash1 == hash2
      assert is_binary(hash1)
      assert String.length(hash1) > 0
    end
  end
end
```

---

## Step 4.2: Implement ScanWorker

**File:** `lib/fuzzy_catalog/ebooks/workers/scan_worker.ex`

```elixir
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
  def perform(%Oban.Job{args: %{
    "directory" => directory,
    "user_id" => user_id,
    "recursive" => recursive
  }}) do
    Logger.info("Starting ebook scan in #{directory} (recursive: #{recursive})")

    with :ok <- validate_directory(directory),
         {:ok, files} <- discover_files(directory, recursive),
         {:ok, results} <- process_files(files, user_id) do

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
    pattern = if recursive do
      Path.join([directory, "**", "*.{epub,pdf}"])
    else
      Path.join([directory, "*.{epub,pdf}"])
    end

    files = Path.wildcard(pattern, match_dot: false)
    {:ok, files}
  end

  defp process_files(files, user_id) do
    results = Enum.reduce(files, %{new: 0, skipped: 0}, fn file, acc ->
      case process_single_file(file, user_id) do
        {:ok, :new} -> Map.update!(acc, :new, &(&1 + 1))
        {:ok, :existing} -> Map.update!(acc, :skipped, &(&1 + 1))
        {:error, reason} ->
          Logger.warning("Failed to process #{file}: #{inspect(reason)}")
          acc
      end
    end)

    {:ok, results}
  end

  defp process_single_file(file_path, user_id) do
    # Check if already exists
    case Ebooks.get_ebook_by_path(file_path, user_id) do
      nil ->
        create_ebook_record(file_path, user_id)

      _existing ->
        {:ok, :existing}
    end
  end

  defp create_ebook_record(file_path, user_id) do
    file_stat = File.stat!(file_path)

    attrs = %{
      file_path: file_path,
      file_format: determine_format(file_path),
      file_size: file_stat.size,
      file_hash: calculate_file_hash(file_path),
      last_modified_at: file_stat.mtime |> DateTime.from_naive!("Etc/UTC"),
      user_id: user_id,
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

  defp determine_format(file_path) do
    case Path.extname(file_path) do
      ".epub" -> "epub"
      ".pdf" -> "pdf"
      _ -> "unknown"
    end
  end
end
```

---

## Verification

Run tests:

```bash
mix test test/fuzzy_catalog/ebooks/workers/scan_worker_test.exs
```

All tests should pass ✅

---

## Usage Example

Trigger a scan from IEx:

```elixir
# Start IEx
iex -S mix

# Get a user
user = FuzzyCatalog.Accounts.list_users() |> List.first()

# Enqueue scan job
{:ok, job} = %{
  directory: "/path/to/ebooks",
  user_id: user.id,
  recursive: true
}
|> FuzzyCatalog.Ebooks.Workers.ScanWorker.new()
|> Oban.insert()
```

---

## Next Steps

Continue to [Phase 5: ProcessWorker](./05-process-worker.md) to implement file processing and metadata extraction.
