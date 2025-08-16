defmodule FuzzyCatalog.SyncStatusManager do
  @moduledoc """
  GenServer for managing and tracking external library sync status.

  Provides real-time status updates for sync operations via Phoenix.PubSub.
  Tracks which providers are currently syncing and maintains sync statistics.
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub

  @pubsub_topic "sync_status"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current sync status for all providers.
  """
  def get_all_status do
    GenServer.call(__MODULE__, :get_all_status)
  end

  @doc """
  Get sync status for a specific provider.
  """
  def get_provider_status(provider_name) do
    GenServer.call(__MODULE__, {:get_provider_status, provider_name})
  end

  @doc """
  Mark a provider as starting sync.
  """
  def start_sync(provider_name, total_books \\ nil) do
    GenServer.call(__MODULE__, {:start_sync, provider_name, total_books})
  end

  @doc """
  Update sync progress for a provider.
  """
  def update_progress(provider_name, progress) do
    GenServer.cast(__MODULE__, {:update_progress, provider_name, progress})
  end

  @doc """
  Mark a provider sync as completed with results.
  """
  def complete_sync(provider_name, results) do
    GenServer.cast(__MODULE__, {:complete_sync, provider_name, results})
  end

  @doc """
  Mark a provider sync as failed with error.
  """
  def fail_sync(provider_name, error) do
    GenServer.cast(__MODULE__, {:fail_sync, provider_name, error})
  end

  @doc """
  Check if any provider is currently syncing.
  """
  def any_syncing? do
    GenServer.call(__MODULE__, :any_syncing?)
  end

  @doc """
  Check if a specific provider is currently syncing.
  """
  def syncing?(provider_name) do
    GenServer.call(__MODULE__, {:syncing?, provider_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      providers: %{},
      sync_history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_all_status, _from, state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_call({:get_provider_status, provider_name}, _from, state) do
    status = Map.get(state.providers, provider_name, %{status: :idle})
    {:reply, status, state}
  end

  @impl true
  def handle_call({:start_sync, provider_name, total_books}, _from, state) do
    case Map.get(state.providers, provider_name, %{}) do
      %{status: :syncing} ->
        {:reply, {:error, :already_syncing}, state}

      _ ->
        new_status = %{
          status: :syncing,
          started_at: DateTime.utc_now(),
          progress: %{total_books: total_books || 0, processed_books: 0, new_books: 0, errors: []}
        }

        new_providers = Map.put(state.providers, provider_name, new_status)
        new_state = %{state | providers: new_providers}

        broadcast_status_update(provider_name, new_status)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:any_syncing?, _from, state) do
    syncing =
      state.providers
      |> Enum.any?(fn {_name, status} -> status.status == :syncing end)

    {:reply, syncing, state}
  end

  @impl true
  def handle_call({:syncing?, provider_name}, _from, state) do
    syncing =
      case Map.get(state.providers, provider_name) do
        %{status: :syncing} -> true
        _ -> false
      end

    {:reply, syncing, state}
  end

  @impl true
  def handle_cast({:update_progress, provider_name, progress}, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        Logger.warning("Received progress update for unknown provider: #{provider_name}")
        {:noreply, state}

      provider_status ->
        updated_progress = Map.merge(provider_status.progress, progress)
        updated_status = %{provider_status | progress: updated_progress}
        new_providers = Map.put(state.providers, provider_name, updated_status)
        new_state = %{state | providers: new_providers}

        broadcast_status_update(provider_name, updated_status)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:complete_sync, provider_name, results}, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        Logger.warning("Received completion for unknown provider: #{provider_name}")
        {:noreply, state}

      provider_status ->
        completed_at = DateTime.utc_now()

        completed_status =
          Map.merge(provider_status, %{
            status: :idle,
            completed_at: completed_at,
            last_results: results
          })

        new_providers = Map.put(state.providers, provider_name, completed_status)

        # Add to history
        history_entry = %{
          provider: provider_name,
          started_at: provider_status.started_at,
          completed_at: completed_status.completed_at,
          results: results,
          success: true
        }

        new_history = [history_entry | Enum.take(state.sync_history, 49)]
        new_state = %{state | providers: new_providers, sync_history: new_history}

        broadcast_status_update(provider_name, completed_status)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:fail_sync, provider_name, error}, state) do
    case Map.get(state.providers, provider_name) do
      nil ->
        Logger.warning("Received failure for unknown provider: #{provider_name}")
        {:noreply, state}

      provider_status ->
        failed_status = %{
          provider_status
          | status: :error,
            completed_at: DateTime.utc_now(),
            error: error
        }

        new_providers = Map.put(state.providers, provider_name, failed_status)

        # Add to history
        history_entry = %{
          provider: provider_name,
          started_at: provider_status.started_at,
          completed_at: failed_status.completed_at,
          error: error,
          success: false
        }

        new_history = [history_entry | Enum.take(state.sync_history, 49)]
        new_state = %{state | providers: new_providers, sync_history: new_history}

        broadcast_status_update(provider_name, failed_status)
        {:noreply, new_state}
    end
  end

  # Private Functions

  defp broadcast_status_update(provider_name, status) do
    PubSub.broadcast(
      FuzzyCatalog.PubSub,
      @pubsub_topic,
      {:sync_status_update, provider_name, status}
    )
  end
end
