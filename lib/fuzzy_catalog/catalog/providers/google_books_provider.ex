defmodule FuzzyCatalog.Catalog.Providers.GoogleBooksProvider do
  @moduledoc """
  Google Books API provider for book lookups.
  """

  @behaviour FuzzyCatalog.Catalog.BookLookupProvider

  require Logger
  alias FuzzyCatalog.Catalog.BookLookupProvider

  @google_books_url "https://www.googleapis.com/books/v1/volumes"

  @impl BookLookupProvider
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    case validate_isbn(clean_isbn) do
      :valid ->
        case lookup_google_books_full(clean_isbn) do
          {:ok, google_data} ->
            {:ok, google_data}

          {:error, reason} ->
            {:error, reason}
        end

      :invalid ->
        {:error, "Invalid ISBN format"}
    end
  end

  @impl BookLookupProvider
  def lookup_by_title(title) when is_binary(title) do
    case String.trim(title) do
      "" ->
        {:error, "Title cannot be empty"}

      clean_title ->
        encoded_title = URI.encode(clean_title)

        url =
          "#{@google_books_url}?q=intitle:#{encoded_title}&fields=items(volumeInfo(title,subtitle,authors,publisher,publishedDate,pageCount,categories,description,seriesInfo,industryIdentifiers,imageLinks))&maxResults=10"

        case make_request(url) do
          {:ok, response} ->
            parse_search_response(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl BookLookupProvider
  def lookup_by_upc(_upc) do
    {:error, "UPC lookup not supported by Google Books"}
  end

  @impl BookLookupProvider
  def provider_name, do: "Google Books"

  # Private functions

  defp make_request(url) do
    Logger.info("Google Books: Making request to: #{url}")

    case Req.get(url, headers: [{"User-Agent", "FuzzyCatalog/1.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Google Books: Request failed: #{inspect(reason)}")
        {:error, "Network error"}
    end
  end

  defp validate_isbn(isbn) do
    cond do
      String.length(isbn) == 10 and Regex.match?(~r/^[0-9]{9}[0-9X]$/, isbn) ->
        :valid

      String.length(isbn) == 13 and Regex.match?(~r/^[0-9]{13}$/, isbn) ->
        :valid

      true ->
        :invalid
    end
  end

  defp lookup_google_books_full(isbn) do
    url =
      "#{@google_books_url}?q=isbn:#{isbn}&fields=items(volumeInfo(title,subtitle,authors,publisher,publishedDate,pageCount,categories,description,seriesInfo,industryIdentifiers,imageLinks))"

    case make_request(url) do
      {:ok, response} ->
        parse_google_books_full(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_google_books_full(%{"items" => [item | _]}) do
    volume_info = item["volumeInfo"] || %{}
    {:ok, normalize_google_books_data(volume_info)}
  end

  defp parse_google_books_full(_), do: {:error, "No results"}

  defp parse_search_response(%{"items" => items}) when is_list(items) do
    books =
      Enum.map(items, fn item ->
        volume_info = item["volumeInfo"] || %{}
        normalize_google_books_data(volume_info)
      end)

    {:ok, books}
  end

  defp parse_search_response(_), do: {:error, "No results"}

  defp normalize_google_books_data(volume_info) do
    isbn_identifiers = volume_info["industryIdentifiers"] || []
    isbn10 = find_isbn(isbn_identifiers, "ISBN_10")
    isbn13 = find_isbn(isbn_identifiers, "ISBN_13")

    %{
      title: volume_info["title"] || "Unknown Title",
      subtitle: volume_info["subtitle"],
      author: extract_google_authors(volume_info["authors"]),
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: volume_info["publisher"],
      publication_date: parse_google_date(volume_info["publishedDate"]),
      pages: volume_info["pageCount"],
      genre: List.first(volume_info["categories"] || []),
      description: volume_info["description"],
      series: extract_google_series(volume_info["seriesInfo"]),
      cover_url: get_in(volume_info, ["imageLinks", "thumbnail"]),
      suggested_media_types: []
    }
  end

  defp find_isbn(identifiers, type) do
    case Enum.find(identifiers, fn id -> id["type"] == type end) do
      %{"identifier" => isbn} -> isbn
      _ -> nil
    end
  end

  defp extract_google_authors(nil), do: "Unknown Author"
  defp extract_google_authors([]), do: "Unknown Author"

  defp extract_google_authors(authors) when is_list(authors) do
    Enum.join(authors, ", ")
  end

  defp extract_google_series(nil), do: nil

  defp extract_google_series(%{"volumeSeries" => [%{"seriesId" => series_name} | _]})
       when is_binary(series_name) do
    series_name
  end

  defp extract_google_series(_), do: nil

  defp parse_google_date(nil), do: nil

  defp parse_google_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        date

      {:error, _} ->
        # Try to parse just the year
        case Regex.run(~r/\d{4}/, date_string) do
          [year] -> Date.new!(String.to_integer(year), 1, 1)
          _ -> nil
        end
    end
  end
end
