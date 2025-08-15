defmodule FuzzyCatalog.Catalog do
  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.TitleUtils

  alias FuzzyCatalog.Catalog.Book

  @doc """
  Returns the list of books.

  ## Examples

      iex> list_books()
      [%Book{}, ...]

  """
  def list_books do
    Repo.all(Book)
  end

  @doc """
  Gets a single book.

  Raises `Ecto.NoResultsError` if the Book does not exist.

  ## Examples

      iex> get_book!(123)
      %Book{}

      iex> get_book!(456)
      ** (Ecto.NoResultsError)

  """
  def get_book!(id), do: Repo.get!(Book, id)

  @doc """
  Creates a book and automatically adds it to the library with an initial media type.

  ## Examples

      iex> create_book(%{field: value})
      {:ok, %Book{}}

      iex> create_book(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_book(attrs \\ %{}) do
    media_type = Map.get(attrs, "media_type", "unspecified")

    case %Book{}
         |> Book.changeset(attrs)
         |> Repo.insert() do
      {:ok, book} ->
        # Automatically add the book to the collection with the specified media type
        case FuzzyCatalog.Collections.add_to_collection(book, media_type) do
          {:ok, _collection_item} -> {:ok, book}
          # Book created successfully, collection item failed
          {:error, _changeset} -> {:ok, book}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Creates a book without automatically adding to collection.
  Used by external sync processes that handle collection management separately.

  ## Examples

      iex> create_book_without_collection(%{field: value})
      {:ok, %Book{}}

      iex> create_book_without_collection(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_book_without_collection(attrs \\ %{}) do
    %Book{}
    |> Book.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a book.

  ## Examples

      iex> update_book(book, %{field: new_value})
      {:ok, %Book{}}

      iex> update_book(book, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_book(%Book{} = book, attrs) do
    book
    |> Book.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a book.

  ## Examples

      iex> delete_book(book)
      {:ok, %Book{}}

      iex> delete_book(book)
      {:error, %Ecto.Changeset{}}

  """
  def delete_book(%Book{} = book) do
    Repo.delete(book)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking book changes.

  ## Examples

      iex> change_book(book)
      %Ecto.Changeset{data: %Book{}}

  """
  def change_book(%Book{} = book, attrs \\ %{}) do
    Book.changeset(book, attrs)
  end

  @doc """
  Finds a book by identifiers (title, UPC, ISBN, etc.) or creates it if it doesn't exist.
  This is used when adding books to collections to ensure shared book records.

  ## Examples

      iex> find_or_create_book(%{title: "Book Title", author: "Author"})
      {:ok, %Book{}}

      iex> find_or_create_book(%{title: "Book Title", author: "Author", isbn13: "1234567890123"})
      {:ok, %Book{}}

  """
  def find_or_create_book(attrs) do
    # Try to find existing book by various identifiers
    existing_book = find_existing_book(attrs)

    case existing_book do
      nil ->
        create_book(attrs)

      book ->
        # Update existing book with any new information
        update_book(book, attrs)
    end
  end

  defp find_existing_book(attrs) do
    query = from(b in Book)

    query =
      query
      |> maybe_filter_by_isbn13(attrs)
      |> maybe_filter_by_isbn10(attrs)
      |> maybe_filter_by_upc(attrs)
      |> maybe_filter_by_amazon_asin(attrs)
      |> maybe_filter_by_title_author(attrs)

    Repo.one(query)
  end

  defp maybe_filter_by_isbn13(query, %{"isbn13" => isbn13})
       when is_binary(isbn13) and isbn13 != "",
       do: where(query, [b], b.isbn13 == ^isbn13)

  defp maybe_filter_by_isbn13(query, %{isbn13: isbn13}) when is_binary(isbn13) and isbn13 != "",
    do: where(query, [b], b.isbn13 == ^isbn13)

  defp maybe_filter_by_isbn13(query, _), do: query

  defp maybe_filter_by_isbn10(query, %{"isbn10" => isbn10})
       when is_binary(isbn10) and isbn10 != "",
       do: where(query, [b], b.isbn10 == ^isbn10)

  defp maybe_filter_by_isbn10(query, %{isbn10: isbn10}) when is_binary(isbn10) and isbn10 != "",
    do: where(query, [b], b.isbn10 == ^isbn10)

  defp maybe_filter_by_isbn10(query, _), do: query

  defp maybe_filter_by_upc(query, %{"upc" => upc}) when is_binary(upc) and upc != "",
    do: where(query, [b], b.upc == ^upc)

  defp maybe_filter_by_upc(query, %{upc: upc}) when is_binary(upc) and upc != "",
    do: where(query, [b], b.upc == ^upc)

  defp maybe_filter_by_upc(query, _), do: query

  defp maybe_filter_by_amazon_asin(query, %{"amazon_asin" => asin})
       when is_binary(asin) and asin != "",
       do: where(query, [b], b.amazon_asin == ^asin)

  defp maybe_filter_by_amazon_asin(query, %{amazon_asin: asin})
       when is_binary(asin) and asin != "",
       do: where(query, [b], b.amazon_asin == ^asin)

  defp maybe_filter_by_amazon_asin(query, _), do: query

  defp maybe_filter_by_title_author(query, attrs) do
    title = get_string_attr(attrs, :title) || get_string_attr(attrs, "title")
    author = get_string_attr(attrs, :author) || get_string_attr(attrs, "author")

    case {title, author} do
      {title, author} when is_binary(title) and is_binary(author) ->
        where(query, [b], b.title == ^title and b.author == ^author)

      _ ->
        query
    end
  end

  defp get_string_attr(attrs, key) do
    case Map.get(attrs, key) do
      str when is_binary(str) and str != "" -> str
      _ -> nil
    end
  end

  @doc """
  Gets a book by ISBN (either ISBN-10 or ISBN-13).

  ## Examples

      iex> get_book_by_isbn("9781234567890")
      %Book{}

      iex> get_book_by_isbn("nonexistent")
      nil

  """
  def get_book_by_isbn(isbn) when is_binary(isbn) do
    from(b in Book)
    |> where([b], b.isbn13 == ^isbn or b.isbn10 == ^isbn)
    |> Repo.one()
  end

  @doc """
  Gets a book by its Amazon ASIN.

  ## Examples

      iex> get_book_by_asin("B01234567X")
      %Book{}

      iex> get_book_by_asin("nonexistent")
      nil

  """
  def get_book_by_asin(asin) when is_binary(asin) do
    from(b in Book)
    |> where([b], b.amazon_asin == ^asin)
    |> Repo.one()
  end

  @doc """
  Finds a book by title and author combination.

  Uses normalized title matching to handle common postfixes like "(Unabridged)",
  "(Paperback)", etc. that don't affect the core title.

  ## Examples

      iex> find_book_by_title_and_author("The Great Book", "Famous Author")
      %Book{}

      iex> find_book_by_title_and_author("The Martian (Unabridged)", "Andy Weir")
      %Book{title: "The Martian"}

      iex> find_book_by_title_and_author("Nonexistent", "No Author")
      nil

  """
  def find_book_by_title_and_author(title, author) when is_binary(title) and is_binary(author) do
    normalized_title = TitleUtils.normalize_title(title)

    # First try exact match for performance
    case from(b in Book)
         |> where([b], b.title == ^title and b.author == ^author)
         |> Repo.one() do
      nil ->
        # Fallback to normalized title matching
        from(b in Book)
        |> where([b], b.author == ^author)
        |> Repo.all()
        |> Enum.find(fn book -> TitleUtils.normalize_title(book.title) == normalized_title end)

      book ->
        book
    end
  end
end
