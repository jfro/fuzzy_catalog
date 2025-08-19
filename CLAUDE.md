# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FuzzyCatalog is a Phoenix web application built with Elixir. It follows standard Phoenix 1.8 conventions with LiveView support, uses PostgreSQL for data persistence, and includes Tailwind CSS for styling.

## Development Commands

### Setup and Installation
```bash
mix setup                    # Install deps, setup database, build assets
mix deps.get                 # Install dependencies only
```

### Development Server
```bash
mix phx.server              # Start Phoenix server on localhost:4000
iex -S mix phx.server       # Start server with interactive Elixir shell
```

### Database Operations
```bash
mix ecto.create             # Create database
mix ecto.migrate            # Run migrations
mix ecto.drop               # Drop database
mix ecto.setup              # Create, migrate, and seed database
mix ecto.reset              # Drop and recreate database
```

### Asset Management
```bash
mix assets.setup            # Install Tailwind and esbuild if missing
mix assets.build            # Build assets for development
mix assets.deploy           # Build and minify assets for production
```

### Testing
```bash
mix test                    # Run all tests (sets up test database)
mix test path/to/test.exs   # Run specific test file
mix test --failed           # Re-run only failed tests
```

### Code Quality
```bash
mix precommit               # Run full precommit checks (compile, format, test)
mix compile                 # Compile project
mix compile --warnings-as-errors  # Compile with strict warnings
mix format                  # Format code
```

## Architecture Overview

### Application Structure
- **FuzzyCatalog**: Main application module containing business logic contexts
- **FuzzyCatalogWeb**: Web interface module with controllers, components, and LiveViews
- **FuzzyCatalog.Application**: OTP application supervisor managing child processes

### Key Components
- **Repo**: `FuzzyCatalog.Repo` - Ecto database interface
- **Endpoint**: `FuzzyCatalogWeb.Endpoint` - HTTP request entry point
- **Router**: `FuzzyCatalogWeb.Router` - URL routing
- **PubSub**: Phoenix PubSub for real-time features
- **Telemetry**: Application monitoring and metrics

### Directory Structure
```
lib/
├── fuzzy_catalog/          # Business logic contexts
│   ├── application.ex      # OTP application
│   ├── repo.ex            # Database interface
│   └── mailer.ex          # Email functionality
└── fuzzy_catalog_web/     # Web interface
    ├── components/        # Reusable UI components
    ├── controllers/       # HTTP controllers
    ├── endpoint.ex        # HTTP endpoint
    └── router.ex         # URL routing
```

### Testing Architecture
- **ConnCase**: For testing controllers and web functionality
- **DataCase**: For testing business logic with database access
- Uses Ecto SQL Sandbox for test isolation
- Supports async testing for database operations

### Configuration
- Environment-specific configs in `config/`
- Uses Bandit adapter for HTTP server
- Swoosh for email with local adapter in development
- esbuild and Tailwind for asset compilation

## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs:
  - A plug `:fetch_current_user` that is included in the default browser pipeline
  - A plug `:require_authenticated_user` that redirects to the log in page when the user is not authenticated
  - In both cases, a `@current_scope` is assigned to the Plug connection
  - A plug `redirect_if_user_is_authenticated` that redirects to a default path in case the user is authenticated - useful for a registration page that should only be shown to unauthenticated users
- **Always let the user know in which router scopes and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign a `current_user` assign**.
- To derive/access `current_user`, **always use the `current_scope.user` assign**, never use **`@current_user`** in templates
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct plug as described below**

### Routes that require authentication

Controller routes must be placed in a scope that sets the `:require_authenticated_user` plug:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      get "/", MyControllerThatRequiresAuth, :index
    end

### Routes that work with or without authentication

Controllers automatically have the `current_scope` available if they use the `:browser` pipeline.

## Phoenix/LiveView Patterns

When working with this codebase:
- Use `FuzzyCatalogWeb` macros (`use FuzzyCatalogWeb, :controller`, etc.)
- Follow Phoenix context patterns for business logic organization
- Do not leverage LiveView
- Use CoreComponents for consistent UI elements
- Follow Ecto patterns for database interactions

## Development Guidelines

### Project Guidelines
- Use `mix precommit` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps
- Use `mix run -e` to run inline elixir code

### Elixir Guidelines
- Elixir lists **do not support index based access via the access syntax** - use `Enum.at`, pattern matching, or `List` instead
- Elixir variables are immutable but can be rebound - for block expressions like `if`, `case`, `cond`, you must bind the result to a variable
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies
- **Never** use map access syntax (`changeset[:field]`) on structs - use direct field access or higher level APIs
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should end in a question mark, not start with `is_`

### Phoenix Guidelines
- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope
- You **never** need to create your own `alias` for route definitions - the `scope` provides the alias
- `Phoenix.View` is no longer needed or included with Phoenix, don't use it

### Ecto Guidelines
- **Always** preload Ecto associations in queries when they'll be accessed in templates
- Remember `import Ecto.Query` when writing `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text` columns
- `Ecto.Changeset.validate_number/2` does not support the `:allow_nil` option
- Use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields set programmatically (like `user_id`) must not be listed in `cast` calls for security

### Phoenix HTML Guidelines
- Phoenix templates **always** use `~H` or .html.heex files (HEEx), **never** use `~E`
- **Always** use imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` for forms
- Use `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))`)
- **Always** add unique DOM IDs to key elements for testing
- Elixir supports `if/else` but **does NOT support `if/else if`** - use `cond` or `case` for multiple conditionals
- HEEx require special tag annotation for literal curly braces - use `phx-no-curly-interpolation`
- HEEx class attrs support lists - use `[...]` syntax for multiple class values
- **Never** use `<% Enum.each %>` for template content - use `<%= for item <- @collection do %>`
- Use `<%!-- comment --%>` for HEEx HTML comments
- Use `{...}` for attribute interpolation and `<%= ... %>` for block constructs in tag bodies
