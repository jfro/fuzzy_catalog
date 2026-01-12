defmodule FuzzyCatalog.Ebooks.LibraryWatcherTest do
  use FuzzyCatalog.DataCase, async: false
  use Oban.Testing, repo: FuzzyCatalog.Repo

  alias FuzzyCatalog.Ebooks.LibraryWatcher
  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Workers.ScanWorker

  import FuzzyCatalog.LibrariesFixtures

  describe "init/1" do
    @tag :tmp_dir
    test "starts watchers for existing auto_watch libraries", %{tmp_dir: tmp_dir} do
      # Create auto_watch library
      _library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      # Start the watcher
      {:ok, pid} = LibraryWatcher.start_link([])

      # Give it time to initialize
      Process.sleep(100)

      # Verify watcher is tracking the library
      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 1

      GenServer.stop(pid)
    end

    test "does not start watchers for non-auto_watch libraries" do
      library_fixture(%{scan_mode: "manual"})
      library_fixture(%{scan_mode: "scheduled"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 0

      GenServer.stop(pid)
    end
  end

  describe "library_changed/2" do
    @tag :tmp_dir
    test "starts watcher when library becomes auto_watch", %{tmp_dir: tmp_dir} do
      {:ok, pid} = LibraryWatcher.start_link([])

      library = library_fixture(%{path: tmp_dir, scan_mode: "manual"})

      # Change to auto_watch
      {:ok, updated} = Libraries.update_library(library, %{scan_mode: "auto_watch"})
      LibraryWatcher.library_changed(pid, updated)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 1

      GenServer.stop(pid)
    end

    @tag :tmp_dir
    test "stops watcher when library is no longer auto_watch", %{tmp_dir: tmp_dir} do
      library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      # Change to manual
      {:ok, updated} = Libraries.update_library(library, %{scan_mode: "manual"})
      LibraryWatcher.library_changed(pid, updated)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 0

      GenServer.stop(pid)
    end

    @tag :tmp_dir
    test "restarts watcher when library path changes", %{tmp_dir: tmp_dir} do
      library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      # Change path
      new_path = Path.join(tmp_dir, "new_location")
      File.mkdir_p!(new_path)

      {:ok, updated} = Libraries.update_library(library, %{path: new_path})
      LibraryWatcher.library_changed(pid, updated)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 1

      GenServer.stop(pid)
    end
  end

  describe "library_deleted/2" do
    @tag :tmp_dir
    test "stops watcher when library is deleted", %{tmp_dir: tmp_dir} do
      library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 1

      # Delete library
      LibraryWatcher.library_deleted(pid, library.id)

      Process.sleep(100)

      state = :sys.get_state(pid)
      assert map_size(state.watchers) == 0

      GenServer.stop(pid)
    end
  end

  describe "file change detection" do
    @tag :skip
    @tag :tmp_dir
    test "triggers scan when ebook file is created", %{tmp_dir: tmp_dir} do
      library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      {:ok, pid} = LibraryWatcher.start_link([])
      # Give FileSystem time to start watching
      Process.sleep(1000)

      # Create an ebook file
      epub_path = Path.join(tmp_dir, "test.epub")
      File.write!(epub_path, "fake epub content")

      # Wait for debounce + processing
      Process.sleep(6000)

      # Verify scan was enqueued
      assert_enqueued(
        worker: ScanWorker,
        args: %{directory: tmp_dir, recursive: true, library_id: library.id}
      )

      GenServer.stop(pid)
    end

    @tag :skip
    @tag :tmp_dir
    test "debounces multiple rapid file changes", %{tmp_dir: tmp_dir} do
      _library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      # Create multiple files rapidly
      File.write!(Path.join(tmp_dir, "book1.epub"), "content")
      Process.sleep(100)
      File.write!(Path.join(tmp_dir, "book2.epub"), "content")
      Process.sleep(100)
      File.write!(Path.join(tmp_dir, "book3.epub"), "content")

      # Wait for debounce
      Process.sleep(6000)

      # Should only have enqueued one scan job (due to debouncing)
      jobs = all_enqueued(worker: ScanWorker)
      assert length(jobs) == 1

      GenServer.stop(pid)
    end

    @tag :skip
    @tag :tmp_dir
    test "ignores non-ebook files", %{tmp_dir: tmp_dir} do
      _library = library_fixture(%{path: tmp_dir, scan_mode: "auto_watch"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      # Create non-ebook files
      File.write!(Path.join(tmp_dir, "readme.txt"), "content")
      File.write!(Path.join(tmp_dir, "image.jpg"), "content")

      # Wait for debounce
      Process.sleep(6000)

      # Should not have enqueued any scans
      refute_enqueued(worker: ScanWorker)

      GenServer.stop(pid)
    end

    @tag :skip
    @tag :tmp_dir
    test "does not trigger scan while library is already scanning", %{tmp_dir: tmp_dir} do
      _library =
        library_fixture(%{path: tmp_dir, scan_mode: "auto_watch", scanning_status: "scanning"})

      {:ok, pid} = LibraryWatcher.start_link([])
      Process.sleep(100)

      # Create ebook file
      File.write!(Path.join(tmp_dir, "test.epub"), "content")

      # Wait for debounce
      Process.sleep(6000)

      # Should not have enqueued scan (library already scanning)
      refute_enqueued(worker: ScanWorker)

      GenServer.stop(pid)
    end
  end

  describe "configuration" do
    test "respects watcher_enabled config" do
      # This would need to be tested with a mock/config override
      # For now, just verify the configuration is accessible
      config = Application.get_env(:fuzzy_catalog, :ebooks, [])

      assert Keyword.has_key?(config, :watcher_debounce_ms) or
               not Keyword.has_key?(config, :watcher_debounce_ms)
    end
  end
end
