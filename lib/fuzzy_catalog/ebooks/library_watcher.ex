defmodule FuzzyCatalog.Ebooks.LibraryWatcher do
  @moduledoc """
  GenServer that manages filesystem watchers for libraries with auto_watch mode.

  Responsibilities:
  - Start/stop watchers for auto_watch libraries
  - Debounce file change events (5 second quiet period)
  - Filter events for ebook formats only
  - Trigger ScanWorker jobs when changes detected
  - Respect library scanning status (don't trigger if already scanning)
  """

  use GenServer
  require Logger

  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Workers.ScanWorker

  @ebook_extensions [".epub", ".pdf"]

  defstruct watchers: %{}, debounce_timers: %{}

  ## Client API

  @doc """
  Starts the LibraryWatcher GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Notifies the watcher that a library has been created or updated.
  """
  def library_changed(pid \\ __MODULE__, library) do
    GenServer.cast(pid, {:library_changed, library})
  end

  @doc """
  Notifies the watcher that a library has been deleted.
  """
  def library_deleted(pid \\ __MODULE__, library_id) do
    GenServer.cast(pid, {:library_deleted, library_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("LibraryWatcher starting")

    # Start watchers for existing auto_watch libraries
    libraries = Libraries.list_auto_watch_libraries()
    state = %__MODULE__{}

    state =
      Enum.reduce(libraries, state, fn library, acc ->
        start_watcher(library, acc)
      end)

    {:ok, state}
  end

  @impl true
  def handle_cast({:library_changed, library}, state) do
    state =
      case {library.scan_mode, Map.has_key?(state.watchers, library.id)} do
        {"auto_watch", false} ->
          # New auto_watch library, start watcher
          start_watcher(library, state)

        {"auto_watch", true} ->
          # Update existing watcher (path might have changed)
          new_state = stop_watcher(state, library.id)
          start_watcher(library, new_state)

        {_, true} ->
          # No longer auto_watch, stop watcher
          stop_watcher(state, library.id)

        {_, false} ->
          # Not auto_watch and no watcher, nothing to do
          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:library_deleted, library_id}, state) do
    state = stop_watcher(state, library_id)
    {:noreply, state}
  end

  @impl true
  def handle_info({:file_event, watcher_pid, {path, events}}, state) do
    # Find which library this watcher belongs to
    library_id =
      Enum.find_value(state.watchers, fn {lib_id, pid} ->
        if pid == watcher_pid, do: lib_id
      end)

    if library_id do
      # Check if this is an ebook file
      if is_ebook_file?(path) and relevant_event?(events) do
        Logger.debug("File event detected for library #{library_id}: #{path}")

        # Cancel existing debounce timer if any
        state = cancel_debounce_timer(state, library_id)

        # Start new debounce timer
        debounce_ms = get_debounce_ms()
        timer_ref = Process.send_after(self(), {:trigger_scan, library_id}, debounce_ms)

        state = put_in(state.debounce_timers[library_id], timer_ref)
        {:noreply, state}
      else
        {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, watcher_pid, :stop}, state) do
    Logger.warning("FileSystem watcher stopped unexpectedly: #{inspect(watcher_pid)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:trigger_scan, library_id}, state) do
    # Remove debounce timer
    state = update_in(state.debounce_timers, &Map.delete(&1, library_id))

    # Trigger scan if library is not already scanning
    try do
      library = Libraries.get_library!(library_id)

      if Libraries.scanning?(library) do
        Logger.debug("Library #{library_id} already scanning, skipping scan trigger")
        {:noreply, state}
      else
        Logger.info("Triggering auto-scan for library #{library_id}: #{library.path}")

        # Mark as scanning
        {:ok, _library} = Libraries.mark_scanning(library)

        # Enqueue scan job
        %{directory: library.path, recursive: true, library_id: library.id}
        |> ScanWorker.new()
        |> Oban.insert()

        {:noreply, state}
      end
    rescue
      Ecto.NoResultsError ->
        Logger.warning("Library #{library_id} not found, cannot trigger scan")
        {:noreply, state}
    end
  end

  ## Private Functions

  defp start_watcher(library, state) do
    if File.dir?(library.path) do
      case FileSystem.start_link(dirs: [library.path], name: :"watcher_#{library.id}") do
        {:ok, pid} ->
          FileSystem.subscribe(pid)
          Logger.info("Started FileSystem watcher for library #{library.id}: #{library.path}")
          put_in(state.watchers[library.id], pid)

        {:error, reason} ->
          Logger.error("Failed to start watcher for library #{library.id}: #{inspect(reason)}")
          state
      end
    else
      Logger.warning(
        "Cannot start watcher for library #{library.id}: directory does not exist: #{library.path}"
      )

      state
    end
  end

  defp stop_watcher(state, library_id) do
    case Map.pop(state.watchers, library_id) do
      {nil, watchers} ->
        %{state | watchers: watchers}

      {pid, watchers} ->
        # Stop the FileSystem GenServer
        if Process.alive?(pid) do
          GenServer.stop(pid, :normal)
        end

        Logger.info("Stopped FileSystem watcher for library #{library_id}")

        # Also cancel any pending debounce timer
        state = %{state | watchers: watchers}
        cancel_debounce_timer(state, library_id)
    end
  end

  defp cancel_debounce_timer(state, library_id) do
    case Map.pop(state.debounce_timers, library_id) do
      {nil, timers} ->
        %{state | debounce_timers: timers}

      {timer_ref, timers} ->
        Process.cancel_timer(timer_ref)
        %{state | debounce_timers: timers}
    end
  end

  defp is_ebook_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @ebook_extensions
  end

  defp relevant_event?(events) do
    # FileSystem events: [:created, :modified, :removed, :renamed, :closed]
    # We care about created, modified, and renamed
    Enum.any?(events, fn event ->
      event in [:created, :modified, :renamed, :closed]
    end)
  end

  defp get_debounce_ms do
    Application.get_env(:fuzzy_catalog, :ebooks, [])
    |> Keyword.get(:watcher_debounce_ms, 5000)
  end
end
