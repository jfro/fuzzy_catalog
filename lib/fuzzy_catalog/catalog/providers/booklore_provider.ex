defmodule FuzzyCatalog.Catalog.Providers.BookLoreProvider do
  @moduledoc """
  BookLore external library provider implementation.

  Synchronizes ebooks from a BookLore instance using its REST API.
  BookLore is a self-hosted web application for organizing and managing personal book collections.
  """

  @behaviour FuzzyCatalog.Catalog.ExternalLibraryProvider

  require Logger
  alias FuzzyCatalog.IsbnUtils

  @impl true
  def provider_name, do: "BookLore"

  @impl true
  def available? do
    config = Application.get_env(:fuzzy_catalog, :booklore, [])

    case {Keyword.get(config, :url), Keyword.get(config, :username),
          Keyword.get(config, :password)} do
      {url, username, password}
      when is_binary(url) and is_binary(username) and is_binary(password) and
             url != "" and username != "" and password != "" ->
        true

      _ ->
        false
    end
  end

  @impl true
  def fetch_books do
    case stream_books() do
      {:ok, book_stream} ->
        {:ok, Enum.to_list(book_stream)}

      error ->
        error
    end
  end

  @impl true
  def stream_books do
    case get_config() do
      {:ok, {base_url, username, password, library_filter}} ->
        case authenticate(base_url, username, password) do
          {:ok, access_token} ->
            case fetch_libraries(base_url, access_token) do
              {:ok, libraries} ->
                filtered_libraries = filter_libraries(libraries, library_filter)
                names = Enum.map(filtered_libraries, &Map.get(&1, "name"))

                Logger.debug(
                  "Filtered BookLore libraries: #{inspect(names)}, preparing book stream"
                )

                stream = create_books_stream(filtered_libraries, base_url, access_token)
                {:ok, stream}

              error ->
                error
            end

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the total count of books that will be synced from configured libraries.
  """
  def get_total_books_count do
    case get_config() do
      {:ok, {base_url, username, password, library_filter}} ->
        case authenticate(base_url, username, password) do
          {:ok, access_token} ->
            case fetch_libraries(base_url, access_token) do
              {:ok, libraries} ->
                filtered_libraries = filter_libraries(libraries, library_filter)

                total_count =
                  filtered_libraries
                  |> Enum.reduce(0, fn library, acc ->
                    case get_library_total_count(library["id"], base_url, access_token) do
                      {:ok, count} -> acc + count
                      {:error, _} -> acc
                    end
                  end)

                Logger.debug(
                  "Total books count across filtered BookLore libraries: #{total_count}"
                )

                {:ok, total_count}

              error ->
                error
            end

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_config do
    config = Application.get_env(:fuzzy_catalog, :booklore, [])

    case {Keyword.get(config, :url), Keyword.get(config, :username),
          Keyword.get(config, :password)} do
      {url, username, password}
      when is_binary(url) and is_binary(username) and is_binary(password) and
             url != "" and username != "" and password != "" ->
        base_url = String.trim_trailing(url, "/")
        libraries = parse_libraries_config(Keyword.get(config, :libraries))
        {:ok, {base_url, username, password, libraries}}

      _ ->
        {:error, "BookLore URL, username, and password must be configured"}
    end
  end

  defp parse_libraries_config(nil), do: :all
  defp parse_libraries_config(""), do: :all

  defp parse_libraries_config(libraries_str) when is_binary(libraries_str) do
    libraries_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp authenticate(base_url, username, password) do
    url = "#{base_url}/api/v1/auth/login"

    body = %{
      username: username,
      password: password
    }

    Logger.debug("Authenticating with BookLore at #{url}")

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: %{"accessToken" => access_token}}} ->
        Logger.debug("Successfully authenticated with BookLore")
        {:ok, access_token}

      {:ok, %{status: 401, body: body}} ->
        Logger.error("Authentication failed: Invalid credentials - #{inspect(body)}")
        {:error, "Authentication failed: Invalid credentials"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Authentication failed: HTTP #{status} - #{inspect(body)}")
        {:error, "Authentication failed: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Authentication request failed: #{inspect(exception)}")
        {:error, "Authentication request failed: #{inspect(exception)}"}
    end
  end

  defp fetch_libraries(base_url, access_token) do
    url = "#{base_url}/api/v1/libraries"
    headers = [{"Authorization", "Bearer #{access_token}"}]

    Logger.debug("Fetching BookLore libraries from #{url}")

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: libraries}} when is_list(libraries) ->
        {:ok, libraries}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch libraries: HTTP #{status} - #{inspect(body)}")
        {:error, "Failed to fetch libraries: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end

  defp filter_libraries(libraries, :all), do: libraries

  defp filter_libraries(libraries, library_names) when is_list(library_names) do
    Enum.filter(libraries, fn library ->
      library["name"] in library_names or to_string(library["id"]) in library_names
    end)
  end

  defp create_books_stream(libraries, base_url, access_token) do
    libraries
    |> Stream.flat_map(fn library ->
      create_library_books_stream(library, base_url, access_token)
    end)
  end

  defp create_library_books_stream(library, base_url, access_token) do
    library_id = library["id"]

    Logger.debug("Creating stream for BookLore library #{library["name"]}")

    # Pass the access token and base URL for cover URL construction
    stream_library_books(library_id, base_url, access_token)
    |> Stream.map(&transform_book_to_sync_data(&1, base_url, access_token))
    |> Stream.filter(& &1)
  rescue
    error ->
      Logger.error("Failed to create library books stream: #{inspect(error)}")
      []
  end

  defp stream_library_books(library_id, base_url, access_token) do
    Stream.resource(
      fn -> {0, nil, false} end,
      fn
        {_page, _total, true} ->
          {:halt, nil}

        {page, total, false} ->
          case fetch_books_page(library_id, base_url, access_token, page) do
            {:ok, books, response_total} ->
              new_total = total || response_total
              fetched_so_far = (page + 1) * 1000
              is_done = fetched_so_far >= new_total or length(books) < 1000

              if is_done do
                Logger.debug("Completed fetching all books from BookLore library")
              else
                Logger.debug(
                  "Fetched page #{page}, continuing to page #{page + 1} (#{fetched_so_far}/#{new_total} books)"
                )
              end

              {books, {page + 1, new_total, is_done}}

            {:error, reason} ->
              throw({:fetch_error, reason})
          end
      end,
      fn _ -> :ok end
    )
  end

  defp fetch_books_page(library_id, base_url, access_token, page) do
    url = "#{base_url}/api/v1/libraries/#{library_id}/book"
    headers = [{"Authorization", "Bearer #{access_token}"}]
    # BookLore uses limit/page query params
    params = [limit: 1000, page: page]

    Logger.debug("Fetching BookLore books page #{page} from #{url}")

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: books}} when is_list(books) ->
        # BookLore doesn't provide total count in paginated response, so we estimate
        # by checking if we got a full page
        estimated_total =
          if length(books) == 1000, do: (page + 1) * 1000 + 1, else: page * 1000 + length(books)

        Logger.debug("Fetched page #{page}: #{length(books)} books")
        {:ok, books, estimated_total}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("Unexpected response structure: #{inspect(body)}")
        {:error, "Unexpected response structure: expected a list of books"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch library books: HTTP #{status} - #{inspect(body)}")
        {:error, "Failed to fetch library books: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end

  defp get_library_total_count(library_id, base_url, access_token) do
    url = "#{base_url}/api/v1/libraries/#{library_id}/book"
    headers = [{"Authorization", "Bearer #{access_token}"}]
    # Fetch all books to get accurate total count (BookLore frontend approach)

    Logger.debug("Fetching total count for BookLore library #{library_id}")

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: books}} when is_list(books) ->
        total_count = length(books)
        Logger.debug("BookLore library #{library_id} contains #{total_count} books")
        {:ok, total_count}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("Unexpected response structure: #{inspect(body)}")
        {:error, "Unexpected response structure: expected books list"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch library total: HTTP #{status} - #{inspect(body)}")
        {:error, "Failed to fetch library total: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end

  defp transform_book_to_sync_data(book, base_url, access_token) do
    with %{} <- book,
         metadata when is_map(metadata) <- Map.get(book, "metadata") do
      # Debug logging to see actual BookLore metadata structure
      Logger.debug(
        "BookLore metadata for '#{metadata["title"] || "Unknown"}': #{inspect(metadata, pretty: true)}"
      )

      # Get cover URL with authentication
      cover_url = build_cover_url(book, base_url, access_token)

      Logger.debug(
        "BookLore cover URL for '#{metadata["title"] || "Unknown"}': #{cover_url || "nil"}"
      )

      # Parse publication date
      publication_date = parse_publication_date(metadata["publishedDate"])

      # Extract series information
      {series_name, series_number} = extract_series_info(metadata)

      # Parse ISBN/ASIN data
      {isbn10, isbn13, asin} = parse_isbn_asin_data(metadata)

      %{
        title: metadata["title"] || "Unknown Title",
        author: format_authors(metadata["authors"] || []),
        isbn10: isbn10,
        isbn13: isbn13,
        asin: asin,
        publisher: metadata["publisher"],
        publication_date: publication_date,
        pages: metadata["pageCount"],
        cover_url: cover_url,
        subtitle: metadata["subtitle"],
        description: metadata["description"],
        genre: format_genres(metadata["categories"] || []),
        series: series_name,
        series_number: series_number,
        original_title: nil,
        media_type: "ebook",
        external_id: to_string(book["id"]),
        provider: "BookLore"
      }
    else
      _ ->
        Logger.warning("Skipping invalid BookLore book structure: #{inspect(book)}")
        nil
    end
  end

  defp build_cover_url(book, base_url, access_token) do
    # BookLore uses /api/v1/media/book/{bookId}/thumbnail endpoint for covers
    # Format: /api/v1/media/book/{bookId}/thumbnail?{timestamp}&token={jwt}
    book_id = book["id"]

    if book_id do
      # Generate timestamp for cache busting (RFC3339 format like the frontend)
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

      # Build the cover URL with query parameters
      cover_url =
        "#{base_url}/api/v1/media/book/#{book_id}/thumbnail?#{timestamp}=&token=#{access_token}"

      cover_url
    else
      nil
    end
  end

  defp parse_publication_date(nil), do: nil
  defp parse_publication_date(""), do: nil

  defp parse_publication_date(date_str) when is_binary(date_str) do
    # BookLore stores dates in various formats, use centralized date utils
    FuzzyCatalog.DateUtils.parse_flexible_date_input(date_str)
  end

  defp parse_publication_date(_), do: nil

  defp extract_series_info(metadata) do
    series_name = metadata["seriesName"]
    series_number = metadata["seriesNumber"]

    if series_name && series_name != "" do
      parsed_number = parse_series_number(series_number)
      {series_name, parsed_number}
    else
      {nil, nil}
    end
  end

  defp parse_series_number(nil), do: nil
  defp parse_series_number(""), do: nil
  defp parse_series_number(num) when is_number(num), do: Decimal.from_float(num)

  defp parse_series_number(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} -> Decimal.from_float(num)
      :error -> nil
    end
  end

  defp parse_series_number(_), do: nil

  defp format_authors([]), do: "Unknown Author"

  defp format_authors(authors) when is_list(authors) do
    authors
    |> Enum.reject(&(&1 == "" || is_nil(&1)))
    |> case do
      [] -> "Unknown Author"
      author_list -> Enum.join(author_list, ", ")
    end
  end

  defp format_authors(_), do: "Unknown Author"

  defp format_genres([]), do: nil

  defp format_genres(genres) when is_list(genres) do
    genres
    |> Enum.take(3)
    |> Enum.join(", ")
  end

  defp format_genres(_), do: nil

  defp parse_isbn_asin_data(metadata) do
    # Use the centralized ISBN utils to parse identifiers
    data = %{
      "isbn10" => metadata["isbn10"],
      "isbn13" => metadata["isbn13"],
      "asin" => metadata["asin"]
    }

    IsbnUtils.parse_identifiers(data)
  end
end
