defmodule FuzzyCatalog.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Conditionally start LibraryWatcher based on config
    library_watcher_child =
      if watcher_enabled?() do
        [FuzzyCatalog.Ebooks.LibraryWatcher]
      else
        []
      end

    # Conditionally start LibraryScheduler based on config
    library_scheduler_child =
      if scheduler_enabled?() do
        [FuzzyCatalog.Ebooks.LibraryScheduler]
      else
        []
      end

    children =
      [
        FuzzyCatalogWeb.Telemetry,
        FuzzyCatalog.Repo,
        {Oban, Application.fetch_env!(:fuzzy_catalog, Oban)},
        {DNSCluster, query: Application.get_env(:fuzzy_catalog, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: FuzzyCatalog.PubSub},
        FuzzyCatalog.SyncStatusManager,
        FuzzyCatalog.ProviderScheduler
      ] ++
        library_watcher_child ++
        library_scheduler_child ++
        [
          # Start a worker by calling: FuzzyCatalog.Worker.start_link(arg)
          # {FuzzyCatalog.Worker, arg},
          # Start to serve requests, typically the last entry
          FuzzyCatalogWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FuzzyCatalog.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FuzzyCatalogWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp watcher_enabled? do
    Application.get_env(:fuzzy_catalog, :ebooks, [])
    |> Keyword.get(:watcher_enabled, true)
  end

  defp scheduler_enabled? do
    Application.get_env(:fuzzy_catalog, :ebooks, [])
    |> Keyword.get(:scheduler_enabled, true)
  end
end
