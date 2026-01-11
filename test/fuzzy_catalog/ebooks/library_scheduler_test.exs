defmodule FuzzyCatalog.Ebooks.LibrarySchedulerTest do
  use FuzzyCatalog.DataCase, async: false
  use Oban.Testing, repo: FuzzyCatalog.Repo

  alias FuzzyCatalog.Ebooks.LibraryScheduler
  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Workers.ScanWorker

  import FuzzyCatalog.LibrariesFixtures

  describe "init/1" do
    test "loads scheduled libraries on startup" do
      # Create scheduled libraries
      _lib1 = library_fixture(%{name: "Lib 1", scan_mode: "scheduled", schedule: "0 * * * *"})
      _lib2 = library_fixture(%{name: "Lib 2", scan_mode: "scheduled", schedule: "0 */6 * * *"})

      # Create non-scheduled library
      _lib3 = library_fixture(%{name: "Lib 3", scan_mode: "manual"})

      {:ok, pid} = LibraryScheduler.start_link([])

      state = :sys.get_state(pid)
      assert length(state.libraries) == 2

      GenServer.stop(pid)
    end

    test "starts with empty state when no scheduled libraries" do
      {:ok, pid} = LibraryScheduler.start_link([])

      state = :sys.get_state(pid)
      assert state.libraries == []

      GenServer.stop(pid)
    end
  end

  describe "library_changed/2" do
    test "reloads schedule when library becomes scheduled" do
      {:ok, pid} = LibraryScheduler.start_link([])

      library = library_fixture(%{scan_mode: "manual"})

      # Change to scheduled
      {:ok, updated} =
        Libraries.update_library(library, %{scan_mode: "scheduled", schedule: "0 * * * *"})

      LibraryScheduler.library_changed(pid, updated)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert length(state.libraries) == 1

      GenServer.stop(pid)
    end

    test "reloads schedule when scheduled library updated" do
      library = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      {:ok, pid} = LibraryScheduler.start_link([])
      Process.sleep(100)

      # Change schedule
      {:ok, updated} = Libraries.update_library(library, %{schedule: "0 */2 * * *"})
      LibraryScheduler.library_changed(pid, updated)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert length(state.libraries) == 1

      GenServer.stop(pid)
    end

    test "reloads schedule when library is no longer scheduled" do
      library = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      {:ok, pid} = LibraryScheduler.start_link([])
      Process.sleep(100)

      # Change to manual
      {:ok, updated} = Libraries.update_library(library, %{scan_mode: "manual"})
      LibraryScheduler.library_changed(pid, updated)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert state.libraries == []

      GenServer.stop(pid)
    end
  end

  describe "library_deleted/2" do
    test "reloads schedule when scheduled library is deleted" do
      library = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      {:ok, pid} = LibraryScheduler.start_link([])
      Process.sleep(100)

      state = :sys.get_state(pid)
      assert length(state.libraries) == 1

      # Delete library from database
      {:ok, _deleted} = Libraries.delete_library(library)

      # Notify scheduler
      LibraryScheduler.library_deleted(pid, library.id)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert state.libraries == []

      GenServer.stop(pid)
    end
  end

  describe "perform_scheduled_scan/1" do
    test "enqueues ScanWorker for the library" do
      library = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      LibraryScheduler.perform_scheduled_scan(library.id)

      # Verify scan was enqueued
      assert_enqueued(
        worker: ScanWorker,
        args: %{directory: library.path, recursive: true, library_id: library.id}
      )
    end

    test "marks library as scanning" do
      library = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      LibraryScheduler.perform_scheduled_scan(library.id)

      # Reload library and check status
      reloaded = Libraries.get_library!(library.id)
      assert reloaded.scanning_status == "scanning"
    end

    test "does not enqueue scan if library already scanning" do
      library =
        library_fixture(%{
          scan_mode: "scheduled",
          schedule: "0 * * * *",
          scanning_status: "scanning"
        })

      LibraryScheduler.perform_scheduled_scan(library.id)

      # Should not have enqueued scan
      refute_enqueued(worker: ScanWorker)
    end

    test "handles deleted library gracefully" do
      # Try to scan non-existent library ID
      assert :ok = LibraryScheduler.perform_scheduled_scan(99999)

      # Should not have enqueued scan
      refute_enqueued(worker: ScanWorker)
    end
  end

  describe "cron configuration" do
    test "validates cron expressions" do
      # Valid cron expressions
      assert LibraryScheduler.valid_cron?("0 * * * *") == true
      assert LibraryScheduler.valid_cron?("*/5 * * * *") == true
      assert LibraryScheduler.valid_cron?("0 0 * * 0") == true

      # Invalid cron expressions
      assert LibraryScheduler.valid_cron?("invalid") == false
      assert LibraryScheduler.valid_cron?("") == false
      assert LibraryScheduler.valid_cron?(nil) == false
    end
  end
end
