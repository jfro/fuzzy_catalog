defmodule FuzzyCatalogWeb.AdminLibrariesLive do
  @moduledoc """
  LiveView for managing ebook libraries (admin only).

  Provides a full CRUD interface for managing library configurations, including:
  - Creating new libraries with directory picker
  - Editing library settings (name, path, scan mode, schedule)
  - Deleting libraries
  - Manually triggering scans
  - Viewing library status and scan history

  ## Features

  - **Directory Tree Picker**: Browse filesystem to select library path
  - **Multiple Scan Modes**: Manual, auto-watch (filesystem monitoring), or scheduled (cron)
  - **Real-time Status**: Shows current scanning status and last scan time
  - **Error Display**: Shows scan errors inline with truncated text and tooltip
  - **Scan Prevention**: Prevents concurrent scans on the same library

  ## Access Control

  Only accessible to admin users. Non-admin users are redirected to the home page.

  ## Route

      live "/admin/libraries", AdminLibrariesLive, :index
  """
  use FuzzyCatalogWeb, :live_view

  require Logger
  alias FuzzyCatalog.Accounts
  alias FuzzyCatalog.Ebooks.Libraries

  @impl true
  def mount(_params, session, socket) do
    current_scope = get_current_scope_from_session(session)

    if current_scope.user && Accounts.admin?(current_scope.user) do
      libraries = Libraries.list_libraries()

      # Schedule periodic refresh if any library is scanning
      if Enum.any?(libraries, &(&1.scanning_status == "scanning")) do
        Process.send_after(self(), :refresh_libraries, 2000)
      end

      socket =
        socket
        |> assign(:current_scope, current_scope)
        |> assign(:libraries, libraries)
        |> assign(:show_modal, false)
        |> assign(:modal_action, nil)
        |> assign(:form, nil)
        |> assign(:show_tree_picker, false)
        |> assign(:tree_current_path, nil)
        |> assign(:tree_selected_path, nil)
        |> assign(:tree_expanded_paths, MapSet.new())

      {:ok, socket, layout: {FuzzyCatalogWeb.Layouts, :live}}
    else
      socket =
        socket
        |> put_flash(:error, "Access denied. Admin privileges required.")
        |> push_navigate(to: ~p"/")

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("open_new_modal", _params, socket) do
    changeset = Libraries.change_library(%FuzzyCatalog.Ebooks.Library{})

    socket =
      socket
      |> assign(:show_modal, true)
      |> assign(:modal_action, :new)
      |> assign(:editing_library, nil)
      |> assign(:form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    library = Libraries.get_library!(id)
    changeset = Libraries.change_library(library)

    socket =
      socket
      |> assign(:show_modal, true)
      |> assign(:modal_action, :edit)
      |> assign(:editing_library, library)
      |> assign(:form, to_form(changeset))

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_modal, false)
      |> assign(:modal_action, nil)
      |> assign(:form, nil)
      |> assign(:show_tree_picker, false)
      |> assign(:tree_current_path, nil)
      |> assign(:tree_selected_path, nil)
      |> assign(:tree_expanded_paths, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_tree_picker", _params, socket) do
    # Start at root directory
    initial_path = "/"

    socket =
      socket
      |> assign(:show_tree_picker, true)
      |> assign(:tree_current_path, initial_path)
      |> assign(:tree_selected_path, nil)
      |> assign(:tree_expanded_paths, MapSet.new([initial_path]))

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_tree_picker", _params, socket) do
    socket =
      socket
      |> assign(:show_tree_picker, false)
      |> assign(:tree_current_path, nil)
      |> assign(:tree_selected_path, nil)
      |> assign(:tree_expanded_paths, MapSet.new())

    {:noreply, socket}
  end

  @impl true
  def handle_event("expand_directory", %{"path" => path}, socket) do
    expanded_paths = MapSet.put(socket.assigns.tree_expanded_paths, path)
    {:noreply, assign(socket, :tree_expanded_paths, expanded_paths)}
  end

  @impl true
  def handle_event("collapse_directory", %{"path" => path}, socket) do
    expanded_paths = MapSet.delete(socket.assigns.tree_expanded_paths, path)
    {:noreply, assign(socket, :tree_expanded_paths, expanded_paths)}
  end

  @impl true
  def handle_event("select_directory", %{"path" => path}, socket) do
    {:noreply, assign(socket, :tree_selected_path, path)}
  end

  @impl true
  def handle_event("use_selected_path", _params, socket) do
    selected_path = socket.assigns.tree_selected_path

    if selected_path do
      # Get existing form data to preserve other fields (like name)
      existing_changeset = socket.assigns.form.source

      # Extract current params, preserving what the user already typed
      current_params =
        existing_changeset.params ||
          existing_changeset.changes
          |> Enum.map(fn {k, v} -> {to_string(k), v} end)
          |> Enum.into(%{})

      # Merge selected path with existing params
      updated_params = Map.put(current_params, "path", selected_path)

      # Update changeset with merged params
      library = socket.assigns[:editing_library] || %FuzzyCatalog.Ebooks.Library{}

      changeset =
        library
        |> Libraries.change_library(updated_params)
        |> Map.put(:action, :validate)

      socket =
        socket
        |> assign(:form, to_form(changeset))
        |> assign(:show_tree_picker, false)
        |> assign(:tree_current_path, nil)
        |> assign(:tree_selected_path, nil)
        |> assign(:tree_expanded_paths, MapSet.new())

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_tree_root", %{"path" => path}, socket) do
    socket =
      socket
      |> assign(:tree_current_path, path)
      |> assign(:tree_expanded_paths, MapSet.new([path]))

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_library", %{"library" => library_params}, socket) do
    # Get existing library if editing, otherwise create new struct
    library = socket.assigns[:editing_library] || %FuzzyCatalog.Ebooks.Library{}

    changeset =
      library
      |> Libraries.change_library(library_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("scan_now", %{"id" => id}, socket) do
    library = Libraries.get_library!(id)

    cond do
      Libraries.scanning?(library) ->
        socket =
          socket
          |> put_flash(:error, "Library is already scanning")

        {:noreply, socket}

      !File.dir?(library.path) ->
        socket =
          socket
          |> put_flash(:error, "Directory does not exist")

        {:noreply, socket}

      true ->
        # Mark as scanning
        {:ok, library} = Libraries.mark_scanning(library)

        # Enqueue ScanWorker job
        %{directory: library.path, recursive: true, library_id: library.id}
        |> FuzzyCatalog.Ebooks.Workers.ScanWorker.new()
        |> Oban.insert()

        # Reload libraries to show updated status
        libraries = Libraries.list_libraries()

        # Schedule periodic refresh to update progress
        Process.send_after(self(), :refresh_libraries, 2000)

        socket =
          socket
          |> assign(:libraries, libraries)
          |> put_flash(:info, "Scan started")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_library", %{"id" => id}, socket) do
    library = Libraries.get_library!(id)

    if Libraries.scanning?(library) do
      socket =
        socket
        |> put_flash(:error, "Cannot delete library while scanning")

      {:noreply, socket}
    else
      case Libraries.delete_library(library) do
        {:ok, _library} ->
          libraries = Libraries.list_libraries()

          socket =
            socket
            |> assign(:libraries, libraries)
            |> put_flash(:info, "Library deleted successfully")

          {:noreply, socket}

        {:error, _changeset} ->
          socket =
            socket
            |> put_flash(:error, "Failed to delete library")

          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("save_library", %{"library" => library_params}, socket) do
    result =
      case socket.assigns.modal_action do
        :new ->
          Libraries.create_library(library_params)

        :edit ->
          library = socket.assigns.editing_library
          Libraries.update_library(library, library_params)
      end

    case result do
      {:ok, _library} ->
        libraries = Libraries.list_libraries()

        message =
          if socket.assigns.modal_action == :new,
            do: "Library created successfully",
            else: "Library updated successfully"

        socket =
          socket
          |> assign(:libraries, libraries)
          |> assign(:show_modal, false)
          |> assign(:modal_action, nil)
          |> assign(:editing_library, nil)
          |> assign(:form, nil)
          |> put_flash(:info, message)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def handle_info(:refresh_libraries, socket) do
    libraries = Libraries.list_libraries()

    # Schedule next refresh if any library is still scanning
    if Enum.any?(libraries, &(&1.scanning_status == "scanning")) do
      Process.send_after(self(), :refresh_libraries, 2000)
    end

    {:noreply, assign(socket, :libraries, libraries)}
  end

  defp scan_mode_badge_class("manual"), do: "badge-ghost"
  defp scan_mode_badge_class("auto_watch"), do: "badge-info"
  defp scan_mode_badge_class("scheduled"), do: "badge-success"
  defp scan_mode_badge_class(_), do: "badge-ghost"

  defp status_badge_class("idle"), do: "badge-ghost"
  defp status_badge_class("scanning"), do: "badge-warning"
  defp status_badge_class("failed"), do: "badge-error"
  defp status_badge_class(_), do: "badge-ghost"

  defp get_current_scope_from_session(session) do
    case session["user_token"] do
      nil ->
        Accounts.Scope.for_user(nil)

      user_token ->
        case Accounts.get_user_by_session_token(user_token) do
          {user, _inserted_at} -> Accounts.Scope.for_user(user)
          nil -> Accounts.Scope.for_user(nil)
        end
    end
  end
end
