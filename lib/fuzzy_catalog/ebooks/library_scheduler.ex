defmodule FuzzyCatalog.Ebooks.LibraryScheduler do
  @moduledoc """
  GenServer that manages scheduled scans for libraries with scheduled mode.

  Responsibilities:
  - Load libraries with scan_mode = "scheduled" on startup
  - Use Oban Cron for scheduling actual scans
  - Dynamically update Oban cron configuration when libraries change
  - Validate cron expressions
  - Trigger ScanWorker jobs on schedule
  """

  use GenServer
  require Logger

  alias FuzzyCatalog.Ebooks.Libraries
  alias FuzzyCatalog.Ebooks.Workers.ScanWorker

  defstruct libraries: []

  ## Client API

  @doc """
  Starts the LibraryScheduler GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Notifies the scheduler that a library has been created or updated.
  """
  def library_changed(pid \\ __MODULE__, _library) do
    GenServer.cast(pid, :reload_schedule)
  end

  @doc """
  Notifies the scheduler that a library has been deleted.
  """
  def library_deleted(pid \\ __MODULE__, _library_id) do
    GenServer.cast(pid, :reload_schedule)
  end

  @doc """
  Performs a scheduled scan for a library.
  Called by Oban cron jobs.
  """
  def perform_scheduled_scan(library_id) do
    try do
      library = Libraries.get_library!(library_id)

      if Libraries.scanning?(library) do
        Logger.debug("Library #{library_id} already scanning, skipping scheduled scan")
        :ok
      else
        Logger.info("Triggering scheduled scan for library #{library_id}: #{library.path}")

        # Mark as scanning
        {:ok, _library} = Libraries.mark_scanning(library)

        # Enqueue scan job
        %{directory: library.path, recursive: true, library_id: library.id}
        |> ScanWorker.new()
        |> Oban.insert()

        :ok
      end
    rescue
      Ecto.NoResultsError ->
        Logger.warning("Library #{library_id} not found for scheduled scan")
        :ok
    end
  end

  @doc """
  Validates a cron expression.
  """
  def valid_cron?(cron) when is_binary(cron) do
    # Basic cron validation - check format
    # Cron format: minute hour day-of-month month day-of-week
    # Each field can be: number, *, */n, n-m, or comma-separated list
    parts = String.split(cron, " ")

    if length(parts) == 5 do
      Enum.all?(parts, &valid_cron_field?/1)
    else
      false
    end
  end

  def valid_cron?(_), do: false

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("LibraryScheduler starting")

    # Load scheduled libraries
    libraries = Libraries.list_scheduled_libraries()
    Logger.info("Found #{length(libraries)} scheduled libraries")

    # Update Oban cron configuration
    update_oban_cron(libraries)

    {:ok, %__MODULE__{libraries: libraries}}
  end

  @impl true
  def handle_cast(:reload_schedule, state) do
    Logger.info("Reloading library schedule")

    # Reload scheduled libraries
    libraries = Libraries.list_scheduled_libraries()
    Logger.info("Found #{length(libraries)} scheduled libraries after reload")

    # Update Oban cron configuration
    update_oban_cron(libraries)

    {:noreply, %{state | libraries: libraries}}
  end

  ## Private Functions

  defp update_oban_cron(libraries) do
    # Build crontab from scheduled libraries
    crontab =
      Enum.map(libraries, fn library ->
        {library.schedule, {__MODULE__, :perform_scheduled_scan, [library.id]}}
      end)

    # Get current Oban config
    oban_config = Application.get_env(:fuzzy_catalog, Oban, [])

    # Update plugins with new crontab
    plugins =
      case Keyword.get(oban_config, :plugins) do
        # Plugins disabled (test mode)
        false ->
          false

        # No plugins configured, add cron plugin
        nil ->
          [{Oban.Plugins.Cron, crontab: crontab}]

        # Empty list, add cron plugin
        [] ->
          [{Oban.Plugins.Cron, crontab: crontab}]

        # Plugins configured, update or add cron plugin
        plugins when is_list(plugins) ->
          update_cron_plugin(plugins, crontab)
      end

    # Only update config if plugins are enabled
    if plugins != false do
      # Update application config
      new_oban_config = Keyword.put(oban_config, :plugins, plugins)
      Application.put_env(:fuzzy_catalog, Oban, new_oban_config)

      # If Oban is already started, we need to update the running configuration
      # This is done by the Oban.Plugins.Cron plugin which watches config changes
      Logger.debug("Updated Oban cron configuration with #{length(crontab)} scheduled libraries")
    else
      Logger.debug("Oban plugins disabled, skipping cron configuration update")
    end
  end

  defp update_cron_plugin(plugins, crontab) do
    cron_index =
      Enum.find_index(plugins, fn
        {Oban.Plugins.Cron, _opts} -> true
        _ -> false
      end)

    if cron_index do
      # Update existing cron plugin
      List.replace_at(plugins, cron_index, {Oban.Plugins.Cron, crontab: crontab})
    else
      # Add cron plugin
      plugins ++ [{Oban.Plugins.Cron, crontab: crontab}]
    end
  end

  defp valid_cron_field?(field) do
    cond do
      # Wildcard
      field == "*" ->
        true

      # Step values (*/5)
      String.match?(field, ~r/^\*\/\d+$/) ->
        true

      # Range (1-5)
      String.match?(field, ~r/^\d+-\d+$/) ->
        true

      # List (1,2,3)
      String.match?(field, ~r/^(\d+,)+\d+$/) ->
        true

      # Single number
      String.match?(field, ~r/^\d+$/) ->
        true

      true ->
        false
    end
  end
end
