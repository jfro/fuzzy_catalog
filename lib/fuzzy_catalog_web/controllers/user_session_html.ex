defmodule FuzzyCatalogWeb.UserSessionHTML do
  use FuzzyCatalogWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:fuzzy_catalog, FuzzyCatalog.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
