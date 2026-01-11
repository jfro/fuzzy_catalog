defmodule FuzzyCatalog.Ebooks.Libraries do
  @moduledoc """
  The Libraries context for managing ebook library directories.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Ebooks.Library

  @doc """
  Returns the list of libraries.

  ## Examples

      iex> list_libraries()
      [%Library{}, ...]

  """
  def list_libraries do
    Repo.all(Library)
  end

  @doc """
  Gets a single library.

  Raises `Ecto.NoResultsError` if the Library does not exist.

  ## Examples

      iex> get_library!(123)
      %Library{}

      iex> get_library!(456)
      ** (Ecto.NoResultsError)

  """
  def get_library!(id), do: Repo.get!(Library, id)

  @doc """
  Creates a library.

  ## Examples

      iex> create_library(%{name: "My Library", path: "/home/books"})
      {:ok, %Library{}}

      iex> create_library(%{name: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_library(attrs \\ %{}) do
    %Library{}
    |> Library.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, library} = result ->
        notify_watcher_library_changed(:created, library)
        notify_scheduler_library_changed(:created, library)
        result

      error ->
        error
    end
  end

  @doc """
  Updates a library.

  ## Examples

      iex> update_library(library, %{name: "New Name"})
      {:ok, %Library{}}

      iex> update_library(library, %{name: nil})
      {:error, %Ecto.Changeset{}}

  """
  def update_library(%Library{} = library, attrs) do
    library
    |> Library.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_library} = result ->
        # Notify watchers of change (scan_mode or path may have changed)
        notify_watcher_library_changed(:updated, updated_library)
        # Notify scheduler of change (scan_mode or schedule may have changed)
        notify_scheduler_library_changed(:updated, updated_library)
        result

      error ->
        error
    end
  end

  @doc """
  Deletes a library.

  ## Examples

      iex> delete_library(library)
      {:ok, %Library{}}

      iex> delete_library(library)
      {:error, %Ecto.Changeset{}}

  """
  def delete_library(%Library{} = library) do
    result = Repo.delete(library)

    case result do
      {:ok, deleted_library} ->
        notify_watcher_library_changed(:deleted, deleted_library)
        notify_scheduler_library_changed(:deleted, deleted_library)
        result

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking library changes.

  ## Examples

      iex> change_library(library)
      %Ecto.Changeset{data: %Library{}}

  """
  def change_library(%Library{} = library, attrs \\ %{}) do
    Library.changeset(library, attrs)
  end

  @doc """
  Returns libraries filtered by scan_mode.

  ## Examples

      iex> list_libraries_by_scan_mode("auto_watch")
      [%Library{scan_mode: "auto_watch"}, ...]

  """
  def list_libraries_by_scan_mode(scan_mode) do
    Library
    |> where([l], l.scan_mode == ^scan_mode)
    |> Repo.all()
  end

  @doc """
  Returns all libraries with scan_mode="auto_watch".

  ## Examples

      iex> list_auto_watch_libraries()
      [%Library{scan_mode: "auto_watch"}, ...]

  """
  def list_auto_watch_libraries do
    list_libraries_by_scan_mode("auto_watch")
  end

  @doc """
  Returns all libraries with scan_mode="scheduled".

  ## Examples

      iex> list_scheduled_libraries()
      [%Library{scan_mode: "scheduled"}, ...]

  """
  def list_scheduled_libraries do
    list_libraries_by_scan_mode("scheduled")
  end

  @doc """
  Marks a library as currently scanning.

  ## Examples

      iex> mark_scanning(library)
      {:ok, %Library{scanning_status: "scanning"}}

  """
  def mark_scanning(%Library{} = library) do
    library
    |> Library.changeset(%{scanning_status: "scanning"})
    |> Repo.update()
  end

  @doc """
  Marks a library scan as complete.

  Updates scanning_status to "idle" and sets last_scanned_at to now.

  ## Examples

      iex> mark_scan_complete(library)
      {:ok, %Library{scanning_status: "idle"}}

  """
  def mark_scan_complete(%Library{} = library) do
    library
    |> Library.changeset(%{
      scanning_status: "idle",
      last_scanned_at: DateTime.utc_now(),
      last_scan_error: nil
    })
    |> Repo.update()
  end

  @doc """
  Marks a library scan as failed.

  Updates scanning_status to "failed" and stores the error message.

  ## Examples

      iex> mark_scan_failed(library, "File not found")
      {:ok, %Library{scanning_status: "failed"}}

  """
  def mark_scan_failed(%Library{} = library, error) do
    library
    |> Library.changeset(%{
      scanning_status: "failed",
      last_scan_error: to_string(error),
      last_scanned_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Returns true if the library is currently being scanned.

  ## Examples

      iex> scanning?(library)
      true

  """
  def scanning?(%Library{scanning_status: "scanning"}), do: true
  def scanning?(%Library{}), do: false

  @doc """
  Updates scan progress for a library.

  ## Examples

      iex> update_scan_progress(library, "scanning", 10, 100)
      {:ok, %Library{}}

  """
  def update_scan_progress(%Library{} = library, stage, current, total) do
    library
    |> Library.changeset(%{
      scan_progress_stage: stage,
      scan_progress_current: current,
      scan_progress_total: total
    })
    |> Repo.update()
  end

  @doc """
  Clears scan progress for a library.

  ## Examples

      iex> clear_scan_progress(library)
      {:ok, %Library{}}

  """
  def clear_scan_progress(%Library{} = library) do
    library
    |> Library.changeset(%{
      scan_progress_stage: nil,
      scan_progress_current: nil,
      scan_progress_total: nil
    })
    |> Repo.update()
  end

  @doc """
  Resets a stuck library from "scanning" to "idle" status.

  This is useful for recovering from situations where a scan job crashed
  or was killed without properly updating the library status.

  ## Examples

      iex> reset_stuck_scanning(library)
      {:ok, %Library{scanning_status: "idle"}}

  """
  def reset_stuck_scanning(%Library{} = library) do
    library
    |> Library.changeset(%{
      scanning_status: "idle",
      last_scan_error: "Scan was interrupted and reset manually"
    })
    |> Repo.update()
  end

  @doc """
  Finds and resets all libraries stuck in "scanning" status.

  Returns a list of reset libraries.

  ## Examples

      iex> reset_all_stuck_scanning()
      [%Library{}, ...]

  """
  def reset_all_stuck_scanning do
    from(l in Library, where: l.scanning_status == "scanning")
    |> Repo.all()
    |> Enum.map(fn library ->
      case reset_stuck_scanning(library) do
        {:ok, updated} -> updated
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Notifies watchers/schedulers when a library is created, updated, or deleted.

  ## Examples

      iex> notify_watcher_library_changed(:created, library)
      :ok

  """
  def notify_watcher_library_changed(event, library) do
    case event do
      :created ->
        FuzzyCatalog.Ebooks.LibraryWatcher.library_changed(library)

      :updated ->
        FuzzyCatalog.Ebooks.LibraryWatcher.library_changed(library)

      :deleted ->
        FuzzyCatalog.Ebooks.LibraryWatcher.library_deleted(library.id)
    end

    :ok
  end

  @doc """
  Notifies the scheduler when a library is created, updated, or deleted.
  This allows the scheduler to reload its schedule.
  """
  def notify_scheduler_library_changed(event, library) do
    case event do
      :created ->
        FuzzyCatalog.Ebooks.LibraryScheduler.library_changed(library)

      :updated ->
        FuzzyCatalog.Ebooks.LibraryScheduler.library_changed(library)

      :deleted ->
        FuzzyCatalog.Ebooks.LibraryScheduler.library_deleted(library.id)
    end

    :ok
  end
end
