import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/fuzzy_catalog start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :fuzzy_catalog, FuzzyCatalogWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :fuzzy_catalog, FuzzyCatalog.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :fuzzy_catalog, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Audiobookshelf configuration
  config :fuzzy_catalog, :audiobookshelf,
    url: System.get_env("AUDIOBOOKSHELF_URL"),
    api_key: System.get_env("AUDIOBOOKSHELF_API_KEY"),
    libraries: System.get_env("AUDIOBOOKSHELF_LIBRARIES")

  # Calibre configuration
  config :fuzzy_catalog, :calibre, library_path: System.get_env("CALIBRE_LIBRARY_PATH")

  # Storage configuration
  config :fuzzy_catalog, :storage,
    local: [
      base_path: System.get_env("UPLOAD_PATH") || "priv/static/uploads",
      base_url: "/uploads"
    ]

  config :fuzzy_catalog, FuzzyCatalogWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :fuzzy_catalog, FuzzyCatalogWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :fuzzy_catalog, FuzzyCatalogWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Configure mailer adapter based on environment variables.
  # Supports Local (default), Mailgun, and SMTP adapters.

  mailer_adapter = System.get_env("MAILER_ADAPTER", "local")

  case String.downcase(mailer_adapter) do
    "mailgun" ->
      mailgun_api_key =
        System.get_env("MAILGUN_API_KEY") ||
          raise """
          environment variable MAILGUN_API_KEY is missing.
          This is required when MAILER_ADAPTER is set to "mailgun".
          """

      mailgun_domain =
        System.get_env("MAILGUN_DOMAIN") ||
          raise """
          environment variable MAILGUN_DOMAIN is missing.
          This is required when MAILER_ADAPTER is set to "mailgun".
          """

      config :fuzzy_catalog, FuzzyCatalog.Mailer,
        adapter: Swoosh.Adapters.Mailgun,
        api_key: mailgun_api_key,
        domain: mailgun_domain

      config :swoosh, :api_client, Swoosh.ApiClient.Req

    "smtp" ->
      smtp_relay =
        System.get_env("SMTP_RELAY") ||
          raise """
          environment variable SMTP_RELAY is missing.
          This is required when MAILER_ADAPTER is set to "smtp".
          """

      smtp_username =
        System.get_env("SMTP_USERNAME") ||
          raise """
          environment variable SMTP_USERNAME is missing.
          This is required when MAILER_ADAPTER is set to "smtp".
          """

      smtp_password =
        System.get_env("SMTP_PASSWORD") ||
          raise """
          environment variable SMTP_PASSWORD is missing.
          This is required when MAILER_ADAPTER is set to "smtp".
          """

      smtp_port = String.to_integer(System.get_env("SMTP_PORT", "587"))
      smtp_ssl = System.get_env("SMTP_SSL", "false") in ~w(true 1)

      smtp_tls =
        case System.get_env("SMTP_TLS", "if_available") do
          "always" -> :always
          "never" -> :never
          _ -> :if_available
        end

      config :fuzzy_catalog, FuzzyCatalog.Mailer,
        adapter: Swoosh.Adapters.SMTP,
        relay: smtp_relay,
        port: smtp_port,
        username: smtp_username,
        password: smtp_password,
        ssl: smtp_ssl,
        tls: smtp_tls

    "local" ->
      config :fuzzy_catalog, FuzzyCatalog.Mailer, adapter: Swoosh.Adapters.Local

    _ ->
      raise """
      Invalid MAILER_ADAPTER value: #{mailer_adapter}
      Supported values are: "local", "mailgun", "smtp"
      """
  end

  # Configure email sender information
  config :fuzzy_catalog, :email,
    from_name: System.get_env("EMAIL_FROM_NAME", "FuzzyCatalog"),
    from_address: System.get_env("EMAIL_FROM_ADDRESS", "noreply@localhost")
end

# Configure OIDC
config :fuzzy_catalog, :oidc,
  client_id: System.get_env("OIDC_CLIENT_ID"),
  client_secret: System.get_env("OIDC_CLIENT_SECRET"),
  base_url: System.get_env("OIDC_BASE_URL"),
  redirect_uri: System.get_env("OIDC_REDIRECT_URI") || "http://localhost:4000/auth/oidc/callback",
  authorization_params: [scope: "openid profile email"]

config :fuzzy_catalog, :booklore,
  url: System.get_env("BOOKLORE_URL"),
  username: System.get_env("BOOKLORE_USERNAME"),
  password: System.get_env("BOOKLORE_PASSWORD")
