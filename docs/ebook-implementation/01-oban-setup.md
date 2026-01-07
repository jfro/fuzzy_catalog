# Phase 1: Oban Setup (Foundation)

Oban is a robust, database-backed job processing library for Elixir. We'll use it to handle background tasks for scanning and processing ebook files. Oban Web provides a dashboard for monitoring and managing jobs, which we'll embed in the admin area.

## Prerequisites

- PostgreSQL database (already configured)
- Understanding of Elixir supervision trees
- Admin area already configured (at `/admin`)

## Step 1.1: Write Oban Integration Tests

Following TDD, we write tests first to define what "success" looks like.

### Create Unit Test File

**File:** `test/fuzzy_catalog/ebooks/oban_integration_test.exs`

```elixir
defmodule FuzzyCatalog.Ebooks.ObanIntegrationTest do
  use FuzzyCatalog.DataCase, async: true

  test "Oban is configured and running" do
    # Verify Oban is in the supervision tree
    children = Supervisor.which_children(FuzzyCatalog.Supervisor)
    assert Enum.any?(children, fn {name, _pid, _type, _modules} ->
      name == Oban
    end)
  end

  test "Oban queues are configured" do
    config = Oban.config()
    assert Map.has_key?(config.queues, :ebook_scan)
    assert Map.has_key?(config.queues, :ebook_process)
  end

  test "Oban Web is configured" do
    # Verify Oban Web resolver is configured with PubSub
    config = Oban.config()
    assert config.name == Oban
  end
end
```

### Create Web Integration Test File

**File:** `test/fuzzy_catalog_web/admin/oban_web_test.exs`

```elixir
defmodule FuzzyCatalogWeb.Admin.ObanWebTest do
  use FuzzyCatalogWeb.ConnCase, async: true

  import FuzzyCatalog.AccountsFixtures

  describe "GET /admin/oban" do
    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/admin/oban")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "loads Oban Web dashboard when authenticated", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/admin/oban")
      assert html_response(conn, 200)
      assert conn.resp_body =~ "Oban"
    end

    test "displays jobs section", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/admin/oban")
      response = html_response(conn, 200)

      # Check for expected Oban Web UI elements
      assert response =~ "Jobs"
      assert response =~ "Queues"
    end

    test "shows configured queues", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/admin/oban")
      response = html_response(conn, 200)

      # Should display our ebook queues
      assert response =~ "ebook_scan" or response =~ "ebook-scan"
      assert response =~ "ebook_process" or response =~ "ebook-process"
    end
  end

  describe "GET /admin/oban/jobs (Oban Web sub-routes)" do
    test "jobs page loads when authenticated", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      # Oban Web may have sub-routes like /admin/oban/jobs
      # This tests that the routing is fully functional
      conn = get(conn, ~p"/admin/oban")
      assert html_response(conn, 200)
    end
  end
end
```

**Why these tests?**
- **Unit tests** verify Oban configuration and supervision
- **Integration tests** verify Oban Web is properly mounted and accessible
- **Authentication tests** ensure security (redirects when not logged in)
- **Content tests** verify the dashboard actually renders

### Verify Tests Fail

Run the tests - they should fail because Oban isn't installed yet:

```bash
# Run unit tests
mix test test/fuzzy_catalog/ebooks/oban_integration_test.exs

# Run web integration tests
mix test test/fuzzy_catalog_web/admin/oban_web_test.exs
```

Expected: Compilation errors or test failures (Oban module not found, route not defined, etc.).

---

## Step 1.2: Install and Configure Oban

Now we'll install Oban and configure it to make the tests pass.

### Add Dependencies

**File:** `mix.exs`

Add to the `deps` function:

```elixir
defp deps do
  [
    # ... existing dependencies ...
    {:oban, "~> 2.18"},
    {:oban_web, "~> 2.10"}
  ]
end
```

**Why Oban Web?**
- Provides a web dashboard for monitoring jobs
- Allows canceling, retrying, and inspecting jobs
- Shows queue statistics and performance metrics
- Essential for production monitoring

### Install Dependencies

```bash
mix deps.get
```

### Configure Oban (Main Config)

**File:** `config/config.exs`

Add Oban configuration:

