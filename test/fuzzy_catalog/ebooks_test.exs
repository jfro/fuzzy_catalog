defmodule FuzzyCatalog.EbooksTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  alias FuzzyCatalog.Ebooks
  import FuzzyCatalog.EbooksFixtures

  describe "list_ebooks/0" do
    test "returns all ebooks" do
      ebook1 = ebook_fixture()
      ebook2 = ebook_fixture()

      ebooks = Ebooks.list_ebooks()

      assert length(ebooks) == 2
      assert Enum.any?(ebooks, &(&1.id == ebook1.id))
      assert Enum.any?(ebooks, &(&1.id == ebook2.id))
    end
  end

  describe "get_ebook!/1" do
    test "returns the ebook with given id" do
      ebook = ebook_fixture()

      assert Ebooks.get_ebook!(ebook.id).id == ebook.id
    end

    test "raises if ebook doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Ebooks.get_ebook!(999_999)
      end
    end
  end

  describe "create_ebook/1" do
    test "creates ebook with valid data" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1_024_000
      }

      assert {:ok, ebook} = Ebooks.create_ebook(attrs)
      assert ebook.file_path == "/path/to/book.epub"
    end

    test "returns error with invalid data" do
      assert {:error, changeset} = Ebooks.create_ebook(%{})
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_ebook/2" do
    test "updates ebook with valid data" do
      ebook = ebook_fixture()

      assert {:ok, updated} =
               Ebooks.update_ebook(ebook, %{
                 extracted_title: "New Title",
                 processing_status: "completed"
               })

      assert updated.extracted_title == "New Title"
      assert updated.processing_status == "completed"
    end
  end

  describe "get_ebook_by_path/1" do
    test "returns ebook by file path" do
      ebook = ebook_fixture(file_path: "/unique/path/book.epub")

      assert found = Ebooks.get_ebook_by_path("/unique/path/book.epub")
      assert found.id == ebook.id
    end

    test "returns nil if path doesn't exist" do
      assert is_nil(Ebooks.get_ebook_by_path("/nonexistent.epub"))
    end
  end

  describe "trigger_scan/1" do
    test "enqueues ScanWorker job" do
      assert {:ok, _job} =
               Ebooks.trigger_scan(
                 directory: "/path/to/ebooks",
                 recursive: true
               )

      assert_enqueued(
        worker: FuzzyCatalog.Ebooks.Workers.ScanWorker,
        args: %{
          "directory" => "/path/to/ebooks",
          "recursive" => true
        }
      )
    end

    test "defaults recursive to true" do
      assert {:ok, _job} = Ebooks.trigger_scan(directory: "/path/to/ebooks")

      assert_enqueued(
        worker: FuzzyCatalog.Ebooks.Workers.ScanWorker,
        args: %{
          "directory" => "/path/to/ebooks",
          "recursive" => true
        }
      )
    end
  end

  describe "trigger_reprocess/1" do
    test "enqueues ProcessWorker job for ebook" do
      ebook = ebook_fixture()

      assert {:ok, _job} = Ebooks.trigger_reprocess(ebook.id)

      assert_enqueued(
        worker: FuzzyCatalog.Ebooks.Workers.ProcessWorker,
        args: %{
          "ebook_id" => ebook.id
        }
      )
    end

    test "accepts enable_fuzzy_matching option" do
      ebook = ebook_fixture()

      assert {:ok, _job} = Ebooks.trigger_reprocess(ebook.id, enable_fuzzy_matching: true)

      assert_enqueued(
        worker: FuzzyCatalog.Ebooks.Workers.ProcessWorker,
        args: %{
          "ebook_id" => ebook.id,
          "enable_fuzzy_matching" => true
        }
      )
    end
  end

  describe "list_pending_ebooks/0" do
    test "returns ebooks with pending processing status" do
      pending1 = ebook_fixture(processing_status: "pending")
      pending2 = ebook_fixture(processing_status: "pending")
      _completed = ebook_fixture(processing_status: "completed")
      _failed = ebook_fixture(processing_status: "failed")

      pending = Ebooks.list_pending_ebooks()

      assert length(pending) == 2
      assert Enum.all?(pending, &(&1.processing_status == "pending"))
      ids = Enum.map(pending, & &1.id)
      assert pending1.id in ids
      assert pending2.id in ids
    end

    test "returns empty list when no pending ebooks" do
      _completed = ebook_fixture(processing_status: "completed")

      assert Ebooks.list_pending_ebooks() == []
    end
  end

  describe "list_failed_ebooks/0" do
    test "returns ebooks with failed processing status" do
      _failed1 = ebook_fixture(processing_status: "failed")
      _failed2 = ebook_fixture(processing_status: "failed")
      _completed = ebook_fixture(processing_status: "completed")

      failed = Ebooks.list_failed_ebooks()

      assert length(failed) == 2
      assert Enum.all?(failed, &(&1.processing_status == "failed"))
    end
  end

  describe "delete_ebook/1" do
    test "deletes the ebook" do
      ebook = ebook_fixture()

      assert {:ok, deleted} = Ebooks.delete_ebook(ebook)
      assert deleted.id == ebook.id

      assert_raise Ecto.NoResultsError, fn ->
        Ebooks.get_ebook!(ebook.id)
      end
    end
  end

  describe "change_ebook/2" do
    test "returns a changeset" do
      ebook = ebook_fixture()

      changeset = Ebooks.change_ebook(ebook)

      assert %Ecto.Changeset{} = changeset
      assert changeset.data == ebook
    end

    test "returns a changeset with changes" do
      ebook = ebook_fixture()

      changeset = Ebooks.change_ebook(ebook, %{extracted_title: "New Title"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes.extracted_title == "New Title"
    end
  end
end
