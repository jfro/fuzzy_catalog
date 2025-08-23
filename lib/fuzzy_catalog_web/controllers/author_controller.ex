defmodule FuzzyCatalogWeb.AuthorController do
  use FuzzyCatalogWeb, :controller

  alias FuzzyCatalog.Catalog

  def show(conn, %{"name" => author_name}) do
    # URL decode the author name to handle spaces and special characters
    decoded_author_name = URI.decode(author_name)
    books = Catalog.get_books_by_author(decoded_author_name)

    case books do
      [] ->
        conn
        |> put_flash(:error, "No books found by author '#{decoded_author_name}'")
        |> redirect(to: ~p"/books")

      books ->
        render(conn, :show, author_name: decoded_author_name, books: books)
    end
  end
end