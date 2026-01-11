defmodule FuzzyCatalog.Ebooks.LibrariesTest do
  use FuzzyCatalog.DataCase

  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Library

  import FuzzyCatalog.LibrariesFixtures

  describe "list_libraries/0" do
    test "returns all libraries" do
      library1 = library_fixture(%{name: "Library 1"})
      library2 = library_fixture(%{name: "Library 2"})

      libraries = Libraries.list_libraries()

      assert length(libraries) == 2
      assert Enum.any?(libraries, &(&1.id == library1.id))
      assert Enum.any?(libraries, &(&1.id == library2.id))
    end

    test "returns empty list when no libraries" do
      assert Libraries.list_libraries() == []
    end
  end

  describe "get_library!/1" do
    test "returns the library with given id" do
      library = library_fixture()
      fetched = Libraries.get_library!(library.id)

      assert fetched.id == library.id
      assert fetched.name == library.name
    end

    test "raises Ecto.NoResultsError if library does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Libraries.get_library!(999)
      end
    end
  end

  describe "create_library/1" do
    test "with valid data creates a library" do
      attrs = %{
        name: "New Library",
        path: "/home/user/new",
        scan_mode: "manual"
      }

      assert {:ok, %Library{} = library} = Libraries.create_library(attrs)
      assert library.name == "New Library"
      assert library.path == "/home/user/new"
      assert library.scan_mode == "manual"
    end

    test "with invalid data returns error changeset" do
      # Missing required name
      attrs = %{path: "/home/user/books"}

      assert {:error, %Ecto.Changeset{}} = Libraries.create_library(attrs)
    end

    test "returns error for duplicate path" do
      library = library_fixture()

      attrs = %{
        name: "Duplicate",
        path: library.path,
        scan_mode: "manual"
      }

      assert {:error, %Ecto.Changeset{} = changeset} = Libraries.create_library(attrs)
      assert "has already been taken" in errors_on(changeset).path
    end
  end

  describe "update_library/2" do
    test "with valid data updates the library" do
      library = library_fixture()

      update_attrs = %{name: "Updated Name"}

      assert {:ok, %Library{} = updated} = Libraries.update_library(library, update_attrs)
      assert updated.name == "Updated Name"
      assert updated.id == library.id
    end

    test "rejects invalid scan_mode" do
      library = library_fixture()

      update_attrs = %{scan_mode: "invalid"}

      assert {:error, %Ecto.Changeset{} = changeset} =
               Libraries.update_library(library, update_attrs)

      assert "is invalid" in errors_on(changeset).scan_mode
    end
  end

  describe "delete_library/1" do
    test "deletes the library" do
      library = library_fixture()

      assert {:ok, %Library{}} = Libraries.delete_library(library)
      assert_raise Ecto.NoResultsError, fn -> Libraries.get_library!(library.id) end
    end
  end

  describe "change_library/2" do
    test "returns a library changeset" do
      library = library_fixture()
      assert %Ecto.Changeset{} = Libraries.change_library(library)
    end

    test "returns a library changeset with changes" do
      library = library_fixture()
      changeset = Libraries.change_library(library, %{name: "Changed"})

      assert changeset.changes.name == "Changed"
    end
  end

  describe "list_libraries_by_scan_mode/1" do
    test "filters libraries by scan_mode" do
      _manual1 = library_fixture(%{scan_mode: "manual"})
      auto_watch1 = library_fixture(%{scan_mode: "auto_watch"})
      auto_watch2 = library_fixture(%{scan_mode: "auto_watch"})
      _scheduled1 = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      auto_watch_libs = Libraries.list_libraries_by_scan_mode("auto_watch")

      assert length(auto_watch_libs) == 2
      assert Enum.all?(auto_watch_libs, &(&1.scan_mode == "auto_watch"))
      assert Enum.any?(auto_watch_libs, &(&1.id == auto_watch1.id))
      assert Enum.any?(auto_watch_libs, &(&1.id == auto_watch2.id))
    end

    test "returns empty list when no libraries match" do
      library_fixture(%{scan_mode: "manual"})

      assert Libraries.list_libraries_by_scan_mode("auto_watch") == []
    end
  end

  describe "list_auto_watch_libraries/0" do
    test "returns only auto_watch libraries" do
      _manual = library_fixture(%{scan_mode: "manual"})
      auto_watch = library_fixture(%{scan_mode: "auto_watch"})
      _scheduled = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      auto_watch_libs = Libraries.list_auto_watch_libraries()

      assert length(auto_watch_libs) == 1
      assert hd(auto_watch_libs).id == auto_watch.id
    end
  end

  describe "list_scheduled_libraries/0" do
    test "returns only scheduled libraries" do
      _manual = library_fixture(%{scan_mode: "manual"})
      _auto_watch = library_fixture(%{scan_mode: "auto_watch"})
      scheduled = library_fixture(%{scan_mode: "scheduled", schedule: "0 * * * *"})

      scheduled_libs = Libraries.list_scheduled_libraries()

      assert length(scheduled_libs) == 1
      assert hd(scheduled_libs).id == scheduled.id
    end
  end

  describe "mark_scanning/1" do
    test "updates scanning_status to scanning" do
      library = library_fixture()

      assert {:ok, updated} = Libraries.mark_scanning(library)
      assert updated.scanning_status == "scanning"
    end
  end

  describe "mark_scan_complete/1" do
    test "updates scanning_status to idle and sets last_scanned_at" do
      library = library_fixture()
      Libraries.mark_scanning(library)

      assert {:ok, updated} = Libraries.mark_scan_complete(library)
      assert updated.scanning_status == "idle"
      assert updated.last_scanned_at != nil
      assert updated.last_scan_error == nil
    end
  end

  describe "mark_scan_failed/2" do
    test "updates scanning_status to failed and sets error" do
      library = library_fixture()
      Libraries.mark_scanning(library)

      error_msg = "File not found"

      assert {:ok, updated} = Libraries.mark_scan_failed(library, error_msg)
      assert updated.scanning_status == "failed"
      assert updated.last_scan_error == error_msg
    end
  end

  describe "scanning?/1" do
    test "returns true when library is scanning" do
      library = library_fixture()
      {:ok, scanning_lib} = Libraries.mark_scanning(library)

      assert Libraries.scanning?(scanning_lib) == true
    end

    test "returns false when library is idle" do
      library = library_fixture()

      assert Libraries.scanning?(library) == false
    end

    test "returns false when library is failed" do
      library = library_fixture()
      {:ok, failed_lib} = Libraries.mark_scan_failed(library, "Error")

      assert Libraries.scanning?(failed_lib) == false
    end
  end
end