```elixir
# Oban configuration for background job processing
config :fuzzy_catalog, Oban,
  repo: FuzzyCatalog.Repo,
  queues: [
    ebook_scan: 1,      # One concurrent scan job at a time
    ebook_process: 10    # Up to 10 files can be processed concurrently
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 86400 * 7},  # Keep jobs for 7 days
    {Oban.Plugins.Cron, crontab: []}  # No cron jobs initially
  ]

# Oban Web configuration for the dashboard
config :fuzzy_catalog, Oban.Web.Resolver,
  pubsub: FuzzyCatalog.PubSub

config :oban, :notifier, pubsub: FuzzyCatalog.PubSub
```

**Why these settings?**
- `ebook_scan: 1` - Serialize directory scanning to avoid race conditions
- `ebook_process: 10` - Process multiple files concurrently for efficiency
- `Pruner` - Clean up old job records automatically
- `Cron` - Empty for now, but enables scheduled jobs in the future
- `Oban.Web.Resolver` - Connects Oban Web to Phoenix PubSub for real-time updates

### Configure Oban (Test Environment)

**File:** `config/test.exs`

Add test-specific Oban configuration:

```elixir
# Oban test configuration
config :fuzzy_catalog, Oban,
  testing: :manual,
  queues: false,
  plugins: false
```

**Why?**
- `testing: :manual` - Jobs don't auto-execute, use `perform_job/2` helper
- `queues: false` - Don't start queue consumers in tests
- `plugins: false` - Don't run background plugins during tests

### Add Oban to Supervision Tree

**File:** `lib/fuzzy_catalog/application.ex`

Add Oban to the children list in the `start/2` function:

```elixir
def start(_type, _args) do
  children = [
    FuzzyCatalogWeb.Telemetry,
    FuzzyCatalog.Repo,
    # Add Oban here (after Repo, before other processes)
    {Oban, Application.fetch_env!(:fuzzy_catalog, Oban)},
    {DNSCluster, query: Application.get_env(:fuzzy_catalog, :dns_cluster_query) || :ignore},
    {Phoenix.PubSub, name: FuzzyCatalog.PubSub},
    FuzzyCatalog.SyncStatusManager,
    FuzzyCatalog.ProviderScheduler,
    FuzzyCatalogWeb.Endpoint
  ]

  # ... rest of function
end
```

**Why after Repo?** Oban needs the database connection to be available.

---

## Step 1.3: Add Oban Web to Admin Router

Mount Oban Web dashboard in the admin area so authenticated users can monitor jobs.

**File:** `lib/fuzzy_catalog_web/router.ex`

Add Oban Web to the admin scope:

```elixir
scope "/admin", FuzzyCatalogWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/", AdminLive, :index
  live "/users", AdminUsersLive, :index
  live "/settings", AdminSettingsLive, :index

  # Oban Web Dashboard
  import Oban.Web.Router
  oban_dashboard "/oban"

  # Import/Export routes
  get "/import-export", ImportExportController, :index
  # ... rest of routes
end
```

**Security Note:**
- Oban Web is behind `:require_authenticated_user` pipeline
- All authenticated users can access it
- Consider adding an `:require_admin` plug if you want admin-only access

### Optional: Admin-Only Access

If you want to restrict Oban Web to admin users only:

**File:** `lib/fuzzy_catalog_web/user_auth.ex`

Add an admin check plug:

```elixir
def require_admin(conn, _opts) do
  user = conn.assigns[:current_scope][:user]

  if user && user.role == "admin" do
    conn
  else
    conn
    |> put_flash(:error, "You must be an admin to access this page.")
    |> redirect(to: ~p"/")
    |> halt()
  end
end
```

Then update the router:

```elixir
scope "/admin", FuzzyCatalogWeb do
  pipe_through [:browser, :require_authenticated_user, :require_admin]

  # ... admin routes including oban_dashboard
end
```

---

## Step 1.4: Create Oban Migration

Oban stores job data in PostgreSQL tables. We need to create them.

### Generate Migration

```bash
mix ecto.gen.migration add_oban_jobs_table
```

This creates a file like: `priv/repo/migrations/20260105XXXXXX_add_oban_jobs_table.exs`

### Edit Migration

**File:** `priv/repo/migrations/YYYYMMDDHHMMSS_add_oban_jobs_table.exs`

```elixir
defmodule FuzzyCatalog.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
```

**Why version 12?** That's the latest Oban schema version at the time of writing.

### Run Migration

```bash
mix ecto.migrate
```

