defmodule FuzzyCatalogWeb.BookController do
  use FuzzyCatalogWeb, :controller

  require Logger

  alias FuzzyCatalog.Catalog
  alias FuzzyCatalog.Catalog.Book
  alias FuzzyCatalog.Catalog.BookLookup
  alias FuzzyCatalog.Collections
  alias FuzzyCatalog.Storage

  def index(conn, _params) do
    books = Collections.list_library_books()
    render(conn, :index, books: books)
  end

  def show(conn, %{"id" => id}) do
    book = Catalog.get_book!(id)
    media_types = Collections.get_book_media_types(book)

    current_user =
      case conn.assigns[:current_scope] do
        nil -> nil
        current_scope -> current_scope.user
      end

    render(conn, :show,
      book: book,
      media_types: media_types,
      current_user: current_user
    )
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

  def scan_barcode(conn, params) do
    Logger.info("scan_barcode called with params: #{inspect(params)}")

    case params do
      %{"barcode" => barcode} when is_binary(barcode) ->
        raw_barcode = String.trim(barcode)
        Logger.info("Raw barcode: #{raw_barcode}")

        # Extract valid ISBN from potentially longer barcode
        case extract_isbn(raw_barcode) do
          {:ok, isbn} ->
            Logger.info("Extracted ISBN: #{isbn}")
            process_barcode_scan(conn, isbn)

          {:error, reason} ->
            Logger.warning("Failed to extract ISBN: #{reason}")

            conn
            |> put_flash(:error, "Invalid ISBN format in barcode: #{reason}")
            |> redirect(to: ~p"/books/new")
        end

      _ ->
        Logger.warning("Invalid barcode params: #{inspect(params)}")

        conn
        |> put_flash(:error, "Invalid barcode data")
        |> redirect(to: ~p"/books/new")
    end
  end

  defp process_barcode_scan(conn, clean_barcode) do
    # First check if book already exists in database
    case Catalog.get_book_by_isbn(clean_barcode) do
      nil ->
        # Book doesn't exist, try to lookup and create it
        case BookLookup.lookup_by_isbn(clean_barcode) do
          {:ok, book_data} ->
            # Create the book with initial media type (ensure consistent string keys)
            book_params =
              book_data
              |> Enum.map(fn {k, v} -> {to_string(k), v} end)
              |> Map.new()
              |> Map.put("media_type", "unspecified")

            # Download and store cover if available
            processed_params = download_cover_from_params(book_params)

            case Catalog.create_book(processed_params) do
              {:ok, book} ->
                conn
                |> put_flash(:info, "Book '#{book.title}' successfully added to library!")
                |> redirect(to: ~p"/books/#{book}")

              {:error, _changeset} ->
                conn
                |> put_flash(:error, "Failed to add book to library. Please try again.")
                |> redirect(to: ~p"/books/new")
            end

          {:error, reason} ->
            conn
            |> put_flash(:error, "Could not find book information for barcode: #{reason}")
            |> redirect(to: ~p"/books/new")
        end

      existing_book ->
        # Book already exists, show it
        conn
        |> put_flash(:info, "Book '#{existing_book.title}' is already in the library!")
        |> redirect(to: ~p"/books/#{existing_book}")
    end
  end

  # Extract valid ISBN from potentially longer barcode
  defp extract_isbn(barcode) do
    # Remove any non-digit characters except X (for ISBN-10)
    clean = String.replace(barcode, ~r/[^0-9X]/, "")

    cond do
      # ISBN-13 (13 digits)
      String.length(clean) >= 13 ->
        isbn13 = String.slice(clean, 0, 13)

        if validate_isbn_format(isbn13),
          do: {:ok, isbn13},
          else: {:error, "Invalid ISBN-13 format"}

      # ISBN-10 (10 digits, may end with X)
      String.length(clean) >= 10 ->
        isbn10 = String.slice(clean, 0, 10)

        if validate_isbn_format(isbn10),
          do: {:ok, isbn10},
          else: {:error, "Invalid ISBN-10 format"}

      # Too short to be a valid ISBN
      true ->
        {:error, "Barcode too short to contain valid ISBN"}
    end
  end

  # Basic ISBN format validation
  defp validate_isbn_format(isbn) do
    case String.length(isbn) do
      13 -> String.match?(isbn, ~r/^[0-9]{13}$/)
      10 -> String.match?(isbn, ~r/^[0-9]{9}[0-9X]$/)
      _ -> false
    end
  end

  def create(conn, %{"book" => book_params}) do
    # For create, we don't have an existing book so pass %Book{}
    processed_params = process_cover_params(book_params, %Book{})

    case Catalog.create_book(processed_params) do
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
    processed_params = process_cover_params(book_params, book)

    case Catalog.update_book(book, processed_params) do
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

    # Clean up cover image if it exists
    if book.cover_image_key do
      Storage.delete_cover(book.cover_image_key)
    end

    {:ok, _book} = Catalog.delete_book(book)

    conn
    |> put_flash(:info, "Book deleted successfully.")
    |> redirect(to: ~p"/books")
  end

  def add_media_type(conn, %{"book_id" => book_id, "media_type" => media_type}) do
    book = Catalog.get_book!(book_id)

    case Collections.add_to_collection(book, media_type) do
      {:ok, _collection} ->
        conn
        |> put_flash(:info, "#{String.capitalize(media_type)} added to library.")
        |> redirect(to: ~p"/books/#{book}")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "This media type is already in the library.")
        |> redirect(to: ~p"/books/#{book}")
    end
  end

  def remove_media_type(conn, %{"book_id" => book_id, "media_type" => media_type}) do
    book = Catalog.get_book!(book_id)

    case Collections.remove_from_collection(book, media_type) do
      {:ok, _collection} ->
        conn
        |> put_flash(:info, "#{String.capitalize(media_type)} removed from library.")
        |> redirect(to: ~p"/books/#{book}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "This media type is not in the library.")
        |> redirect(to: ~p"/books/#{book}")
    end
  end

  def batch_scanner(conn, _params) do
    render(conn, :batch_scanner)
  end

  def batch_check(conn, %{"barcode" => barcode}) when is_binary(barcode) do
    raw_barcode = String.trim(barcode)
    Logger.info("Batch check for barcode: #{raw_barcode}")

    case extract_isbn(raw_barcode) do
      {:ok, isbn} ->
        case Catalog.get_book_by_isbn(isbn) do
          nil ->
            json(conn, %{exists: false, isbn: isbn})

          existing_book ->
            json(conn, %{
              exists: true,
              isbn: isbn,
              book: %{
                id: existing_book.id,
                title: existing_book.title,
                author: existing_book.author
              }
            })
        end

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid barcode: #{reason}"})
    end
  end

  def batch_check(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing barcode parameter"})
  end

  def batch_add(conn, %{"barcode" => barcode, "media_type" => media_type})
      when is_binary(barcode) and is_binary(media_type) do
    raw_barcode = String.trim(barcode)
    Logger.info("Batch add for barcode: #{raw_barcode}, media_type: #{media_type}")

    case extract_isbn(raw_barcode) do
      {:ok, isbn} ->
        case BookLookup.lookup_by_isbn(isbn) do
          {:ok, book_data} ->
            book_params =
              book_data
              |> Enum.map(fn {k, v} -> {to_string(k), v} end)
              |> Map.new()
              |> Map.put("media_type", media_type)

            # Download and store cover if available
            processed_params = download_cover_from_params(book_params)

            case Catalog.create_book(processed_params) do
              {:ok, book} ->
                json(conn, %{
                  success: true,
                  book: %{
                    id: book.id,
                    title: book.title,
                    author: book.author,
                    isbn: isbn,
                    media_type: media_type
                  }
                })

              {:error, changeset} ->
                conn
                |> put_status(400)
                |> json(%{error: "Failed to create book", details: changeset.errors})
            end

          {:error, reason} ->
            conn
            |> put_status(404)
            |> json(%{error: "Book not found: #{reason}"})
        end

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid barcode: #{reason}"})
    end
  end

  def batch_add(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing required parameters: barcode and media_type"})
  end

  # Private helper functions

  defp process_cover_params(book_params, existing_book) do
    book_params
    |> handle_cover_upload()
    |> handle_cover_removal(existing_book)
  end

  defp handle_cover_upload(book_params) do
    case book_params["cover_image"] do
      %Plug.Upload{} = upload ->
        case store_uploaded_cover(upload) do
          {:ok, storage_key} ->
            Map.put(book_params, "cover_image_key", storage_key)

          {:error, reason} ->
            Logger.error("Failed to upload cover image: #{reason}")
            book_params
        end

      _ ->
        book_params
    end
    |> Map.delete("cover_image")
  end

  defp handle_cover_removal(book_params, existing_book) do
    case book_params["remove_cover"] do
      "true" ->
        # Clean up old cover if it exists
        if existing_book.cover_image_key do
          Storage.delete_cover(existing_book.cover_image_key)
        end

        book_params
        |> Map.put("cover_image_key", nil)
        |> Map.delete("remove_cover")

      _ ->
        Map.delete(book_params, "remove_cover")
    end
  end

  defp store_uploaded_cover(%Plug.Upload{path: path, content_type: content_type}) do
    case File.read(path) do
      {:ok, content} ->
        extension =
          content_type
          |> String.split("/")
          |> List.last()
          |> case do
            "jpeg" -> ".jpg"
            "jpg" -> ".jpg"
            "png" -> ".png"
            "gif" -> ".gif"
            "webp" -> ".webp"
            _ -> ".jpg"
          end

        Storage.store_cover(content, content_type: content_type, extension: extension)

      {:error, reason} ->
        {:error, "Failed to read uploaded file: #{reason}"}
    end
  end

  defp download_cover_from_params(book_params) do
    cover_url = book_params["cover_url"]

    if is_binary(cover_url) && String.trim(cover_url) != "" do
      case Storage.download_and_store_cover(cover_url) do
        {:ok, storage_key} ->
          Map.put(book_params, "cover_image_key", storage_key)

        {:error, reason} ->
          Logger.warning("Failed to download cover during book creation: #{reason}")
          book_params
      end
    else
      book_params
    end
  end
end
