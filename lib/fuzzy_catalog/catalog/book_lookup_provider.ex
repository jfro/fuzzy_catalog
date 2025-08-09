defmodule FuzzyCatalog.Catalog.BookLookupProvider do
  @moduledoc """
  Behaviour for book lookup providers.

  Each provider must implement the callbacks defined here to be used
  by the BookLookup service.
  """

  @type book_data :: %{
          title: String.t(),
          author: String.t(),
          isbn10: String.t() | nil,
          isbn13: String.t() | nil,
          publisher: String.t() | nil,
          publication_date: Date.t() | nil,
          pages: integer() | nil,
          cover_url: String.t() | nil,
          subtitle: String.t() | nil,
          description: String.t() | nil,
          genre: String.t() | nil,
          series: String.t() | nil,
          series_number: integer() | nil,
          original_title: String.t() | nil
        }

  @type lookup_result :: {:ok, book_data()} | {:error, String.t()}
  @type search_result :: {:ok, [book_data()]} | {:error, String.t()}

  @doc """
  Look up a book by ISBN.
  """
  @callback lookup_by_isbn(isbn :: String.t()) :: lookup_result()

  @doc """
  Search for books by title.
  """
  @callback lookup_by_title(title :: String.t()) :: search_result()

  @doc """
  Look up a book by UPC/barcode.
  Optional - providers can return {:error, "Not supported"} if not implemented.
  """
  @callback lookup_by_upc(upc :: String.t()) :: search_result()

  @doc """
  Provider name for logging and identification.
  """
  @callback provider_name() :: String.t()
end
