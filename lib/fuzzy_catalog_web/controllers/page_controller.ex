defmodule FuzzyCatalogWeb.PageController do
  use FuzzyCatalogWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
