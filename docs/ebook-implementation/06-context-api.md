# Phase 6: Enhanced Context API

Add high-level convenience functions to the Ebooks context for triggering scans and managing ebooks.

## Overview

This phase enhances the Ebooks context with functions that:
- Trigger directory scans
- Trigger file reprocessing
- Query ebooks by processing status

These functions provide a clean API for controllers, LiveViews, or admin interfaces.

## Step 6.1: Add Context API Tests

**File:** `test/fuzzy_catalog/ebooks_test.exs`

Add these tests to the existing file:

```elixir
  describe "trigger_scan/1" do
    test "enqueues ScanWorker job" do
      user = user_fixture()

      assert {:ok, job} = Ebooks.trigger_scan(
        directory: "/path/to/ebooks",
        user_id: user.id,
        recursive: true
      )

      assert_enqueued worker: FuzzyCatalog.Ebooks.Workers.ScanWorker, args: %{
        "directory" => "/path/to/ebooks",
        "user_id" => user.id,
        "recursive" => true
      }
    end

    test "defaults recursive to true" do
      user = user_fixture()

      assert {:ok, job} = Ebooks.trigger_scan(
        directory: "/path/to/ebooks",
        user_id: user.id
      )

      assert_enqueued worker: FuzzyCatalog.Ebooks.Workers.ScanWorker, args: %{
        "directory" => "/path/to/ebooks",
        "user_id" => user.id,
        "recursive" => true
      }
    end
  end

  describe "trigger_reprocess/1" do
    test "enqueues ProcessWorker job for ebook" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)

      assert {:ok, job} = Ebooks.trigger_reprocess(ebook.id)

      assert_enqueued worker: FuzzyCatalog.Ebooks.Workers.ProcessWorker, args: %{
        "ebook_id" => ebook.id
      }
    end

    test "accepts enable_fuzzy_matching option" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)

      assert {:ok, job} = Ebooks.trigger_reprocess(ebook.id, enable_fuzzy_matching: true)

      assert_enqueued worker: FuzzyCatalog.Ebooks.Workers.ProcessWorker, args: %{
        "ebook_id" => ebook.id,
        "enable_fuzzy_matching" => true
      }
    end
  end

  describe "list_pending_ebooks/1" do
    test "returns ebooks with pending processing status" do
      user = user_fixture()
      pending1 = ebook_fixture(user_id: user.id, processing_status: "pending")
      pending2 = ebook_fixture(user_id: user.id, processing_status: "pending")
      _completed = ebook_fixture(user_id: user.id, processing_status: "completed")
      _failed = ebook_fixture(user_id: user.id, processing_status: "failed")

      pending = Ebooks.list_pending_ebooks(user.id)

      assert length(pending) == 2
      assert Enum.all?(pending, &(&1.processing_status == "pending"))
      ids = Enum.map(pending, & &1.id)
      assert pending1.id in ids
      assert pending2.id in ids
    end

    test "returns empty list when no pending ebooks" do
      user = user_fixture()
      _completed = ebook_fixture(user_id: user.id, processing_status: "completed")

      assert Ebooks.list_pending_ebooks(user.id) == []
    end
  end

  describe "list_failed_ebooks/1" do
    test "returns ebooks with failed processing status" do
      user = user_fixture()
      failed1 = ebook_fixture(user_id: user.id, processing_status: "failed")
      failed2 = ebook_fixture(user_id: user.id, processing_status: "failed")
      _completed = ebook_fixture(user_id: user.id, processing_status: "completed")

      failed = Ebooks.list_failed_ebooks(user.id)

      assert length(failed) == 2
      assert Enum.all?(failed, &(&1.processing_status == "failed"))
    end
  end

  describe "delete_ebook/1" do
    test "deletes the ebook" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)

      assert {:ok, deleted} = Ebooks.delete_ebook(ebook)
      assert deleted.id == ebook.id

      assert_raise Ecto.NoResultsError, fn ->
        Ebooks.get_ebook!(ebook.id, user.id)
      end
    end
  end
```

---

## Step 6.2: Enhance Ebooks Context

**File:** `lib/fuzzy_catalog/ebooks.ex`

Add these functions to the existing module:

