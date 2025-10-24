defmodule FuzzyCatalog.Catalog.Providers.HardcoverProvider do
  @moduledoc """
  Hardcover API provider for book lookups.

  Uses the Hardcover GraphQL API to retrieve book metadata.
  Requires an API token from https://hardcover.app/settings/api
  """

  @behaviour FuzzyCatalog.Catalog.BookLookupProvider

  require Logger
  alias FuzzyCatalog.Catalog.BookLookupProvider

  @hardcover_api_url "https://api.hardcover.app/v1/graphql"

  @impl BookLookupProvider
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    case validate_isbn(clean_isbn) do
      :valid ->
        query = build_isbn_query(clean_isbn)

        case make_graphql_request(query) do
          {:ok, response} ->
            parse_editions_response(response)

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
        query = build_search_query(clean_title, ["title", "alternative_titles"])

        case make_graphql_request(query) do
          {:ok, response} ->
            parse_search_response(response, :multiple)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl BookLookupProvider
  def lookup_by_upc(_upc) do
    {:error, "UPC lookup not supported by Hardcover"}
  end

  @impl BookLookupProvider
  def provider_name, do: "Hardcover"

  # Private functions

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

  defp build_isbn_query(isbn) do
    """
    {
      editions(where: {
        _or: [
          {isbn_10: {_eq: "#{escape_graphql_string(isbn)}"}},
          {isbn_13: {_eq: "#{escape_graphql_string(isbn)}"}}
        ]
      }, limit: 1) {
        id
        title
        subtitle
        edition_format
        isbn_10
        isbn_13
        pages
        release_date
        asin
        audio_seconds
        book {
          id
          title
          description
          cached_contributors
          book_series {
            series {
              name
            }
          }
          cached_tags
          cached_image
        }
      }
    }
    """
  end

  defp build_search_query(query_string, fields) do
    # Format fields as comma-separated string: "field1,field2"
    fields_str = Enum.join(fields, ",")

    # Format weights as comma-separated string: "5,5"
    weights_str =
      fields
      |> Enum.map(fn _ -> "5" end)
      |> Enum.join(",")

    """
    {
      search(
        query: "#{escape_graphql_string(query_string)}"
        query_type: "Book"
        per_page: 10
        page: 1
        fields: "#{fields_str}"
        weights: "#{weights_str}"
        sort: "_text_match:desc,users_count:desc"
      ) {
        results
      }
    }
    """
  end

  defp escape_graphql_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp make_graphql_request(query) do
    api_token = get_api_token()

    case api_token do
      nil ->
        {:error, "Not configured"}

      token ->
        Logger.info("Hardcover: Making GraphQL request")

        headers = [
          {"Content-Type", "application/json"},
          {"Authorization", "Bearer #{token}"},
          {"User-Agent", "FuzzyCatalog/1.0"}
        ]

        body = Jason.encode!(%{query: query})

        case Req.post(@hardcover_api_url, headers: headers, body: body) do
          {:ok, %{status: 200, body: response_body}} ->
            case response_body do
              %{"data" => data} ->
                Logger.debug("Hardcover: Response data: #{inspect(data)}")
                {:ok, response_body}

              %{"errors" => errors} ->
                Logger.error("Hardcover: GraphQL errors: #{inspect(errors)}")
                {:error, "GraphQL error: #{extract_error_message(errors)}"}

              _ ->
                Logger.error("Hardcover: Unexpected response body: #{inspect(response_body)}")
                {:error, "Invalid response format"}
            end

          {:ok, %{status: 401}} ->
            Logger.error("Hardcover: Authentication failed")
            {:error, "Authentication failed - check API token"}

          {:ok, %{status: 429}} ->
            Logger.warning("Hardcover: Rate limit exceeded")
            {:error, "Rate limit exceeded"}

          {:ok, %{status: status}} ->
            Logger.error("Hardcover: HTTP #{status}")
            {:error, "HTTP #{status}"}

          {:error, reason} ->
            Logger.error("Hardcover: Request failed: #{inspect(reason)}")
            {:error, "Network error"}
        end
    end
  end

  defp get_api_token do
    Application.get_env(:fuzzy_catalog, :hardcover_api_token) ||
      System.get_env("HARDCOVER_API_TOKEN")
  end

  defp extract_error_message([%{"message" => message} | _]), do: message
  defp extract_error_message(_), do: "Unknown error"

  defp parse_search_response(%{"data" => %{"search" => %{"results" => %{"hits" => hits}}}}, mode)
       when is_list(hits) do
    case hits do
      [] ->
        {:error, "No results found"}

      hit_results ->
        # Extract the "document" from each hit
        books_data = Enum.map(hit_results, fn %{"document" => doc} -> doc end)
        normalized_books = Enum.map(books_data, &normalize_hardcover_data/1)

        case mode do
          :single -> {:ok, List.first(normalized_books)}
          :multiple -> {:ok, normalized_books}
        end
    end
  end

  defp parse_search_response(response, _mode) do
    Logger.error("Hardcover: Unexpected response structure: #{inspect(response)}")
    {:error, "Invalid response format"}
  end

  defp parse_editions_response(%{"data" => %{"editions" => editions}}) when is_list(editions) do
    case editions do
      [] ->
        {:error, "No results found"}

      [edition | _] ->
        {:ok, normalize_edition_data(edition)}
    end
  end

  defp parse_editions_response(response) do
    Logger.error("Hardcover: Unexpected editions response structure: #{inspect(response)}")
    {:error, "Invalid response format"}
  end

  defp normalize_edition_data(edition) when is_map(edition) do
    book_data = edition["book"] || %{}

    # Extract edition format and map to media types
    edition_format = edition["edition_format"]
    media_types = map_edition_format_to_media_types(edition_format)

    # Extract book-level data from cached fields
    contributors = extract_from_cached(book_data["cached_contributors"])
    description = book_data["description"]
    book_series = book_data["book_series"] || []
    tags = extract_from_cached(book_data["cached_tags"])
    image = extract_from_cached(book_data["cached_image"])

    # Parse publication date
    publication_date = parse_date(edition["release_date"])

    %{
      title: edition["title"] || book_data["title"] || "Unknown Title",
      subtitle: edition["subtitle"],
      author: format_contributors(contributors),
      isbn10: edition["isbn_10"],
      isbn13: edition["isbn_13"],
      publisher: nil,
      publication_date: publication_date,
      pages: edition["pages"],
      genre: format_tags_as_genres(tags),
      description: description,
      series: format_book_series(book_series),
      series_number: nil,
      cover_url: extract_cover_url(image),
      suggested_media_types: media_types
    }
  end

  # Expose for testing
  if Mix.env() == :test do
    def __map_edition_format_to_media_types__(format),
      do: map_edition_format_to_media_types(format)

    def __extract_from_cached__(data), do: extract_from_cached(data)
    def __format_contributors__(contributors), do: format_contributors(contributors)
    def __format_genres__(genres), do: format_tags_as_genres(genres)
    def __format_series__(series), do: format_book_series(series)
  end

  defp map_edition_format_to_media_types(nil), do: []
  defp map_edition_format_to_media_types(""), do: []

  defp map_edition_format_to_media_types(format) when is_binary(format) do
    # Normalize format string (lowercase, trim)
    normalized = format |> String.downcase() |> String.trim()

    case normalized do
      # Direct matches
      "hardcover" ->
        ["hardcover"]

      "paperback" ->
        ["paperback"]

      "audiobook" ->
        ["audiobook"]

      "ebook" ->
        ["ebook"]

      "audio" ->
        ["audiobook"]

      "digital" ->
        ["ebook"]

      # Common variations
      "mass market paperback" ->
        ["paperback"]

      "trade paperback" ->
        ["paperback"]

      "board book" ->
        ["hardcover"]

      "library binding" ->
        ["hardcover"]

      # Kindle/digital formats
      format when format in ["kindle", "kindle edition"] ->
        ["ebook"]

      # Audio formats
      format when format in ["audio cd", "audio download", "mp3 cd"] ->
        ["audiobook"]

      # Unknown
      _ ->
        Logger.debug("Unknown Hardcover edition_format: #{format}")
        []
    end
  end

  defp extract_from_cached(nil), do: nil

  defp extract_from_cached(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, data} -> data
      {:error, _} -> nil
    end
  end

  defp extract_from_cached(data) when is_map(data) or is_list(data), do: data

  defp format_contributors(nil), do: "Unknown Author"
  defp format_contributors([]), do: "Unknown Author"

  defp format_contributors(contributors) when is_list(contributors) do
    contributors
    |> Enum.map(fn
      %{"author" => %{"name" => name}} -> name
      %{"name" => name} -> name
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "Unknown Author"
      names -> Enum.join(names, ", ")
    end
  end

  defp format_book_series(nil), do: nil
  defp format_book_series([]), do: nil

  defp format_book_series(book_series) when is_list(book_series) do
    # book_series is a list of %{"series" => %{"name" => "..."}}
    book_series
    |> Enum.map(fn
      %{"series" => %{"name" => name}} -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> List.first()
  end

  defp format_tags_as_genres(nil), do: nil
  defp format_tags_as_genres([]), do: nil

  defp format_tags_as_genres(tags) when is_map(tags) do
    # cached_tags is a map with genre/tag categories as keys
    # Try to extract genre-like tags from the structure
    tags
    |> Map.values()
    |> List.flatten()
    |> Enum.take(3)
    |> Enum.map(fn
      %{"tag" => tag} -> tag
      %{"name" => name} -> name
      tag when is_binary(tag) -> tag
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  defp format_tags_as_genres(tags) when is_list(tags) do
    tags
    |> Enum.take(3)
    |> Enum.map(fn
      %{"tag" => tag} -> tag
      %{"name" => name} -> name
      tag when is_binary(tag) -> tag
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    FuzzyCatalog.DateUtils.parse_date(date_str)
  end

  defp normalize_hardcover_data(book_data) when is_map(book_data) do
    # Extract ISBNs
    isbns = book_data["isbns"] || []
    isbn10 = Enum.find(isbns, fn isbn -> String.length(isbn) == 10 end)
    isbn13 = Enum.find(isbns, fn isbn -> String.length(isbn) == 13 end)

    # Extract authors
    author_names = book_data["author_names"] || []
    author = extract_authors(author_names)

    # Extract series
    series_names = book_data["series_names"] || []
    series = List.first(series_names)

    # Extract genres
    genres = book_data["genres"] || []
    genre = extract_genres(genres)

    # Parse publication year to date
    publication_date = parse_release_year(book_data["release_year"])

    # Extract cover image URL (if available)
    cover_url = extract_cover_url(book_data["image"]) || book_data["cover_url"]

    %{
      title: book_data["title"] || "Unknown Title",
      subtitle: book_data["subtitle"],
      author: author,
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: nil,
      publication_date: publication_date,
      pages: book_data["pages"],
      genre: genre,
      description: book_data["description"],
      series: series,
      series_number: nil,
      cover_url: cover_url,
      suggested_media_types: []
    }
  end

  defp extract_cover_url(nil), do: nil
  defp extract_cover_url(%{"url" => url}) when is_binary(url), do: url
  defp extract_cover_url(url) when is_binary(url), do: url
  defp extract_cover_url(_), do: nil

  defp extract_authors([]), do: "Unknown Author"
  defp extract_authors(nil), do: "Unknown Author"

  defp extract_authors(authors) when is_list(authors) do
    Enum.join(authors, ", ")
  end

  defp extract_genres([]), do: nil
  defp extract_genres(nil), do: nil

  defp extract_genres(genres) when is_list(genres) do
    genres
    |> Enum.take(3)
    |> Enum.join(", ")
  end

  defp parse_release_year(nil), do: nil

  defp parse_release_year(year) when is_integer(year) do
    FuzzyCatalog.DateUtils.parse_date(year)
  end

  defp parse_release_year(year_str) when is_binary(year_str) do
    case Integer.parse(year_str) do
      {year, _} -> FuzzyCatalog.DateUtils.parse_date(year)
      :error -> nil
    end
  end

  defp parse_release_year(_), do: nil
end
