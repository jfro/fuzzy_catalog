defmodule FuzzyCatalogWeb.AdminLive do
  use FuzzyCatalogWeb, :live_view

  require Logger
  alias FuzzyCatalog.Catalog.ExternalLibrarySync
  alias FuzzyCatalog.SyncStatusManager
  alias FuzzyCatalog.Accounts

  @providers [
    %{
      module: FuzzyCatalog.Catalog.Providers.AudiobookshelfProvider,
      name: "Audiobookshelf",
      description: "Sync audiobooks from Audiobookshelf server"
    },
    %{
      module: FuzzyCatalog.Catalog.Providers.CalibreProvider,
      name: "Calibre",
      description: "Sync books from Calibre library"
    },
    %{
      module: FuzzyCatalog.Catalog.Providers.BookLoreProvider,
      name: "BookLore",
      description: "Sync books from BookLore library"
    }
  ]

  @impl true
  def mount(_params, session, socket) do
    Logger.info("AdminLive mount called - connected: #{connected?(socket)}")

    # Get current scope from session like the auth plug does
    current_scope = get_current_scope_from_session(session)
    Logger.info("AdminLive current_scope: #{inspect(current_scope)}")

    # Verify user is admin
    if current_scope.user && Accounts.admin?(current_scope.user) &&
         Accounts.active?(current_scope.user) do
      if connected?(socket) do
        Logger.info("AdminLive subscribing to PubSub")
        Phoenix.PubSub.subscribe(FuzzyCatalog.PubSub, "sync_status")
      end

      socket =
        socket
        |> assign(:current_scope, current_scope)
        |> assign(:providers, get_providers_with_status())
        |> assign(:page_title, "Admin - External Library Sync")
        |> assign(:syncing_all, false)

      Logger.info("AdminLive mount completed successfully")
      {:ok, socket, layout: {FuzzyCatalogWeb.Layouts, :live}}
    else
      socket =
        socket
        |> put_flash(:error, "Access denied. Admin privileges required.")
        |> push_navigate(to: ~p"/")

      {:ok, socket}
    end
  end

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

  @impl true
  def handle_event("refresh_provider", %{"provider" => provider_name}, socket) do
    Logger.info("Refresh provider button clicked for: #{provider_name}")

    case find_provider_module(provider_name) do
      nil ->
        Logger.error("Provider not found: #{provider_name}")
        {:noreply, put_flash(socket, :error, "Provider not found: #{provider_name}")}

      provider_module ->
        Logger.info("Found provider module: #{inspect(provider_module)}")

        if SyncStatusManager.syncing?(provider_name) do
          Logger.warning("Provider #{provider_name} is already syncing")
          {:noreply, put_flash(socket, :error, "#{provider_name} is already syncing")}
        else
          # Immediately set sync status to provide instant UI feedback
          case SyncStatusManager.start_sync(provider_name) do
            :ok ->
              Logger.info("Started sync status for #{provider_name}")
              spawn(fn -> sync_provider_with_status(provider_module) end)

              socket =
                socket
                |> put_flash(:info, "Started syncing #{provider_name}")
                |> assign(:providers, get_providers_with_status())

              {:noreply, socket}

            {:error, :already_syncing} ->
              Logger.warning("Provider #{provider_name} is already syncing")
              {:noreply, put_flash(socket, :error, "#{provider_name} is already syncing")}
          end
        end
    end
  end

  @impl true
  def handle_event("refresh_all", _params, socket) do
    Logger.info("Refresh all providers button clicked")

    if SyncStatusManager.any_syncing?() do
      Logger.warning("Some providers are already syncing")
      {:noreply, put_flash(socket, :error, "Some providers are already syncing")}
    else
      available_providers = get_available_provider_modules()
      Logger.info("Found #{length(available_providers)} available providers")

      if Enum.empty?(available_providers) do
        Logger.warning("No external library providers are available")
        {:noreply, put_flash(socket, :error, "No external library providers are available")}
      else
        # Immediately start sync status for all providers to provide instant UI feedback
        provider_names = Enum.map(available_providers, & &1.provider_name())
        sync_start_results = Enum.map(provider_names, &SyncStatusManager.start_sync/1)

        # Check if all providers started successfully
        if Enum.all?(sync_start_results, &(&1 == :ok)) do
          Logger.info("Started sync status for all providers")
          Task.start(fn -> sync_all_providers_with_status(available_providers) end)

          socket =
            socket
            |> assign(:syncing_all, true)
            |> put_flash(:info, "Started syncing all available providers")
            |> assign(:providers, get_providers_with_status())

          {:noreply, socket}
        else
          Logger.error("Failed to start sync for some providers: #{inspect(sync_start_results)}")
          {:noreply, put_flash(socket, :error, "Failed to start sync for some providers")}
        end
      end
    end
  end

  @impl true
  def handle_info({:sync_status_update, _provider_name, _status}, socket) do
    socket =
      socket
      |> assign(:providers, get_providers_with_status())
      |> assign(:syncing_all, SyncStatusManager.any_syncing?())

    {:noreply, socket}
  end

  # Private functions

  defp get_providers_with_status do
    status_map = SyncStatusManager.get_all_status()

    Enum.map(@providers, fn provider ->
      provider_status = Map.get(status_map, provider.name, %{status: :idle})

      Map.merge(provider, %{
        available: provider.module.available?(),
        sync_status: provider_status
      })
    end)
  end

  defp find_provider_module(provider_name) do
    @providers
    |> Enum.find(fn p -> p.name == provider_name end)
    |> case do
      nil -> nil
      provider -> provider.module
    end
  end

  defp get_available_provider_modules do
    @providers
    |> Enum.filter(fn p -> p.module.available?() end)
    |> Enum.map(fn p -> p.module end)
  end

  defp sync_provider_with_status(provider_module) do
    provider_name = provider_module.provider_name()
    Logger.info("AdminLive: Starting sync for #{provider_name}")

    try do
      Logger.info("AdminLive: Calling ExternalLibrarySync.sync_provider for #{provider_name}")
      {_provider, _stats} = ExternalLibrarySync.sync_provider(provider_module)
      Logger.info("AdminLive: ExternalLibrarySync.sync_provider completed for #{provider_name}")
    rescue
      error ->
        Logger.error("AdminLive: Sync failed for #{provider_name}: #{inspect(error)}")
        # ExternalLibrarySync should handle status updates, but let's be safe
        if SyncStatusManager.syncing?(provider_name) do
          SyncStatusManager.fail_sync(provider_name, inspect(error))
        end
    end
  end

  defp sync_all_providers_with_status(provider_modules) do
    try do
      # Sync each provider (start_sync was already called in handle_event)
      Enum.each(provider_modules, fn provider_module ->
        sync_provider_with_status(provider_module)
      end)
    rescue
      error ->
        Logger.error("Bulk sync failed: #{inspect(error)}")

        # Mark any still-syncing providers as failed
        Enum.each(provider_modules, fn provider_module ->
          provider_name = provider_module.provider_name()

          if SyncStatusManager.syncing?(provider_name) do
            SyncStatusManager.fail_sync(provider_name, "Bulk sync error: #{inspect(error)}")
          end
        end)
    end
  end

  def format_duration(started_at, completed_at \\ nil) do
    end_time = completed_at || DateTime.utc_now()
    duration = DateTime.diff(end_time, started_at, :second)

    cond do
      duration < 60 -> "#{duration}s"
      duration < 3600 -> "#{div(duration, 60)}m #{rem(duration, 60)}s"
      true -> "#{div(duration, 3600)}h #{div(rem(duration, 3600), 60)}m"
    end
  end

  def format_datetime(datetime) do
    case datetime do
      nil -> "Never"
      dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
    end
  end
end
