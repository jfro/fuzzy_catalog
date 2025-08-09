defmodule FuzzyCatalog.Repo do
  use Ecto.Repo,
    otp_app: :fuzzy_catalog,
    adapter: Ecto.Adapters.Postgres
end
