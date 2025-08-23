defmodule FuzzyCatalogWeb.SeriesController do
  use FuzzyCatalogWeb, :controller

  alias FuzzyCatalog.Catalog

  def show(conn, %{"name" => series_name}) do
    # URL decode the series name to handle spaces and special characters
    decoded_series_name = URI.decode(series_name)
    books = Catalog.get_books_by_series(decoded_series_name)

    case books do
      [] ->
        conn
        |> put_flash(:error, "No books found in series '#{decoded_series_name}'")
        |> redirect(to: ~p"/books")

      books ->
        render(conn, :show, series_name: decoded_series_name, books: books)
    end
  end
end
