defmodule FuzzyCatalog.Collections do
  @moduledoc """
  The Collections context.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo

  alias FuzzyCatalog.Collections.Collection
  alias FuzzyCatalog.Catalog.Book
  alias FuzzyCatalog.Accounts.User

  @doc """
  Returns the list of collections for a user.

  ## Examples

      iex> list_collections(user)
      [%Collection{}, ...]

  """
  def list_collections(%User{id: user_id}) do
    Collection
    |> where([c], c.user_id == ^user_id)
    |> preload(:book)
    |> order_by([c], desc: c.added_at)
    |> Repo.all()
  end

  @doc """
  Gets a single collection entry.

  Raises `Ecto.NoResultsError` if the Collection does not exist.

  ## Examples

      iex> get_collection!(123)
      %Collection{}

      iex> get_collection!(456)
      ** (Ecto.NoResultsError)

  """
  def get_collection!(id), do: Repo.get!(Collection, id) |> Repo.preload(:book)

  @doc """
  Gets a collection entry for a user and book.

  ## Examples

      iex> get_user_book_collection(user, book)
      %Collection{}

      iex> get_user_book_collection(user, book)
      nil

  """
  def get_user_book_collection(%User{id: user_id}, %Book{id: book_id}) do
    Collection
    |> where([c], c.user_id == ^user_id and c.book_id == ^book_id)
    |> preload(:book)
    |> Repo.one()
  end

  @doc """
  Checks if a book is in user's collection.

  ## Examples

      iex> book_in_collection?(user, book)
      true

      iex> book_in_collection?(user, book)
      false

  """
  def book_in_collection?(%User{id: user_id}, %Book{id: book_id}) do
    Collection
    |> where([c], c.user_id == ^user_id and c.book_id == ^book_id)
    |> Repo.exists?()
  end

  @doc """
  Adds a book to user's collection.

  ## Examples

      iex> add_to_collection(user, book)
      {:ok, %Collection{}}

      iex> add_to_collection(user, book)
      {:error, %Ecto.Changeset{}}

  """
  def add_to_collection(%User{} = user, %Book{} = book, attrs \\ %{}) do
    %Collection{}
    |> Collection.changeset(Map.merge(attrs, %{user_id: user.id, book_id: book.id}))
    |> Repo.insert()
  end

  @doc """
  Updates a collection entry.

  ## Examples

      iex> update_collection(collection, %{notes: "Great book!"})
      {:ok, %Collection{}}

      iex> update_collection(collection, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_collection(%Collection{} = collection, attrs) do
    collection
    |> Collection.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Removes a book from user's collection.

  ## Examples

      iex> remove_from_collection(collection)
      {:ok, %Collection{}}

      iex> remove_from_collection(collection)
      {:error, %Ecto.Changeset{}}

  """
  def remove_from_collection(%Collection{} = collection) do
    Repo.delete(collection)
  end

  @doc """
  Removes a book from user's collection by user and book.

  ## Examples

      iex> remove_from_collection(user, book)
      {:ok, %Collection{}}

      iex> remove_from_collection(user, book)
      {:error, :not_found}

  """
  def remove_from_collection(%User{} = user, %Book{} = book) do
    case get_user_book_collection(user, book) do
      nil -> {:error, :not_found}
      collection -> remove_from_collection(collection)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking collection changes.

  ## Examples

      iex> change_collection(collection)
      %Ecto.Changeset{data: %Collection{}}

  """
  def change_collection(%Collection{} = collection, attrs \\ %{}) do
    Collection.changeset(collection, attrs)
  end
end