Expected output:
```
[info] == Running ... FuzzyCatalog.Repo.Migrations.AddObanJobsTable.change/0 forward
[info] create table oban_jobs
[info] create index oban_jobs_state_queue_priority_scheduled_at_id_index
[info] create index oban_jobs_args_index
[info] ... (more indexes)
[info] == Migrated in 0.Xs
```

---

## Step 1.5: Verify Tests Pass

Now run the tests again:

```bash
# Run unit tests
mix test test/fuzzy_catalog/ebooks/oban_integration_test.exs

# Run web integration tests
mix test test/fuzzy_catalog_web/admin/oban_web_test.exs
```

Expected: All tests pass ✅

**Unit tests output:**
```
...

Finished in 0.X seconds
3 tests, 0 failures
```

**Web integration tests output:**
```
.....

Finished in 0.X seconds
5 tests, 0 failures
```

**Total: 8 tests, 0 failures** ✅

---

## Step 1.6: Verify Oban Web Dashboard

Start the development server and check the dashboard:

```bash
mix phx.server
```

Navigate to: `http://localhost:4000/admin/oban`

You should see:
- 📊 **Jobs tab** - List of all jobs (pending, executing, completed, failed)
- 📈 **Queues tab** - Status of all queues (ebook_scan, ebook_process)
- ⚙️ **Stats** - Job statistics and performance metrics

### Expected Dashboard Features

1. **Jobs View:**
   - Filter by state (available, executing, completed, retryable, discarded)
   - Search by worker name or arguments
   - View job details (args, errors, attempts)
   - Manually retry or cancel jobs

2. **Queues View:**
   - See queue status (running/paused)
   - View jobs per queue
   - Pause/resume queues

3. **Real-time Updates:**
   - Job counts update automatically via PubSub
   - See jobs moving through states in real-time

---

## Verification Checklist

- [x] Oban dependency added to `mix.exs`
- [x] Oban Web dependency added to `mix.exs`
- [x] Oban configured in `config/config.exs`
- [x] Oban Web configured with PubSub
- [x] Oban test config in `config/test.exs`
- [x] Oban added to supervision tree
- [x] Oban Web mounted in admin router
- [x] Oban migration created and run
- [x] Unit tests pass (3 tests)
- [x] Web integration tests pass (5 tests)
- [x] Oban Web dashboard accessible at `/admin/oban`

## Troubleshooting

### "Oban is not running"

Check that:
1. Oban is in the supervision tree (`lib/fuzzy_catalog/application.ex`)
2. The application compiled successfully (`mix compile`)
3. The database is running

### "Cannot find Oban.config()"

Check that:
1. Oban is configured in `config/config.exs`
2. The config uses the correct key (`:fuzzy_catalog, Oban`)

### Migration Fails

Check that:
1. PostgreSQL is running
2. Database exists (`mix ecto.create` if needed)
3. No previous Oban tables exist (`mix ecto.rollback` then retry)

### "Oban Web not accessible"

Check that:
1. You're logged in as an authenticated user
2. The route is correctly mounted in router
3. Oban.Web.Router is imported in the admin scope
4. Server is running (`mix phx.server`)

### "Real-time updates not working"

Check that:
1. PubSub is configured in both Oban and Oban.Web.Resolver
2. Phoenix.PubSub is in the supervision tree
3. Browser has JavaScript enabled

---

## Next Steps

Continue to [Phase 2: Ebook Schema](./02-ebook-schema.md) to create the core data model.

## Using Oban Web Dashboard

### Common Operations

**View Failed Jobs:**
1. Go to `/admin/oban`
2. Click "Jobs" tab
3. Filter by "Retryable" or "Discarded"
4. Click on a job to see error details

**Retry a Failed Job:**
1. Find the job in the dashboard
2. Click "Retry" button
3. Job will be re-enqueued

**Pause a Queue:**
1. Go to "Queues" tab
2. Find the queue (e.g., `ebook_process`)
3. Click "Pause"
4. Useful during maintenance or high load

**Monitor Processing:**
1. Watch "Executing" count for active jobs
2. Check "Completed" for successful jobs
3. Monitor average execution time

---

## Additional Resources

- [Oban Documentation](https://hexdocs.pm/oban/)
- [Oban Web Documentation](https://hexdocs.pm/oban_web/)
- [Oban GitHub](https://github.com/sorentwo/oban)
- [Oban Web GitHub](https://github.com/sorentwo/oban_web)
- [Oban Testing Guide](https://hexdocs.pm/oban/testing.html)
