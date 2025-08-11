defmodule FuzzyCatalogWeb.PageController do
  use FuzzyCatalogWeb, :controller

  def home(conn, _params) do
    # Redirect authenticated users directly to the library
    case conn.assigns[:current_scope] do
      nil -> render(conn, :home)
      _current_scope -> redirect(conn, to: ~p"/books")
    end
  end
end
