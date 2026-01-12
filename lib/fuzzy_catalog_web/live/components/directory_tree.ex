defmodule FuzzyCatalogWeb.DirectoryTree do
  @moduledoc """
  Interactive directory tree picker component for selecting filesystem paths.

  Provides a lazy-loading, expandable tree view for browsing directories. Only shows
  directories (files are filtered out) and loads children on-demand when a directory
  is expanded.

  ## Security

  - Path traversal protection: Rejects paths containing ".."
  - Existence validation: Only shows directories that actually exist
  - Permission checking: Handles permission errors gracefully

  ## Usage

      <DirectoryTree.tree
        id="my-tree"
        current_path="/home/user"
        selected_path={@selected_path}
        expanded_paths={@expanded_paths}
      />

  ## Events

  The component emits the following events that can be handled in the parent LiveView:

  - `expand_directory` - User clicked to expand a directory
  - `collapse_directory` - User clicked to collapse a directory
  - `select_directory` - User selected a directory
  """
  use Phoenix.Component

  @doc """
  Renders a directory tree picker component.

  ## Attributes
    * `id` - Component ID (required)
    * `selected_path` - Currently selected directory path
    * `current_path` - Root path to start browsing from
    * `expanded_paths` - MapSet of expanded directory paths
  """
  attr :id, :string, required: true
  attr :selected_path, :string, default: nil
  attr :current_path, :string, required: true
  attr :expanded_paths, :any, default: %MapSet{}

  def tree(assigns) do
    ~H"""
    <div id={@id} class="directory-tree border rounded p-4 max-h-96 overflow-y-auto">
      <%= if @current_path do %>
        <.directory_node
          path={@current_path}
          selected_path={@selected_path}
          expanded_paths={@expanded_paths}
          depth={0}
        />
      <% end %>
    </div>
    """
  end

  attr :path, :string, required: true
  attr :selected_path, :string, default: nil
  attr :expanded_paths, :any, required: true
  attr :depth, :integer, required: true

  defp directory_node(assigns) do
    assigns = assign(assigns, :name, Path.basename(assigns.path))
    assigns = assign(assigns, :is_expanded, MapSet.member?(assigns.expanded_paths, assigns.path))
    assigns = assign(assigns, :is_selected, assigns.path == assigns.selected_path)

    # Get subdirectories if expanded
    assigns =
      if assigns.is_expanded do
        case list_subdirectories(assigns.path) do
          {:ok, subdirs} -> assign(assigns, :subdirs, subdirs)
          {:error, _} -> assign(assigns, :subdirs, [])
        end
      else
        assign(assigns, :subdirs, [])
      end

    ~H"""
    <div class="directory-node" style={"margin-left: #{@depth * 20}px"}>
      <div class="flex items-center gap-2 py-1 hover:bg-base-200 rounded cursor-pointer">
        <%= if @is_expanded do %>
          <button
            type="button"
            phx-click="collapse_directory"
            phx-value-path={@path}
            class="btn btn-ghost btn-xs"
          >
            ▼
          </button>
        <% else %>
          <button
            type="button"
            phx-click="expand_directory"
            phx-value-path={@path}
            class="btn btn-ghost btn-xs"
          >
            ▶
          </button>
        <% end %>

        <button
          type="button"
          phx-click="select_directory"
          phx-value-path={@path}
          class={"flex-1 text-left " <> if(@is_selected, do: "font-bold text-primary", else: "")}
        >
          📁 {@name}
        </button>
      </div>

      <%= if @is_expanded do %>
        <%= for subdir <- @subdirs do %>
          <.directory_node
            path={subdir}
            selected_path={@selected_path}
            expanded_paths={@expanded_paths}
            depth={@depth + 1}
          />
        <% end %>
      <% end %>
    </div>
    """
  end

  @doc """
  Validates a directory path for security and existence.

  Returns `{:ok, path}` if valid, `{:error, reason}` otherwise.
  """
  def validate_path(path) do
    cond do
      String.contains?(path, "..") ->
        {:error, "Invalid path: path traversal detected"}

      !File.dir?(path) ->
        {:error, "Directory does not exist"}

      true ->
        case File.ls(path) do
          {:ok, _} -> {:ok, path}
          {:error, :eacces} -> {:error, "Permission denied"}
          {:error, _} -> {:error, "Cannot read directory"}
        end
    end
  end

  @doc """
  Lists subdirectories in a given path.

  Returns `{:ok, [paths]}` on success, `{:error, reason}` on failure.
  """
  def list_subdirectories(path) do
    case File.ls(path) do
      {:ok, entries} ->
        subdirs =
          entries
          |> Enum.map(&Path.join(path, &1))
          |> Enum.filter(&File.dir?/1)
          |> Enum.sort()

        {:ok, subdirs}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
