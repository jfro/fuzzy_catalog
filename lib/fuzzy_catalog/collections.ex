defmodule FuzzyCatalog.Collections do
  @moduledoc """
  The Collections context.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo

  alias FuzzyCatalog.Collections.CollectionItem
  alias FuzzyCatalog.Catalog.Book
  alias FuzzyCatalog.Accounts.User

  @doc """
  Returns the list of collection items for a user, grouped by book.

  ## Examples

      iex> list_collections(user)
      %{book_id => [%CollectionItem{}, ...]}

  """
  def list_collections(%User{id: user_id}) do
    CollectionItem
    |> where([ci], ci.user_id == ^user_id)
    |> preload(:book)
    |> order_by([ci], desc: ci.added_at)
    |> Repo.all()
    |> Enum.group_by(& &1.book_id)
  end

  @doc """
  Returns a flat list of collection items for a user.

  ## Examples

      iex> list_collection_items(user)
      [%CollectionItem{}, ...]

  """
  def list_collection_items(%User{id: user_id}) do
    CollectionItem
    |> where([ci], ci.user_id == ^user_id)
    |> preload(:book)
    |> order_by([ci], desc: ci.added_at)
    |> Repo.all()
  end

  @doc """
  Gets a single collection item.

  Raises `Ecto.NoResultsError` if the CollectionItem does not exist.

  ## Examples

      iex> get_collection_item!(123)
      %CollectionItem{}

      iex> get_collection_item!(456)
      ** (Ecto.NoResultsError)

  """
  def get_collection_item!(id), do: Repo.get!(CollectionItem, id) |> Repo.preload(:book)

  @doc """
  Gets all collection items for a user and book.

  ## Examples

      iex> get_user_book_items(user, book)
      [%CollectionItem{}, ...]

      iex> get_user_book_items(user, book)
      []

  """
  def get_user_book_items(%User{id: user_id}, %Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.user_id == ^user_id and ci.book_id == ^book_id)
    |> preload(:book)
    |> Repo.all()
  end

  @doc """
  Gets a specific collection item for a user, book, and media type.

  ## Examples

      iex> get_user_book_item(user, book, "paperback")
      %CollectionItem{}

      iex> get_user_book_item(user, book, "hardcover")
      nil

  """
  def get_user_book_item(%User{id: user_id}, %Book{id: book_id}, media_type) do
    CollectionItem
    |> where(
      [ci],
      ci.user_id == ^user_id and ci.book_id == ^book_id and ci.media_type == ^media_type
    )
    |> preload(:book)
    |> Repo.one()
  end

  @doc """
  Checks if a book is in user's collection (any media type).

  ## Examples

      iex> book_in_collection?(user, book)
      true

      iex> book_in_collection?(user, book)
      false

  """
  def book_in_collection?(%User{id: user_id}, %Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.user_id == ^user_id and ci.book_id == ^book_id)
    |> Repo.exists?()
  end

  @doc """
  Checks if a specific media type of a book is in user's collection.

  ## Examples

      iex> book_media_type_in_collection?(user, book, "paperback")
      true

      iex> book_media_type_in_collection?(user, book, "hardcover")
      false

  """
  def book_media_type_in_collection?(%User{id: user_id}, %Book{id: book_id}, media_type) do
    CollectionItem
    |> where(
      [ci],
      ci.user_id == ^user_id and ci.book_id == ^book_id and ci.media_type == ^media_type
    )
    |> Repo.exists?()
  end

  @doc """
  Adds a book to user's collection with specified media type.

  ## Examples

      iex> add_to_collection(user, book, "paperback")
      {:ok, %CollectionItem{}}

      iex> add_to_collection(user, book, "paperback", %{notes: "Great book!"})
      {:ok, %CollectionItem{}}

      iex> add_to_collection(user, book, "invalid_type")
      {:error, %Ecto.Changeset{}}

  """
  def add_to_collection(%User{} = user, %Book{} = book, media_type \\ "unspecified", attrs \\ %{}) do
    base_attrs = %{user_id: user.id, book_id: book.id, media_type: media_type}

    %CollectionItem{}
    |> CollectionItem.changeset(Map.merge(attrs, base_attrs))
    |> Repo.insert()
  end

  @doc """
  Updates a collection item.

  ## Examples

      iex> update_collection_item(collection_item, %{notes: "Great book!"})
      {:ok, %CollectionItem{}}

      iex> update_collection_item(collection_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_collection_item(%CollectionItem{} = collection_item, attrs) do
    collection_item
    |> CollectionItem.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Removes a collection item.

  ## Examples

      iex> remove_collection_item(collection_item)
      {:ok, %CollectionItem{}}

      iex> remove_collection_item(collection_item)
      {:error, %Ecto.Changeset{}}

  """
  def remove_collection_item(%CollectionItem{} = collection_item) do
    Repo.delete(collection_item)
  end

  @doc """
  Removes a specific media type from user's collection.

  ## Examples

      iex> remove_from_collection(user, book, "paperback")
      {:ok, %CollectionItem{}}

      iex> remove_from_collection(user, book, "hardcover")
      {:error, :not_found}

  """
  def remove_from_collection(%User{} = user, %Book{} = book, media_type) do
    case get_user_book_item(user, book, media_type) do
      nil -> {:error, :not_found}
      collection_item -> remove_collection_item(collection_item)
    end
  end

  @doc """
  Removes all media types of a book from user's collection.

  ## Examples

      iex> remove_all_from_collection(user, book)
      {3, nil}

  """
  def remove_all_from_collection(%User{id: user_id}, %Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.user_id == ^user_id and ci.book_id == ^book_id)
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking collection item changes.

  ## Examples

      iex> change_collection_item(collection_item)
      %Ecto.Changeset{data: %CollectionItem{}}

  """
  def change_collection_item(%CollectionItem{} = collection_item, attrs \\ %{}) do
    CollectionItem.changeset(collection_item, attrs)
  end
end
