defmodule FuzzyCatalogWeb.AdminLibrariesLiveTest do
  use FuzzyCatalogWeb.ConnCase
  use Oban.Testing, repo: FuzzyCatalog.Repo

  import Phoenix.LiveViewTest
  import FuzzyCatalog.LibrariesFixtures
  import FuzzyCatalog.AccountsFixtures

  setup do
    # Create admin user
    admin_user = admin_user_fixture()
    %{admin_user: admin_user}
  end

  describe "authentication and authorization" do
    test "requires authentication", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/admin/libraries")
      assert path == ~p"/users/log-in"
    end

    test "admin can access page", %{conn: conn, admin_user: admin} do
      # Log in as admin
      conn = log_in_user(conn, admin)

      # Admin should be able to access the page
      {:ok, _view, _html} = live(conn, ~p"/admin/libraries")
    end
  end

  describe "index view" do
    test "displays all libraries", %{conn: conn, admin_user: admin} do
      library1 = library_fixture(%{name: "Library One", scan_mode: "manual"})
      library2 = library_fixture(%{name: "Library Two", scan_mode: "auto_watch"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/libraries")

      assert html =~ "Library One"
      assert html =~ "Library Two"
      assert html =~ library1.path
      assert html =~ library2.path
    end

    test "displays scan_mode badge for each library", %{conn: conn, admin_user: admin} do
      library_fixture(%{name: "Manual Lib", scan_mode: "manual"})
      library_fixture(%{name: "Auto Lib", scan_mode: "auto_watch"})
      library_fixture(%{name: "Scheduled Lib", scan_mode: "scheduled", schedule: "0 * * * *"})

      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/libraries")

      assert html =~ "manual"
      assert html =~ "auto_watch"
      assert html =~ "scheduled"
    end

    test "shows empty state when no libraries", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, _view, html} = live(conn, ~p"/admin/libraries")

      assert html =~ "No libraries"
    end
  end

  describe "create library" do
    test "clicking New Library opens modal", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      html = view |> element("button", "New Library") |> render_click()

      assert html =~ "Create Library"
      assert html =~ "name=\"library[name]\""
      assert html =~ "name=\"library[path]\""
      assert html =~ "name=\"library[scan_mode]\""
    end

    test "form has scan_mode select with manual, auto_watch, scheduled options", %{
      conn: conn,
      admin_user: admin
    } do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      html = view |> element("button", "New Library") |> render_click()

      assert html =~ "manual"
      assert html =~ "auto_watch"
      assert html =~ "scheduled"
    end

    test "schedule field visible when scan_mode is scheduled", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      # Change to scheduled mode
      html =
        view
        |> form("#library-form", library: %{scan_mode: "scheduled"})
        |> render_change()

      assert html =~ "name=\"library[schedule]\""
    end

    test "creates library with valid data for manual mode", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      view
      |> form("#library-form",
        library: %{
          name: "Test Library",
          path: "/home/test/books",
          scan_mode: "manual"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Test Library"
      assert html =~ "/home/test/books"
    end

    test "creates library with valid data for auto_watch mode", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      view
      |> form("#library-form",
        library: %{
          name: "Auto Library",
          path: "/home/test/auto",
          scan_mode: "auto_watch"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Auto Library"
      assert html =~ "auto_watch"
    end

    test "creates library with valid data for scheduled mode", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      # First change scan_mode to scheduled to show the schedule field
      view
      |> form("#library-form", library: %{scan_mode: "scheduled"})
      |> render_change()

      # Then submit the full form
      view
      |> form("#library-form",
        library: %{
          name: "Scheduled Library",
          path: "/home/test/scheduled",
          scan_mode: "scheduled",
          schedule: "0 */6 * * *"
        }
      )
      |> render_submit()

      html = render(view)
      assert html =~ "Scheduled Library"
      assert html =~ "scheduled"
    end

    test "validates required fields", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      html =
        view
        |> form("#library-form", library: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "validates schedule required when scan_mode is scheduled", %{
      conn: conn,
      admin_user: admin
    } do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      # First change to scheduled mode
      view
      |> form("#library-form", library: %{scan_mode: "scheduled"})
      |> render_change()

      # Then try to submit without schedule
      html =
        view
        |> form("#library-form",
          library: %{
            name: "Test",
            path: "/home/test",
            scan_mode: "scheduled",
            schedule: ""
          }
        )
        |> render_submit()

      assert html =~ "can&#39;t be blank when scan mode is scheduled"
    end

    test "shows flash message on success", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      view
      |> form("#library-form",
        library: %{
          name: "Test Library",
          path: "/home/test/books",
          scan_mode: "manual"
        }
      )
      |> render_submit()

      assert render(view) =~ "Library created successfully"
    end

    test "rejects duplicate path", %{conn: conn, admin_user: admin} do
      existing = library_fixture(%{path: "/home/existing"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      html =
        view
        |> form("#library-form",
          library: %{
            name: "Duplicate",
            path: existing.path,
            scan_mode: "manual"
          }
        )
        |> render_submit()

      assert html =~ "has already been taken"
    end
  end

  describe "edit library" do
    test "clicking Edit opens modal with library data", %{conn: conn, admin_user: admin} do
      library = library_fixture(%{name: "Existing Library", path: "/home/existing"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      html =
        view
        |> element("button[phx-click='open_edit_modal'][phx-value-id='#{library.id}']")
        |> render_click()

      assert html =~ "Edit Library"
      assert html =~ "Existing Library"
      assert html =~ "/home/existing"
    end

    test "updates library with valid data", %{conn: conn, admin_user: admin} do
      library = library_fixture(%{name: "Old Name", scan_mode: "manual"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{library.id}']")
      |> render_click()

      view
      |> form("#library-form", library: %{name: "New Name"})
      |> render_submit()

      html = render(view)
      assert html =~ "New Name"
      assert html =~ "Library updated successfully"
    end

    test "changing scan_mode updates form", %{conn: conn, admin_user: admin} do
      library = library_fixture(%{scan_mode: "manual"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{library.id}']")
      |> render_click()

      # Change to scheduled mode
      html =
        view
        |> form("#library-form", library: %{scan_mode: "scheduled"})
        |> render_change()

      # Schedule field should now be visible
      assert html =~ "name=\"library[schedule]\""
    end

    test "prevents duplicate paths", %{conn: conn, admin_user: admin} do
      _existing = library_fixture(%{path: "/home/existing"})
      library = library_fixture(%{path: "/home/other"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{library.id}']")
      |> render_click()

      html =
        view
        |> form("#library-form", library: %{path: "/home/existing"})
        |> render_submit()

      assert html =~ "has already been taken"
    end

    test "shows flash message on success", %{conn: conn, admin_user: admin} do
      library = library_fixture()

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='open_edit_modal'][phx-value-id='#{library.id}']")
      |> render_click()

      view
      |> form("#library-form", library: %{name: "Updated"})
      |> render_submit()

      assert render(view) =~ "Library updated successfully"
    end
  end

  describe "tree-view picker" do
    test "opens tree-view picker when Browse button clicked", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()

      html = view |> element("button", "Browse") |> render_click()

      assert html =~ "Select Directory"
      assert html =~ "directory-tree"
    end

    test "tree-view allows expanding directories", %{conn: conn, admin_user: admin} do
      # Create a test directory structure
      tmp_dir = System.tmp_dir!()
      test_root = Path.join(tmp_dir, "picker_test_#{:rand.uniform(1_000_000)}")
      subdir_path = Path.join(test_root, "subdir")
      File.mkdir_p!(Path.join(subdir_path, "nested"))

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()
      view |> element("button", "Browse") |> render_click()

      # Set initial path (this expands the root)
      view |> render_hook("set_tree_root", %{"path" => test_root})

      # Root should show subdir since it's expanded
      html = render(view)
      assert html =~ "subdir"

      # Now expand the subdir to see its nested directory
      html =
        view
        |> element("button[phx-click='expand_directory'][phx-value-path='#{subdir_path}']")
        |> render_click()

      assert html =~ "nested"

      # Cleanup
      File.rm_rf!(test_root)
    end

    test "selecting directory updates path field", %{conn: conn, admin_user: admin} do
      tmp_dir = System.tmp_dir!()

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()
      view |> element("button", "Browse") |> render_click()

      # Select a directory
      view
      |> element("button[phx-click='select_directory'][phx-value-path='#{tmp_dir}']")
      |> render_click()

      # Confirm selection
      view |> element("button", "Use This Path") |> render_click()

      html = render(view)
      assert html =~ tmp_dir
    end

    test "can close tree-view picker without selecting", %{conn: conn, admin_user: admin} do
      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view |> element("button", "New Library") |> render_click()
      view |> element("button", "Browse") |> render_click()

      # Use phx-click to be specific about which Cancel button
      html = view |> element("button[phx-click='close_tree_picker']") |> render_click()

      refute html =~ "Select Directory"
    end
  end

  describe "manual scan" do
    test "clicking Scan Now enqueues ScanWorker job", %{conn: conn, admin_user: admin} do
      library = library_fixture(%{name: "Test Library", path: System.tmp_dir!()})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='scan_now'][phx-value-id='#{library.id}']")
      |> render_click()

      # Verify job was enqueued
      assert_enqueued(
        worker: FuzzyCatalog.Ebooks.Workers.ScanWorker,
        args: %{directory: library.path, recursive: true, library_id: library.id}
      )

      html = render(view)
      assert html =~ "Scan started"
    end

    test "Scan Now button disabled when already scanning", %{conn: conn, admin_user: admin} do
      _library = library_fixture(%{scanning_status: "scanning"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      html = render(view)
      # Button should be disabled
      assert html =~ "disabled"
    end

    test "shows error if directory does not exist", %{conn: conn, admin_user: admin} do
      library = library_fixture(%{path: "/nonexistent/path"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='scan_now'][phx-value-id='#{library.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Directory does not exist"
    end
  end

  describe "delete library" do
    test "clicking Delete shows confirmation and deletes library", %{
      conn: conn,
      admin_user: admin
    } do
      library = library_fixture(%{name: "To Delete"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      # Initially library is present
      assert render(view) =~ "To Delete"

      # Delete the library
      view
      |> element("button[phx-click='delete_library'][phx-value-id='#{library.id}']")
      |> render_click()

      html = render(view)
      refute html =~ "To Delete"
      assert html =~ "Library deleted successfully"
    end

    test "cannot delete library while scanning", %{conn: conn, admin_user: admin} do
      library = library_fixture(%{scanning_status: "scanning"})

      conn = log_in_user(conn, admin)
      {:ok, view, _html} = live(conn, ~p"/admin/libraries")

      view
      |> element("button[phx-click='delete_library'][phx-value-id='#{library.id}']")
      |> render_click()

      html = render(view)
      assert html =~ library.name
      assert html =~ "Cannot delete library while scanning"
    end
  end
end
