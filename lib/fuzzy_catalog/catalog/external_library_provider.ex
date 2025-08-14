defmodule FuzzyCatalog.Catalog.ExternalLibraryProvider do
  @moduledoc """
  Behaviour for external library providers that synchronize books.

  External libraries (like Audiobookshelf, Calibre) can implement this behavior
  to synchronize their book collections with the local database.
  """

  @type book_sync_data :: %{
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
          original_title: String.t() | nil,
          media_type: String.t(),
          external_id: String.t()
        }

  @type sync_result :: {:ok, [book_sync_data()]} | {:error, String.t()}
  @type stream_result :: {:ok, Enumerable.t()} | {:error, String.t()}

  @doc """
  Fetch all books from the external library.
  """
  @callback fetch_books() :: sync_result()

  @doc """
  Stream books from the external library for efficient memory usage.
  Providers that don't implement this will fall back to fetch_books/0.
  """
  @callback stream_books() :: stream_result()

  @optional_callbacks stream_books: 0

  @doc """
  Provider name for logging and identification.
  """
  @callback provider_name() :: String.t()

  @doc """
  Check if the provider is properly configured and available.
  """
  @callback available?() :: boolean()
end
