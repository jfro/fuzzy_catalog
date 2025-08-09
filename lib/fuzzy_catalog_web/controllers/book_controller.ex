defmodule FuzzyCatalogWeb.BookController do
  use FuzzyCatalogWeb, :controller

  alias FuzzyCatalog.Catalog
  alias FuzzyCatalog.Catalog.Book
  alias FuzzyCatalog.Catalog.BookLookup

  def index(conn, _params) do
    books = Catalog.list_books()
    render(conn, :index, books: books)
  end

  def show(conn, %{"id" => id}) do
    book = Catalog.get_book!(id)
    render(conn, :show, book: book)
  end

  def new(conn, params) do
    # Pre-fill form with lookup data if provided
    book_data = %{
      title: params["title"] || "",
      author: params["author"] || "",
      upc: params["upc"] || "",
      isbn10: params["isbn10"] || "",
      isbn13: params["isbn13"] || "",
      amazon_asin: params["amazon_asin"] || "",
      cover_url: params["cover_url"] || ""
    }

    changeset = Catalog.change_book(%Book{}, book_data)
    render(conn, :new, changeset: changeset)
  end

  def lookup(conn, %{"lookup_type" => "isbn", "isbn" => isbn}) when is_binary(isbn) do
    case BookLookup.lookup_by_isbn(String.trim(isbn)) do
      {:ok, book_data} ->
        changeset = Catalog.change_book(%Book{}, book_data)
        render(conn, :new, changeset: changeset, lookup_results: book_data)

      {:error, reason} ->
        changeset = Catalog.change_book(%Book{})
        render(conn, :new, changeset: changeset, lookup_error: reason)
    end
  end

  def lookup(conn, %{"lookup_type" => "upc", "upc" => upc}) when is_binary(upc) do
    case BookLookup.lookup_by_upc(String.trim(upc)) do
      {:ok, books} ->
        changeset = Catalog.change_book(%Book{})
        render(conn, :new, changeset: changeset, lookup_results: books)

      {:error, reason} ->
        changeset = Catalog.change_book(%Book{})
        render(conn, :new, changeset: changeset, lookup_error: reason)
    end
  end

  def lookup(conn, %{"lookup_type" => "title", "title" => title}) when is_binary(title) do
    case BookLookup.lookup_by_title(String.trim(title)) do
      {:ok, books} ->
        changeset = Catalog.change_book(%Book{})
        render(conn, :new, changeset: changeset, lookup_results: books)

      {:error, reason} ->
        changeset = Catalog.change_book(%Book{})
        render(conn, :new, changeset: changeset, lookup_error: reason)
    end
  end

  def lookup(conn, _params) do
    changeset = Catalog.change_book(%Book{})
    render(conn, :new, changeset: changeset, lookup_error: "Invalid lookup parameters")
  end

  def create(conn, %{"book" => book_params}) do
    case Catalog.create_book(book_params) do
      {:ok, book} ->
        conn
        |> put_flash(:info, "Book created successfully.")
        |> redirect(to: ~p"/books/#{book}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def edit(conn, %{"id" => id}) do
    book = Catalog.get_book!(id)
    changeset = Catalog.change_book(book)
    render(conn, :edit, book: book, changeset: changeset)
  end

  def update(conn, %{"id" => id, "book" => book_params}) do
    book = Catalog.get_book!(id)

    case Catalog.update_book(book, book_params) do
      {:ok, book} ->
        conn
        |> put_flash(:info, "Book updated successfully.")
        |> redirect(to: ~p"/books/#{book}")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit, book: book, changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    book = Catalog.get_book!(id)
    {:ok, _book} = Catalog.delete_book(book)

    conn
    |> put_flash(:info, "Book deleted successfully.")
    |> redirect(to: ~p"/books")
  end
end