```elixir
  alias FuzzyCatalog.Ebooks.Workers.{ScanWorker, ProcessWorker}

  @doc """
  Triggers a directory scan for ebook files.

  ## Options

  - `:directory` - Required. Path to scan
  - `:user_id` - Required. User who owns the ebooks
  - `:recursive` - Optional. Whether to scan subdirectories (default: true)

  ## Examples

      iex> trigger_scan(directory: "/ebooks", user_id: 1)
      {:ok, %Oban.Job{}}

      iex> trigger_scan(directory: "/ebooks", user_id: 1, recursive: false)
      {:ok, %Oban.Job{}}
  """
  def trigger_scan(opts) do
    %{
      directory: Keyword.fetch!(opts, :directory),
      user_id: Keyword.fetch!(opts, :user_id),
      recursive: Keyword.get(opts, :recursive, true)
    }
    |> ScanWorker.new()
    |> Oban.insert()
  end

  @doc """
  Triggers reprocessing of an ebook.

  ## Options

  - `:enable_fuzzy_matching` - Optional. Enable fuzzy title/author matching (default: false)

  ## Examples

      iex> trigger_reprocess(123)
      {:ok, %Oban.Job{}}

      iex> trigger_reprocess(123, enable_fuzzy_matching: true)
      {:ok, %Oban.Job{}}
  """
  def trigger_reprocess(ebook_id, opts \\ []) do
    args = %{ebook_id: ebook_id}
    args = if Keyword.get(opts, :enable_fuzzy_matching, false) do
      Map.put(args, :enable_fuzzy_matching, true)
    else
      args
    end

    args
    |> ProcessWorker.new()
    |> Oban.insert()
  end

  @doc """
  Lists ebooks with pending processing status for a user.

  ## Examples

      iex> list_pending_ebooks(123)
      [%Ebook{}, ...]
  """
  def list_pending_ebooks(user_id) do
    Ebook
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.processing_status == "pending")
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists ebooks with failed processing status for a user.

  ## Examples

      iex> list_failed_ebooks(123)
      [%Ebook{}, ...]
  """
  def list_failed_ebooks(user_id) do
    Ebook
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.processing_status == "failed")
    |> order_by([e], desc: e.last_processed_at)
    |> Repo.all()
  end

  @doc """
  Deletes an ebook.

  ## Examples

      iex> delete_ebook(ebook)
      {:ok, %Ebook{}}

      iex> delete_ebook(ebook)
      {:error, %Ecto.Changeset{}}
  """
  def delete_ebook(%Ebook{} = ebook) do
    Repo.delete(ebook)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ebook changes.

  ## Examples

      iex> change_ebook(ebook)
      %Ecto.Changeset{data: %Ebook{}}
  """
  def change_ebook(%Ebook{} = ebook, attrs \\ %{}) do
    Ebook.changeset(ebook, attrs)
  end
```

---

## Verification

Run all ebooks tests:

```bash
mix test test/fuzzy_catalog/ebooks_test.exs
```

All tests should pass ✅

---

## Usage Examples

### Trigger a Scan

```elixir
# From a controller or LiveView
user = get_current_user(conn)

{:ok, job} = FuzzyCatalog.Ebooks.trigger_scan(
  directory: "/mnt/storage/ebooks",
  user_id: user.id,
  recursive: true
)
```

### Reprocess Failed Ebooks

```elixir
# Get all failed ebooks
failed_ebooks = FuzzyCatalog.Ebooks.list_failed_ebooks(user.id)

# Reprocess each with fuzzy matching enabled
Enum.each(failed_ebooks, fn ebook ->
  FuzzyCatalog.Ebooks.trigger_reprocess(ebook.id, enable_fuzzy_matching: true)
end)
```

### Check Processing Status

```elixir
# Get pending count
pending_count = FuzzyCatalog.Ebooks.list_pending_ebooks(user.id) |> length()

# Get failed count
failed_count = FuzzyCatalog.Ebooks.list_failed_ebooks(user.id) |> length()

# Display in UI
assigns = %{
  pending_count: pending_count,
  failed_count: failed_count
}
```

---

## Next Steps

Continue to [Phase 7: Configuration](./07-configuration.md) for final configuration and verification.
