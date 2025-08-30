defmodule FuzzyCatalogWeb.UserSessionHTML do
  use FuzzyCatalogWeb, :html

  embed_templates "user_session_html/*"

  defp local_mail_adapter? do
    Application.get_env(:fuzzy_catalog, FuzzyCatalog.Mailer)[:adapter] == Swoosh.Adapters.Local
  end

  defp oidc_enabled? do
    config = Application.get_env(:fuzzy_catalog, :oidc, [])
    config[:client_id] && config[:client_secret] && config[:base_url]
  end
end
