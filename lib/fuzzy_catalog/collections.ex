defmodule FuzzyCatalog.Collections do
  @moduledoc """
  The Collections context.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo

  alias FuzzyCatalog.Collections.CollectionItem
  alias FuzzyCatalog.Catalog.Book

  @doc """
  Returns the list of all collection items, grouped by book.

  ## Examples

      iex> list_collections()
      %{book_id => [%CollectionItem{}, ...]}

  """
  def list_collections do
    CollectionItem
    |> preload(:book)
    |> order_by([ci], desc: ci.added_at)
    |> Repo.all()
    |> Enum.group_by(& &1.book_id)
  end

  @doc """
  Returns a flat list of all collection items.

  ## Examples

      iex> list_collection_items()
      [%CollectionItem{}, ...]

  """
  def list_collection_items do
    CollectionItem
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
  Gets all collection items for a book.

  ## Examples

      iex> get_book_items(book)
      [%CollectionItem{}, ...]

      iex> get_book_items(book)
      []

  """
  def get_book_items(%Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id)
    |> preload(:book)
    |> Repo.all()
  end

  @doc """
  Gets a specific collection item for a book and media type.

  ## Examples

      iex> get_book_item(book, "paperback")
      %CollectionItem{}

      iex> get_book_item(book, "hardcover")
      nil

  """
  def get_book_item(%Book{id: book_id}, media_type) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id and ci.media_type == ^media_type)
    |> preload(:book)
    |> Repo.one()
  end

  @doc """
  Gets a collection item by external_id.

  ## Examples

      iex> get_collection_item_by_external_id("audiobookshelf-123")
      %CollectionItem{}

      iex> get_collection_item_by_external_id("nonexistent")
      nil

  """
  def get_collection_item_by_external_id(external_id) when is_binary(external_id) do
    CollectionItem
    |> where([ci], ci.external_id == ^external_id)
    |> preload(:book)
    |> limit(1)
    |> Repo.one()
  end

  def get_collection_item_by_external_id(_), do: nil

  @doc """
  Checks if a book is in the collection (any media type).

  ## Examples

      iex> book_in_collection?(book)
      true

      iex> book_in_collection?(book)
      false

  """
  def book_in_collection?(%Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id)
    |> Repo.exists?()
  end

  @doc """
  Checks if a specific media type of a book is in the collection.

  ## Examples

      iex> book_media_type_in_collection?(book, "paperback")
      true

      iex> book_media_type_in_collection?(book, "hardcover")
      false

  """
  def book_media_type_in_collection?(%Book{id: book_id}, media_type) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id and ci.media_type == ^media_type)
    |> Repo.exists?()
  end

  @doc """
  Adds a book to the collection with specified media type.

  ## Examples

      iex> add_to_collection(book, "paperback")
      {:ok, %CollectionItem{}}

      iex> add_to_collection(book, "paperback", %{notes: "Great book!"})
      {:ok, %CollectionItem{}}

      iex> add_to_collection(book, "invalid_type")
      {:error, %Ecto.Changeset{}}

  """
  def add_to_collection(%Book{} = book, media_type \\ "unspecified", attrs \\ %{}) do
    base_attrs = %{book_id: book.id, media_type: media_type}

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
  Removes a specific media type from the collection.

  ## Examples

      iex> remove_from_collection(book, "paperback")
      {:ok, %CollectionItem{}}

      iex> remove_from_collection(book, "hardcover")
      {:error, :not_found}

  """
  def remove_from_collection(%Book{} = book, media_type) do
    case get_book_item(book, media_type) do
      nil -> {:error, :not_found}
      collection_item -> remove_collection_item(collection_item)
    end
  end

  @doc """
  Removes all media types of a book from the collection.

  ## Examples

      iex> remove_all_from_collection(book)
      {3, nil}

  """
  def remove_all_from_collection(%Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id)
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

  @doc """
  Gets all media types for a book that are in the library.

  ## Examples

      iex> get_book_media_types(book)
      ["paperback", "audiobook"]

  """
  def get_book_media_types(%Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id)
    |> select([ci], ci.media_type)
    |> order_by([ci], ci.media_type)
    |> Repo.all()
  end

  @doc """
  Gets all collection items for a book with their external library data.

  Returns a map where keys are media types and values are maps containing
  the external_id and any other external library information.

  ## Examples

      iex> get_book_external_data(book)
      %{"audiobook" => %{external_id: "abc123", media_type: "audiobook"},
        "paperbook" => %{external_id: nil, media_type: "paperback"}}

  """
  def get_book_external_data(%Book{id: book_id}) do
    CollectionItem
    |> where([ci], ci.book_id == ^book_id)
    |> select([ci], %{media_type: ci.media_type, external_id: ci.external_id})
    |> order_by([ci], ci.media_type)
    |> Repo.all()
    |> Enum.into(%{}, fn item -> {item.media_type, item} end)
  end

  @doc """
  Gets all books that are in the library with their media types.

  ## Examples

      iex> list_library_books()
      [%Book{media_types: ["paperback", "audiobook"]}, ...]

      iex> list_library_books(%{page: 1, page_size: 10})
      {[%Book{media_types: ["paperback", "audiobook"]}, ...], %Flop.Meta{...}}

  """
  def list_library_books(params \\ %{}) do
    # Extract search parameters
    search_term = get_search_term(params)

    # Remove search from Flop params to avoid validation issues
    flop_params = remove_search_param(params)

    base_query =
      from b in Book,
        join: ci in CollectionItem,
        on: ci.book_id == b.id,
        group_by: [b.id],
        select: {b, fragment("array_agg(? ORDER BY ?)::text[]", ci.media_type, ci.media_type)}

    # Apply search filter if present
    query_with_search =
      if search_term && String.trim(search_term) != "" do
        apply_search_filter(base_query, search_term)
      else
        base_query
      end

    case Flop.validate_and_run(query_with_search, flop_params, for: Book) do
      {:ok, {books_with_media_types, meta}} ->
        books =
          books_with_media_types
          |> Enum.map(fn {book, media_types} ->
            Map.put(book, :media_types, media_types)
          end)

        # Add search filter back to meta for UI display
        meta_with_search = add_search_to_meta(meta, search_term)
        {books, meta_with_search}

      {:error, %Flop.Meta{} = flop} ->
        meta_with_search = add_search_to_meta(flop, search_term)
        {[], meta_with_search}
    end
  end

  defp get_search_term(%{"filters" => %{"search" => search_term}}) when is_binary(search_term),
    do: search_term

  defp get_search_term(_), do: nil

  defp remove_search_param(%{"filters" => filters} = params) do
    updated_filters = Map.delete(filters, "search")

    if updated_filters == %{} do
      Map.delete(params, "filters")
    else
      Map.put(params, "filters", updated_filters)
    end
  end

  defp remove_search_param(params), do: params

  defp apply_search_filter(query, search_term) do
    import Ecto.Query
    search_pattern = "%#{search_term}%"

    from b in query,
      where:
        ilike(b.title, ^search_pattern) or
          ilike(b.author, ^search_pattern) or
          ilike(b.series, ^search_pattern)
  end

  defp add_search_to_meta(%Flop.Meta{} = meta, search_term)
       when is_binary(search_term) and search_term != "" do
    search_filter = %Flop.Filter{field: :search, op: :ilike, value: search_term}
    updated_flop = %{meta.flop | filters: [search_filter | meta.flop.filters]}
    %{meta | flop: updated_flop}
  end

  defp add_search_to_meta(meta, _), do: meta
end
