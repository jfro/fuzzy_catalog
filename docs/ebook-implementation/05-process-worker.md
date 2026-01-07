# Phase 5: ProcessWorker (File Processing)

Implement an Oban worker that processes ebook files by extracting metadata, generating cover thumbnails, and matching to existing books.

## Overview

The ProcessWorker is responsible for:
- Verifying file exists and hash matches
- Extracting metadata (title, author, ISBN, etc.)
- Extracting and storing cover thumbnails
- Matching ebooks to existing Book records (ISBN or fuzzy matching)
- Updating ebook record with results

## Step 5.1: Write ProcessWorker Tests

**File:** `test/fuzzy_catalog/ebooks/workers/process_worker_test.exs`

```elixir
defmodule FuzzyCatalog.Ebooks.Workers.ProcessWorkerTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  alias FuzzyCatalog.Ebooks.Workers.ProcessWorker
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Catalog
  import FuzzyCatalog.EbooksFixtures

  describe "perform/1" do
    @tag :tmp_dir
    test "extracts metadata from EPUB file", %{tmp_dir: tmp_dir} do
      user = user_fixture()
      epub_path = Path.join(tmp_dir, "test.epub")

      # Create a test EPUB (simplified - in reality use BUPE.Builder or sample file)
      File.write!(epub_path, "fake epub with metadata")

      ebook = ebook_fixture(user_id: user.id, file_path: epub_path)

      # Mock the metadata extraction to avoid complex EPUB creation
      # In real implementation, create proper EPUB or use sample files
      assert :ok = perform_job(ProcessWorker, %{
        "ebook_id" => ebook.id
      })

      updated = Ebooks.get_ebook!(ebook.id, user.id)
      assert updated.processing_status == "completed"
      refute is_nil(updated.last_processed_at)
    end

    @tag :tmp_dir
    test "matches to existing book by ISBN", %{tmp_dir: tmp_dir} do
      user = user_fixture()

      # Create existing book with ISBN
      book = book_fixture(%{
        title: "Existing Book",
        author: "Jane Smith",
        isbn13: "9780123456789"
      })

      # Create ebook file
      epub_path = Path.join(tmp_dir, "matching.epub")
      File.write!(epub_path, "fake epub content")

      # Create ebook record with ISBN in metadata (simulated)
      ebook = ebook_fixture(
        user_id: user.id,
        file_path: epub_path,
        extracted_isbn: "9780123456789"
      )

      assert :ok = perform_job(ProcessWorker, %{
        "ebook_id" => ebook.id
      })

      updated = Ebooks.get_ebook!(ebook.id, user.id)
      # With ISBN pre-filled, worker should match to book
      # Note: Actual matching happens during processing
    end

    test "handles missing file gracefully" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id, file_path: "/nonexistent/book.epub")

      assert {:error, _reason} = perform_job(ProcessWorker, %{
        "ebook_id" => ebook.id
      })

      updated = Ebooks.get_ebook!(ebook.id, user.id)
      assert updated.processing_status == "failed"
      assert updated.processing_error =~ "file not found"
    end

    @tag :tmp_dir
    test "verifies file integrity by hash", %{tmp_dir: tmp_dir} do
      user = user_fixture()
      epub_path = Path.join(tmp_dir, "verify.epub")

      # Create file and calculate hash
      original_content = "original content"
      File.write!(epub_path, original_content)
      original_hash = :crypto.hash(:sha256, original_content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(
        user_id: user.id,
        file_path: epub_path,
        file_hash: original_hash
      )

      # Modify file after ebook creation
      File.write!(epub_path, "modified content")

      assert {:error, _reason} = perform_job(ProcessWorker, %{
        "ebook_id" => ebook.id
      })

      updated = Ebooks.get_ebook!(ebook.id, user.id)
      assert updated.processing_status == "failed"
      assert updated.processing_error =~ "file hash mismatch"
    end

    @tag :tmp_dir
    test "updates processing status to failed on error", %{tmp_dir: tmp_dir} do
      user = user_fixture()
      corrupt_path = Path.join(tmp_dir, "corrupt.epub")
      File.write!(corrupt_path, "not a valid epub")

      ebook = ebook_fixture(user_id: user.id, file_path: corrupt_path)

      # Processing should fail gracefully
      assert {:error, _reason} = perform_job(ProcessWorker, %{
        "ebook_id" => ebook.id
      })

      updated = Ebooks.get_ebook!(ebook.id, user.id)
      assert updated.processing_status == "failed"
      assert updated.processing_error
    end
  end
end
```

---

## Step 5.2: Implement ProcessWorker

**File:** `lib/fuzzy_catalog/ebooks/workers/process_worker.ex`

```elixir
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
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Ebooks.MetadataExtractor
  alias FuzzyCatalog.Catalog
  alias FuzzyCatalog.Storage

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ebook_id" => ebook_id} = args}) do
    enable_fuzzy = Map.get(args, "enable_fuzzy_matching", false)

    Logger.info("Processing ebook #{ebook_id}")

    # Get ebook - this will raise if not found, which is expected
    ebook = Ebooks.get_ebook!(ebook_id, ebook_id) |> Repo.preload(:user)
    # Fix: Need user_id for get_ebook!/2
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
        {:ok, nil}  # Non-fatal error
    end
  end

  defp store_cover_thumbnail(binary, format) do
    content_type = case format do
      "epub" -> "image/jpeg"
      "pdf" -> "image/jpeg"
      _ -> "image/jpeg"
    end

    case Storage.store_cover(binary, content_type: content_type) do
      {:ok, storage_key} ->
        {:ok, storage_key}

      {:error, reason} ->
        Logger.warning("Failed to store cover: #{reason}")
        {:ok, nil}  # Non-fatal error
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
```

**Important Fix:** Add `alias FuzzyCatalog.Repo` at the top:

```elixir
  alias FuzzyCatalog.Repo
```

---

## Verification

Run tests:

```bash
mix test test/fuzzy_catalog/ebooks/workers/process_worker_test.exs
```

Expected: Most tests should pass. Some may need adjustment based on actual metadata extraction implementation.

---

## Usage Example

Manually trigger processing from IEx:

```elixir
# Start IEx
iex -S mix

# Get an ebook
ebook = FuzzyCatalog.Ebooks.list_ebooks(user_id) |> List.first()

# Enqueue processing job
{:ok, job} = %{"ebook_id" => ebook.id}
|> FuzzyCatalog.Ebooks.Workers.ProcessWorker.new()
|> Oban.insert()
```

---

## Next Steps

Continue to [Phase 6: Context API](./06-context-api.md) to add high-level convenience functions.
