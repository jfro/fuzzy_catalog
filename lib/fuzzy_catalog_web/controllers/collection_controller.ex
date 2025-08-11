defmodule FuzzyCatalogWeb.CollectionController do
  use FuzzyCatalogWeb, :controller

  alias FuzzyCatalog.Collections
  alias FuzzyCatalog.Catalog
  alias FuzzyCatalog.Collections.CollectionItem

  def index(conn, _params) do
    user = conn.assigns.current_scope.user
    collections = Collections.list_collections(user)
    render(conn, :index, collections: collections)
  end

  def new(conn, params) do
    book =
      case Map.get(params, "book_id") do
        nil -> nil
        book_id -> Catalog.get_book!(book_id)
      end

    changeset = Collections.change_collection_item(%CollectionItem{})
    render(conn, :new, changeset: changeset, book: book)
  end

  def create(conn, %{"collection" => collection_params}) do
    user = conn.assigns.current_scope.user

    # Handle book creation/lookup
    media_type = Map.get(collection_params, "media_type", "unspecified")

    with {:ok, book} <- find_or_create_book(collection_params),
         {:ok, _collection} <-
           Collections.add_to_collection(user, book, media_type, collection_params) do
      conn
      |> put_flash(:info, "Book added to your collection successfully.")
      |> redirect(to: ~p"/collections")
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        book =
          case Map.get(collection_params, "book_id") do
            nil -> nil
            book_id -> Catalog.get_book!(book_id)
          end

        render(conn, :new, changeset: changeset, book: book)

      {:error, :book_already_in_collection} ->
        conn
        |> put_flash(:error, "This book is already in your collection.")
        |> redirect(to: ~p"/collections/new")
    end
  end

  def show(conn, %{"id" => id}) do
    collection = Collections.get_collection_item!(id)

    # Ensure user can only view their own collections
    if collection.user_id == conn.assigns.current_scope.user.id do
      render(conn, :show, collection: collection)
    else
      conn
      |> put_flash(:error, "You can only view your own collections.")
      |> redirect(to: ~p"/collections")
    end
  end

  def edit(conn, %{"id" => id}) do
    collection = Collections.get_collection_item!(id)

    # Ensure user can only edit their own collections
    if collection.user_id == conn.assigns.current_scope.user.id do
      changeset = Collections.change_collection_item(collection)
      render(conn, :edit, collection: collection, changeset: changeset)
    else
      conn
      |> put_flash(:error, "You can only edit your own collections.")
      |> redirect(to: ~p"/collections")
    end
  end

  def update(conn, %{"id" => id, "collection" => collection_params}) do
    collection = Collections.get_collection_item!(id)

    # Ensure user can only update their own collections
    if collection.user_id == conn.assigns.current_scope.user.id do
      case Collections.update_collection_item(collection, collection_params) do
        {:ok, collection} ->
          conn
          |> put_flash(:info, "Collection updated successfully.")
          |> redirect(to: ~p"/collections/#{collection}")

        {:error, %Ecto.Changeset{} = changeset} ->
          render(conn, :edit, collection: collection, changeset: changeset)
      end
    else
      conn
      |> put_flash(:error, "You can only edit your own collections.")
      |> redirect(to: ~p"/collections")
    end
  end

  def delete(conn, %{"id" => id}) do
    collection = Collections.get_collection_item!(id)

    # Ensure user can only delete their own collections
    if collection.user_id == conn.assigns.current_scope.user.id do
      {:ok, _collection} = Collections.remove_collection_item(collection)

      conn
      |> put_flash(:info, "Book removed from collection successfully.")
      |> redirect(to: ~p"/collections")
    else
      conn
      |> put_flash(:error, "You can only remove books from your own collections.")
      |> redirect(to: ~p"/collections")
    end
  end

  def add_book(conn, %{"book_id" => book_id} = params) do
    user = conn.assigns.current_scope.user
    book = Catalog.get_book!(book_id)

    media_type = Map.get(params, "media_type", "unspecified")

    case Collections.add_to_collection(user, book, media_type) do
      {:ok, _collection} ->
        conn
        |> put_flash(:info, "#{book.title} (#{media_type}) added to your collection.")
        |> redirect(to: ~p"/books/#{book}")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "This media type is already in your collection.")
        |> redirect(to: ~p"/books/#{book}")
    end
  end

  def remove_book(conn, %{"book_id" => book_id} = params) do
    user = conn.assigns.current_scope.user
    book = Catalog.get_book!(book_id)

    case Map.get(params, "media_type") do
      nil ->
        # Remove all media types
        case Collections.remove_all_from_collection(user, book) do
          {count, _} when count > 0 ->
            conn
            |> put_flash(:info, "#{book.title} removed from your collection.")
            |> redirect(to: ~p"/books/#{book}")

          {0, _} ->
            conn
            |> put_flash(:error, "This book is not in your collection.")
            |> redirect(to: ~p"/books/#{book}")
        end

      media_type ->
        # Remove specific media type
        case Collections.remove_from_collection(user, book, media_type) do
          {:ok, _collection} ->
            conn
            |> put_flash(:info, "#{book.title} (#{media_type}) removed from your collection.")
            |> redirect(to: ~p"/books/#{book}")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "This media type is not in your collection.")
            |> redirect(to: ~p"/books/#{book}")
        end
    end
  end

  def add_media_type(conn, %{"book_id" => book_id, "media_type" => media_type}) do
    user = conn.assigns.current_scope.user
    book = Catalog.get_book!(book_id)

    case Collections.add_to_collection(user, book, media_type) do
      {:ok, _collection} ->
        conn
        |> put_flash(:info, "#{media_type} added to your collection for #{book.title}.")
        |> redirect(to: ~p"/collections")

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_flash(:error, "This media type is already in your collection.")
        |> redirect(to: ~p"/collections")
    end
  end

  def update_media_type(conn, %{"id" => id, "media_type" => new_media_type}) do
    collection_item = Collections.get_collection_item!(id)
    user = conn.assigns.current_scope.user

    # Ensure user can only update their own collection items
    if collection_item.user_id == user.id do
      case Collections.update_collection_item(collection_item, %{media_type: new_media_type}) do
        {:ok, _item} ->
          conn
          |> put_flash(:info, "Media type updated successfully.")
          |> redirect(to: ~p"/collections")

        {:error, %Ecto.Changeset{}} ->
          conn
          |> put_flash(:error, "Unable to update media type - it may already exist.")
          |> redirect(to: ~p"/collections")
      end
    else
      conn
      |> put_flash(:error, "You can only edit your own collections.")
      |> redirect(to: ~p"/collections")
    end
  end

  defp find_or_create_book(%{"book_id" => book_id}) when book_id != "" and book_id != nil do
    {:ok, Catalog.get_book!(book_id)}
  end

  defp find_or_create_book(collection_params) do
    # Extract book data from collection params
    book_params =
      Map.take(collection_params, [
        "title",
        "author",
        "isbn10",
        "isbn13",
        "upc",
        "amazon_asin",
        "cover_url",
        "publisher",
        "publication_date",
        "pages",
        "genre",
        "subtitle",
        "description",
        "series",
        "series_number",
        "original_title"
      ])

    # Only proceed if we have at least title and author
    case {Map.get(book_params, "title"), Map.get(book_params, "author")} do
      {title, author}
      when is_binary(title) and title != "" and is_binary(author) and author != "" ->
        Catalog.find_or_create_book(book_params)

      _ ->
        {:error, :missing_book_data}
    end
  end
end
