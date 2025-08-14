defmodule FuzzyCatalog.Catalog.BookLookup do
  @moduledoc """
  Main book lookup service that coordinates multiple providers.

  This service uses a provider pattern to support multiple book data sources
  like OpenLibrary, Google Books, etc. Providers are tried in priority order
  and results can be enhanced by multiple providers.
  """

  require Logger
  alias FuzzyCatalog.Catalog.Providers.{OpenLibraryProvider, GoogleBooksProvider}

  @default_providers [
    OpenLibraryProvider
  ]

  @doc """
  Look up a book by ISBN (10 or 13 digit).

  Tries providers in priority order until a result is found.
  Then enhances the result with data from other providers.

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_isbn("0451526538")
      {:ok, %{title: "...", author: "...", ...}}
      
      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_isbn("invalid")
      {:error, "Invalid ISBN format"}
  """
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    try_providers_for_isbn(get_providers(), isbn)
  end

  @doc """
  Look up books by title.

  Uses the primary provider (lowest priority number) for search.
  Returns multiple results if found.

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_title("Lord of the Rings")
      {:ok, [%{title: "...", author: "...", ...}, ...]}
      
      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_title("")
      {:error, "Title cannot be empty"}
  """
  def lookup_by_title(title) when is_binary(title) do
    case get_providers() do
      [primary_provider | _] ->
        case primary_provider.lookup_by_title(title) do
          {:ok, books} when is_list(books) ->
            {:ok, Enum.map(books, &normalize_book_data/1)}
          
          result ->
            result
        end

      [] ->
        {:error, "No providers configured"}
    end
  end

  @doc """
  Look up book by UPC/barcode.

  Uses providers that support UPC lookup.
  """
  def lookup_by_upc(upc) when is_binary(upc) do
    providers_with_upc =
      Enum.filter(get_providers(), fn provider ->
        case provider.lookup_by_upc("000000000000") do
          {:error, "Not supported"} -> false
          {:error, "UPC lookup not supported" <> _} -> false
          _ -> true
        end
      end)

    case providers_with_upc do
      [] ->
        {:error, "UPC lookup not supported by any provider"}

      [provider | _] ->
        case provider.lookup_by_upc(upc) do
          {:ok, books} when is_list(books) ->
            {:ok, Enum.map(books, &normalize_book_data/1)}
          
          result ->
            result
        end
    end
  end

  @doc """
  Look up a book by ISBN using only Google Books API.

  This provides direct access to Google Books without trying other providers first.

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_isbn_google("9780451526538")
      {:ok, %{title: "...", author: "...", series: "..., ...}}
      
      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_isbn_google("invalid")
      {:error, "Invalid ISBN format"}
  """
  def lookup_by_isbn_google(isbn) when is_binary(isbn) do
    case GoogleBooksProvider.lookup_by_isbn(isbn) do
      {:ok, book_data} ->
        {:ok, normalize_book_data(book_data)}
      
      result ->
        result
    end
  end

  @doc """
  Generate cover URLs for different sizes using OpenLibrary.

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.cover_url("9780141439518", :small)
      "https://covers.openlibrary.org/b/isbn/9780141439518-S.jpg"
      
      iex> FuzzyCatalog.Catalog.BookLookup.cover_url("9780141439518", :medium)
      "https://covers.openlibrary.org/b/isbn/9780141439518-M.jpg"
  """
  def cover_url(nil, _size), do: nil
  def cover_url("", _size), do: nil

  def cover_url(isbn, size) when is_binary(isbn) and size in [:small, :medium, :large] do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    size_code =
      case size do
        :small -> "S"
        :medium -> "M"
        :large -> "L"
      end

    "https://covers.openlibrary.org/b/isbn/#{clean_isbn}-#{size_code}.jpg"
  end

  @doc """
  Get list of available providers with their information.
  """
  def providers do
    get_providers()
    |> Enum.with_index(1)
    |> Enum.map(fn {provider, index} ->
      %{
        name: provider.provider_name(),
        order: index,
        module: provider
      }
    end)
  end

  # Private functions

  defp get_providers do
    Application.get_env(:fuzzy_catalog, :book_lookup, [])
    |> Keyword.get(:providers, @default_providers)
  end

  defp try_providers_for_isbn([], _isbn) do
    {:error, "No providers available"}
  end

  defp try_providers_for_isbn([provider | remaining_providers], isbn) do
    Logger.info("Trying provider: #{provider.provider_name()}")

    case provider.lookup_by_isbn(isbn) do
      {:ok, book_data} ->
        Logger.info("Success with provider: #{provider.provider_name()}")
        {:ok, normalize_book_data(book_data)}

      {:error, reason} ->
        Logger.info("Failed with provider #{provider.provider_name()}: #{reason}")
        try_providers_for_isbn(remaining_providers, isbn)
    end
  end

  defp normalize_book_data(book_data) when is_map(book_data) do
    book_data
    |> normalize_pages()
    |> normalize_series_number()
    |> normalize_cover_url()
  end

  defp normalize_pages(%{pages: 0} = book_data), do: %{book_data | pages: nil}
  defp normalize_pages(book_data), do: book_data

  defp normalize_series_number(%{series_number: 0} = book_data), do: %{book_data | series_number: nil}
  defp normalize_series_number(book_data), do: book_data

  defp normalize_cover_url(%{cover_url: nil} = book_data) do
    # Try to generate OpenLibrary cover URL as fallback
    isbn = book_data[:isbn13] || book_data[:isbn10]
    
    case isbn do
      nil -> book_data
      isbn_value -> %{book_data | cover_url: cover_url(isbn_value, :medium)}
    end
  end
  
  defp normalize_cover_url(book_data), do: book_data
end
