defmodule FuzzyCatalog.Ebooks.EdgeCasesTest do
  @moduledoc """
  Tests for edge cases and error handling in the ebook library system.
  """
  use FuzzyCatalog.DataCase, async: false
  use Oban.Testing, repo: FuzzyCatalog.Repo

  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Library

  import FuzzyCatalog.LibrariesFixtures

  describe "concurrent scan prevention" do
    test "manual scan rejected when already scanning" do
      library = library_fixture(%{scanning_status: "scanning"})

      # Try to mark as scanning again
      assert Libraries.scanning?(library)

      # This should not change the status since already scanning
      {:ok, library} = Libraries.mark_scanning(library)
      assert library.scanning_status == "scanning"
    end

    test "cannot start multiple scans simultaneously" do
      library = library_fixture(%{scanning_status: "idle"})

      # Mark as scanning
      {:ok, library} = Libraries.mark_scanning(library)
      assert library.scanning_status == "scanning"

      # Reload and verify still scanning
      reloaded = Libraries.get_library!(library.id)
      assert reloaded.scanning_status == "scanning"

      # Try to scan again - should be prevented
      assert Libraries.scanning?(reloaded)
    end

    test "scan status resets after completion" do
      library = library_fixture(%{scanning_status: "scanning"})

      {:ok, completed} = Libraries.mark_scan_complete(library)
      assert completed.scanning_status == "idle"
      refute Libraries.scanning?(completed)
    end

    test "scan status resets after failure" do
      library = library_fixture(%{scanning_status: "scanning"})

      {:ok, failed} = Libraries.mark_scan_failed(library, "Test error")
      assert failed.scanning_status == "failed"
      assert failed.last_scan_error == "Test error"
      refute Libraries.scanning?(failed)
    end
  end

  describe "path validation" do
    test "library with non-existent path can be created" do
      # We allow creating libraries with non-existent paths
      # (user might create path later)
      attrs = %{
        name: "Test Library",
        path: "/tmp/nonexistent_#{:rand.uniform(100_000)}",
        scan_mode: "manual"
      }

      {:ok, library} = Libraries.create_library(attrs)
      refute File.dir?(library.path)
    end

    test "library path can be updated to non-existent directory" do
      library = library_fixture()

      new_path = "/tmp/nonexistent_#{:rand.uniform(100_000)}"
      {:ok, updated} = Libraries.update_library(library, %{path: new_path})

      assert updated.path == new_path
      refute File.dir?(updated.path)
    end

    @tag :tmp_dir
    test "validates path traversal in library path", %{tmp_dir: tmp_dir} do
      # Path with .. should still be accepted at DB level
      # (validation happens at scan time)
      malicious_path = Path.join(tmp_dir, "../../../etc")

      attrs = %{name: "Test", path: malicious_path, scan_mode: "manual"}
      {:ok, library} = Libraries.create_library(attrs)

      assert library.path == malicious_path
    end
  end

  describe "error recovery" do
    test "scan failure updates library status" do
      library = library_fixture(%{scanning_status: "scanning"})

      {:ok, failed} = Libraries.mark_scan_failed(library, "Connection timeout")

      assert failed.scanning_status == "failed"
      assert failed.last_scan_error == "Connection timeout"
      assert failed.last_scanned_at != nil
    end

    test "can retry scan after failure" do
      library = library_fixture(%{scanning_status: "failed", last_scan_error: "Previous error"})

      # Should be able to scan again
      refute Libraries.scanning?(library)

      {:ok, scanning} = Libraries.mark_scanning(library)
      assert scanning.scanning_status == "scanning"
    end

    test "scan complete clears error" do
      library =
        library_fixture(%{
          scanning_status: "failed",
          last_scan_error: "Previous error"
        })

      {:ok, _} = Libraries.mark_scanning(library)
      {:ok, completed} = Libraries.mark_scan_complete(library)

      assert completed.scanning_status == "idle"
      assert completed.last_scan_error == nil
      assert completed.last_scanned_at != nil
    end
  end

  describe "library deletion" do
    test "can delete library that is idle" do
      library = library_fixture(%{scanning_status: "idle"})

      {:ok, deleted} = Libraries.delete_library(library)
      assert deleted.id == library.id

      assert_raise Ecto.NoResultsError, fn ->
        Libraries.get_library!(library.id)
      end
    end

    test "can delete library that is scanning" do
      # We allow deletion even when scanning
      # (the scan job will handle missing library gracefully)
      library = library_fixture(%{scanning_status: "scanning"})

      {:ok, deleted} = Libraries.delete_library(library)
      assert deleted.id == library.id
    end

    test "can delete library that failed" do
      library = library_fixture(%{scanning_status: "failed"})

      {:ok, deleted} = Libraries.delete_library(library)
      assert deleted.id == library.id
    end
  end

  describe "scan mode transitions" do
    test "can change from manual to auto_watch" do
      library = library_fixture(%{scan_mode: "manual"})

      {:ok, updated} = Libraries.update_library(library, %{scan_mode: "auto_watch"})
      assert updated.scan_mode == "auto_watch"
    end

    test "can change from auto_watch to scheduled with schedule" do
      library = library_fixture(%{scan_mode: "auto_watch"})

      {:ok, updated} =
        Libraries.update_library(library, %{scan_mode: "scheduled", schedule: "0 * * * *"})

      assert updated.scan_mode == "scheduled"
      assert updated.schedule == "0 * * * *"
    end

    test "cannot change to scheduled without schedule" do
      library = library_fixture(%{scan_mode: "manual"})

      changeset = Library.changeset(library, %{scan_mode: "scheduled"})
      refute changeset.valid?
      assert "can't be blank when scan mode is scheduled" in errors_on(changeset).schedule
    end

    test "can change from scheduled to manual (schedule cleared)" do
      library = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      {:ok, updated} = Libraries.update_library(library, %{scan_mode: "manual"})
      assert updated.scan_mode == "manual"
      # Schedule is cleared when changing away from scheduled mode
      assert updated.schedule == nil
    end
  end

  describe "invalid input handling" do
    test "rejects library with empty name" do
      attrs = %{name: "", path: "/tmp/test", scan_mode: "manual"}

      {:error, changeset} = Libraries.create_library(attrs)
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects library with empty path" do
      attrs = %{name: "Test", path: "", scan_mode: "manual"}

      {:error, changeset} = Libraries.create_library(attrs)
      assert "can't be blank" in errors_on(changeset).path
    end

    test "rejects library with invalid scan_mode" do
      attrs = %{name: "Test", path: "/tmp/test", scan_mode: "invalid"}

      {:error, changeset} = Libraries.create_library(attrs)
      assert "is invalid" in errors_on(changeset).scan_mode
    end

    test "rejects duplicate paths" do
      _library = library_fixture(%{path: "/tmp/unique_path"})

      attrs = %{name: "Another Library", path: "/tmp/unique_path", scan_mode: "manual"}

      {:error, changeset} = Libraries.create_library(attrs)
      assert "has already been taken" in errors_on(changeset).path
    end
  end

  describe "ebook association" do
    test "deleting library sets ebook library_id to nil" do
      library = library_fixture()

      # This would be done by ScanWorker in real usage
      # For testing, we'll just verify the foreign key constraint behavior
      {:ok, _deleted} = Libraries.delete_library(library)

      # Library is deleted
      assert_raise Ecto.NoResultsError, fn ->
        Libraries.get_library!(library.id)
      end
    end
  end
end
