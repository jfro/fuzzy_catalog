defmodule FuzzyCatalog.ProviderScheduler do
  @moduledoc """
  GenServer that handles periodic provider synchronization based on admin settings.

  The scheduler can be configured with different intervals like "1h", "30m", "15m" or "disabled".
  When the interval is changed, the scheduler immediately updates its timer without requiring a restart.
  """

  use GenServer
  require Logger
  alias FuzzyCatalog.{AdminSettings, Catalog.ExternalLibrarySync, SyncStatusManager}

  @name __MODULE__

  # Client API

  @doc """
  Starts the provider scheduler.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @doc """
  Updates the refresh interval and immediately reschedules the next sync.
  """
  def update_interval(interval) when is_binary(interval) do
    GenServer.call(@name, {:update_interval, interval})
  end

  @doc """
  Gets the current interval setting.
  """
  def get_interval do
    GenServer.call(@name, :get_interval)
  end

  # Server Callbacks

  @impl true
  def init(_state) do
    # Get initial interval from settings
    interval = AdminSettings.get_provider_refresh_interval()
    Logger.info("ProviderScheduler started with interval: #{interval}")

    state = %{
      interval: interval,
      timer_ref: nil
    }

    # Schedule first sync if enabled
    new_state = schedule_next_sync(state)

    {:ok, new_state}
  end

  @impl true
  def handle_call({:update_interval, interval}, _from, state) do
    Logger.info("ProviderScheduler interval updated to: #{interval}")

    # Cancel existing timer if any
    new_state = cancel_timer(state)

    # Update interval and schedule next sync
    updated_state = %{new_state | interval: interval}
    final_state = schedule_next_sync(updated_state)

    {:reply, :ok, final_state}
  end

  @impl true
  def handle_call(:get_interval, _from, state) do
    {:reply, state.interval, state}
  end

  @impl true
  def handle_info(:sync_providers, state) do
    Logger.info("ProviderScheduler: Triggering periodic provider sync")

    # Only sync if no providers are currently syncing
    if SyncStatusManager.any_syncing?() do
      Logger.info("ProviderScheduler: Skipping sync - providers already syncing")
    else
      # Start sync in background task to avoid blocking the scheduler
      Task.start(fn ->
        try do
          {:ok, summary} = ExternalLibrarySync.sync_all_providers()

          Logger.info(
            "ProviderScheduler: Periodic sync completed - #{summary.new_books} new books added"
          )
        rescue
          error ->
            Logger.error("ProviderScheduler: Periodic sync error - #{inspect(error)}")
        end
      end)
    end

    # Schedule next sync
    new_state = schedule_next_sync(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:timeout, timer_ref, :sync_providers}, %{timer_ref: timer_ref} = state) do
    # This handles the case where we use :timer.send_after/3
    handle_info(:sync_providers, state)
  end

  @impl true
  def handle_info({:timeout, _old_timer_ref, :sync_providers}, state) do
    # Ignore timeouts from old timers that were cancelled
    {:noreply, state}
  end

  # Private functions

  defp schedule_next_sync(%{interval: "disabled"} = state) do
    Logger.debug("ProviderScheduler: Sync disabled, not scheduling")
    %{state | timer_ref: nil}
  end

  defp schedule_next_sync(%{interval: interval} = state) do
    case parse_interval(interval) do
      {:ok, milliseconds} ->
        Logger.debug("ProviderScheduler: Scheduling next sync in #{interval} (#{milliseconds}ms)")
        timer_ref = :timer.send_after(milliseconds, self(), :sync_providers)
        %{state | timer_ref: timer_ref}

      {:error, reason} ->
        Logger.error("ProviderScheduler: Invalid interval '#{interval}': #{reason}")
        %{state | timer_ref: nil}
    end
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: timer_ref} = state) do
    :timer.cancel(timer_ref)
    %{state | timer_ref: nil}
  end

  defp parse_interval("disabled"), do: {:error, "disabled"}
  defp parse_interval(""), do: {:error, "empty interval"}
  defp parse_interval(nil), do: {:error, "nil interval"}

  defp parse_interval(interval) when is_binary(interval) do
    case Regex.run(~r/^(\d+)([mh])$/, String.downcase(interval)) do
      [_, number_str, unit] ->
        case Integer.parse(number_str) do
          {number, ""} when number > 0 ->
            milliseconds =
              case unit do
                # minutes to milliseconds
                "m" -> number * 60 * 1000
                # hours to milliseconds
                "h" -> number * 60 * 60 * 1000
              end

            {:ok, milliseconds}

          _ ->
            {:error, "invalid number: #{number_str}"}
        end

      nil ->
        {:error, "invalid format - expected format like '1h', '30m', '15m'"}
    end
  end

  @doc """
  Validates if an interval string is valid.
  Returns {:ok, interval} if valid, {:error, reason} if invalid.
  """
  def validate_interval("disabled"), do: {:ok, "disabled"}
  def validate_interval(""), do: {:error, "Interval cannot be empty"}
  def validate_interval(nil), do: {:error, "Interval cannot be nil"}

  def validate_interval(interval) when is_binary(interval) do
    case parse_interval(interval) do
      {:ok, _milliseconds} -> {:ok, interval}
      {:error, reason} -> {:error, reason}
    end
  end

  def validate_interval(_), do: {:error, "Interval must be a string"}
end
