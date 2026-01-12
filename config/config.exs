# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fuzzy_catalog, :scopes,
  user: [
    default: true,
    module: FuzzyCatalog.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: FuzzyCatalog.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :fuzzy_catalog,
  ecto_repos: [FuzzyCatalog.Repo],
  generators: [timestamp_type: :utc_datetime]

# Book lookup provider configuration
config :fuzzy_catalog, :book_lookup,
  providers: [
    FuzzyCatalog.Catalog.Providers.OpenLibraryProvider,
    FuzzyCatalog.Catalog.Providers.HardcoverProvider,
    FuzzyCatalog.Catalog.Providers.GoogleBooksProvider,
    FuzzyCatalog.Catalog.Providers.LibraryOfCongressProvider
  ]

# Hardcover API configuration
# Get your API token from https://hardcover.app/settings/api
config :fuzzy_catalog, :hardcover_api_token, System.get_env("HARDCOVER_API_TOKEN")

# File storage configuration
config :fuzzy_catalog, :storage,
  backend: FuzzyCatalog.Storage.Backends.LocalBackend,
  local: [
    base_path: System.get_env("UPLOAD_PATH") || "priv/static/uploads",
    base_url: "/uploads"
  ]

# Configures the endpoint
config :fuzzy_catalog, FuzzyCatalogWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FuzzyCatalogWeb.ErrorHTML, json: FuzzyCatalogWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FuzzyCatalog.PubSub,
  live_view: [signing_salt: "ceTZnIWw"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fuzzy_catalog, FuzzyCatalog.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fuzzy_catalog: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  fuzzy_catalog: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Flop
config :flop, repo: FuzzyCatalog.Repo

# Oban configuration for background job processing
config :fuzzy_catalog, Oban,
  repo: FuzzyCatalog.Repo,
  queues: [
    # One concurrent scan job at a time
    ebook_scan: 1,
    # Up to 10 files can be processed concurrently
    ebook_process: 10
  ],
  plugins: [
    # Keep jobs for 7 days
    {Oban.Plugins.Pruner, max_age: 86400 * 7},
    # No cron jobs initially
    {Oban.Plugins.Cron, crontab: []}
  ]

# Oban Web configuration for the dashboard
config :fuzzy_catalog, Oban.Web.Resolver, pubsub: FuzzyCatalog.PubSub

config :oban, :notifier, pubsub: FuzzyCatalog.PubSub

# =====================================================
# Ebook Management Configuration
# =====================================================
#
# This section configures the ebook library management system, including:
# - File format support and limits
# - Fuzzy matching for book linking
# - Automatic filesystem watching (auto_watch mode)
# - Scheduled scanning (scheduled mode)
#
# See lib/fuzzy_catalog/ebooks/library.ex for scan mode details

config :fuzzy_catalog, :ebooks,
  # Supported file formats for ebook scanning
  # Only files with these extensions will be processed during scans
  supported_formats: ["epub", "pdf"],

  # Maximum file size in bytes (100MB default)
  # Files larger than this will be skipped during scanning
  max_file_size: 100 * 1024 * 1024,

  # Enable fuzzy matching for book linking by default
  # When true, uses fuzzy string matching to link ebooks to existing books
  enable_fuzzy_matching: true,

  # Fuzzy matching threshold (0.0 - 1.0) - higher means stricter matching
  # 0.85 means 85% similarity required to consider a match
  fuzzy_threshold: 0.85,

  # FileSystem watcher configuration (for auto_watch mode)
  # When enabled, monitors library directories for file changes
  # Set to false in test environment to prevent interference
  watcher_enabled: true,

  # Debounce delay in milliseconds (wait for 5 seconds of no changes before scanning)
  # This prevents rapid-fire scans during bulk file operations
  # Libraries in auto_watch mode will wait this long after the last file change
  watcher_debounce_ms: 5000,

  # Library scheduler configuration (for scheduled mode)
  # When enabled, processes libraries with cron-based schedules
  # Set to false in test environment to prevent interference
  scheduler_enabled: true

# Note: Calibre library support is automatic - metadata.opf and cover.jpg
# files are automatically detected and parsed when found alongside ebook files

# =====================================================
# Library Management Workflow
# =====================================================
#
# ## Creating a Library
#
# 1. Navigate to /admin/libraries (admin users only)
# 2. Click "New Library"
# 3. Enter library name
# 4. Use "Browse" button to select directory path via tree picker
# 5. Choose scan mode:
#    - Manual: Trigger scans via "Scan Now" button
#    - Auto Watch: Automatic scans when files change (5s debounce)
#    - Scheduled: Scans on cron schedule (e.g., "0 */6 * * *")
# 6. If scheduled mode, enter cron expression
# 7. Click "Create"
#
# ## Scan Modes Explained
#
# ### Manual Mode
# - Scans only when you click "Scan Now" button
# - Best for: One-time imports, testing, infrequent updates
# - No background processes required
#
# ### Auto Watch Mode
# - Monitors directory for file changes using FileSystem library
# - Automatically triggers scan 5 seconds after last change
# - Best for: Active libraries with frequent additions
# - Requires: watcher_enabled: true (default)
# - Background process: LibraryWatcher GenServer
#
# ### Scheduled Mode
# - Runs scans on a cron schedule (e.g., every 6 hours)
# - Cron format: minute hour day month weekday
# - Examples:
#   - "0 */6 * * *" = every 6 hours
#   - "0 0 * * *" = daily at midnight
#   - "0 9 * * 1" = Mondays at 9am
# - Best for: Stable libraries with predictable update patterns
# - Requires: scheduler_enabled: true (default)
# - Background process: LibraryScheduler GenServer
#
# ## How Scanning Works
#
# 1. Library is marked as "scanning" to prevent concurrent scans
# 2. ScanWorker job is enqueued in Oban
# 3. ScanWorker recursively scans directory for .epub and .pdf files
# 4. For each ebook file:
#    - Extract metadata (title, author, ISBN, etc.)
#    - Create or update Ebook record
#    - Link to Library via library_id
#    - If Calibre metadata.opf exists, parse it for rich metadata
# 5. Library status updated to "idle" or "failed"
# 6. last_scanned_at timestamp recorded
#
# ## Error Handling
#
# - If scan fails, library status set to "failed"
# - Error message stored in last_scan_error field
# - Can retry by clicking "Scan Now" or waiting for next scheduled scan
# - Failed status does not prevent future scans
#
# ## Concurrent Scan Prevention
#
# - Only one scan can run per library at a time
# - scanning_status field acts as a lock
# - Manual, auto_watch, and scheduled modes all check this status
# - "Scan Now" button disabled while scanning in progress

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
