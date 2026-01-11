defmodule FuzzyCatalog.Ebooks.LibraryTest do
  use FuzzyCatalog.DataCase

  alias FuzzyCatalog.Ebooks.Library

  describe "changeset/2" do
    test "changeset with valid data for manual mode" do
      attrs = %{
        name: "My Library",
        path: "/home/user/books",
        scan_mode: "manual"
      }

      changeset = Library.changeset(%Library{}, attrs)
      assert changeset.valid?
      assert changeset.changes.name == "My Library"
      assert changeset.changes.path == "/home/user/books"
      assert Ecto.Changeset.get_field(changeset, :scan_mode) == "manual"
    end

    test "changeset with valid data for auto_watch mode" do
      attrs = %{
        name: "Auto Library",
        path: "/home/user/auto",
        scan_mode: "auto_watch"
      }

      changeset = Library.changeset(%Library{}, attrs)
      assert changeset.valid?
      assert changeset.changes.scan_mode == "auto_watch"
    end

    test "changeset with valid data for scheduled mode" do
      attrs = %{
        name: "Scheduled Library",
        path: "/home/user/scheduled",
        scan_mode: "scheduled",
        schedule: "0 */6 * * *"
      }

      changeset = Library.changeset(%Library{}, attrs)
      assert changeset.valid?
      assert changeset.changes.scan_mode == "scheduled"
      assert changeset.changes.schedule == "0 */6 * * *"
    end

    test "changeset requires name" do
      attrs = %{
        path: "/home/user/books",
        scan_mode: "manual"
      }

      changeset = Library.changeset(%Library{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "changeset requires path" do
      attrs = %{
        name: "My Library",
        scan_mode: "manual"
      }

      changeset = Library.changeset(%Library{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).path
    end

    test "changeset defaults scan_mode to manual when not provided" do
      attrs = %{
        name: "My Library",
        path: "/home/user/books"
      }

      changeset = Library.changeset(%Library{}, attrs)
      assert changeset.valid?
      # Default value should be applied
      assert Ecto.Changeset.get_field(changeset, :scan_mode) == "manual"
    end

    test "changeset validates scan_mode is valid enum" do
      attrs = %{
        name: "My Library",
        path: "/home/user/books",
        scan_mode: "invalid_mode"
      }

      changeset = Library.changeset(%Library{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).scan_mode
    end

    test "changeset requires schedule when scan_mode is scheduled" do
      attrs = %{
        name: "Scheduled Library",
        path: "/home/user/scheduled",
        scan_mode: "scheduled"
      }

      changeset = Library.changeset(%Library{}, attrs)
      refute changeset.valid?
      assert "can't be blank when scan mode is scheduled" in errors_on(changeset).schedule
    end

    test "changeset ignores schedule when scan_mode is manual" do
      attrs = %{
        name: "Manual Library",
        path: "/home/user/manual",
        scan_mode: "manual",
        schedule: "0 */6 * * *"
      }

      changeset = Library.changeset(%Library{}, attrs)
      assert changeset.valid?
      # Schedule should be set to nil for non-scheduled modes
      assert Ecto.Changeset.get_field(changeset, :schedule) == nil
    end

    test "changeset ignores schedule when scan_mode is auto_watch" do
      attrs = %{
        name: "Auto Library",
        path: "/home/user/auto",
        scan_mode: "auto_watch",
        schedule: "0 */6 * * *"
      }

      changeset = Library.changeset(%Library{}, attrs)
      assert changeset.valid?
      # Schedule should be set to nil for non-scheduled modes
      assert Ecto.Changeset.get_field(changeset, :schedule) == nil
    end

    test "changeset validates path format" do
      attrs = %{
        name: "My Library",
        path: "not/an/absolute/path",
        scan_mode: "manual"
      }

      changeset = Library.changeset(%Library{}, attrs)
      refute changeset.valid?
      assert "must be an absolute path" in errors_on(changeset).path
    end
  end
end
