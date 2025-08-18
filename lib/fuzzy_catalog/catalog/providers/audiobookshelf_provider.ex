defmodule FuzzyCatalog.Catalog.Providers.AudiobookshelfProvider do
  @moduledoc """
  Audiobookshelf external library provider implementation.

  Synchronizes audiobooks from an Audiobookshelf instance using its REST API.
  """

  @behaviour FuzzyCatalog.Catalog.ExternalLibraryProvider

  require Logger
  alias FuzzyCatalog.IsbnUtils

  @impl true
  def provider_name, do: "Audiobookshelf"

  @impl true
  def available? do
    config = Application.get_env(:fuzzy_catalog, :audiobookshelf, [])

    case {Keyword.get(config, :url), Keyword.get(config, :api_key)} do
      {url, api_key} when is_binary(url) and is_binary(api_key) and url != "" and api_key != "" ->
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
      {:ok, {base_url, api_key, library_filter}} ->
        case fetch_libraries(base_url, api_key) do
          {:ok, libraries} ->
            filtered_libraries = filter_libraries(libraries, library_filter)
            names = Enum.map(filtered_libraries, &Map.get(&1, "name"))
            Logger.debug("Filtered libraries: #{inspect(names)}, preparing book stream")

            stream = create_books_stream(filtered_libraries, base_url, api_key)
            {:ok, stream}

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
      {:ok, {base_url, api_key, library_filter}} ->
        case fetch_libraries(base_url, api_key) do
          {:ok, libraries} ->
            filtered_libraries = filter_libraries(libraries, library_filter)

            total_count =
              filtered_libraries
              |> Enum.reduce(0, fn library, acc ->
                case get_library_total_count(library["id"], base_url, api_key) do
                  {:ok, count} -> acc + count
                  {:error, _} -> acc
                end
              end)

            Logger.debug("Total books count across filtered libraries: #{total_count}")
            {:ok, total_count}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_config do
    config = Application.get_env(:fuzzy_catalog, :audiobookshelf, [])

    case {Keyword.get(config, :url), Keyword.get(config, :api_key)} do
      {url, api_key} when is_binary(url) and is_binary(api_key) and url != "" and api_key != "" ->
        base_url = String.trim_trailing(url, "/")
        libraries = parse_libraries_config(Keyword.get(config, :libraries))
        {:ok, {base_url, api_key, libraries}}

      _ ->
        {:error, "Audiobookshelf URL and API key must be configured"}
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

  defp fetch_libraries(base_url, api_key) do
    url = "#{base_url}/api/libraries"
    headers = [{"Authorization", "Bearer #{api_key}"}]

    Logger.debug("Fetching Audiobookshelf libraries from #{url}")

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"libraries" => libraries}}} ->
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
      library["name"] in library_names or library["id"] in library_names
    end)
  end

  defp create_books_stream(libraries, base_url, api_key) do
    libraries
    |> Stream.flat_map(fn library ->
      create_library_items_stream(library, base_url, api_key)
    end)
  end

  defp create_library_items_stream(library, base_url, api_key) do
    library_id = library["id"]
    library_media_type = library["mediaType"]

    Logger.debug(
      "Creating stream for library #{library["name"]} (mediaType: #{library_media_type})"
    )

    stream_library_items(library_id, base_url, api_key)
    |> Stream.map(&transform_item_to_book(&1, library_media_type))
    |> Stream.filter(& &1)
  rescue
    error ->
      Logger.error("Failed to create library items stream: #{inspect(error)}")
      []
  end

  defp stream_library_items(library_id, base_url, api_key) do
    Stream.resource(
      fn -> {0, nil, false} end,
      fn
        {_page, _total, true} ->
          {:halt, nil}

        {page, total, false} ->
          case fetch_page(library_id, base_url, api_key, page) do
            {:ok, items, response_total} ->
              new_total = total || response_total
              fetched_so_far = (page + 1) * 1000
              is_done = fetched_so_far >= new_total or length(items) < 1000

              if is_done do
                Logger.debug("Completed fetching all items from library")
              else
                Logger.debug(
                  "Fetched page #{page}, continuing to page #{page + 1} (#{fetched_so_far}/#{new_total} items)"
                )
              end

              {items, {page + 1, new_total, is_done}}

            {:error, reason} ->
              throw({:fetch_error, reason})
          end
      end,
      fn _ -> :ok end
    )
  end

  defp fetch_page(library_id, base_url, api_key, page) do
    url = "#{base_url}/api/libraries/#{library_id}/items"
    headers = [{"Authorization", "Bearer #{api_key}"}]
    params = [limit: 1000, page: page]

    Logger.debug("Fetching library items page #{page} from #{url}")

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"results" => items, "total" => total}}} when is_list(items) ->
        Logger.debug("Fetched page #{page}: #{length(items)} items")
        {:ok, items, total}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("Unexpected response structure: #{inspect(body)}")
        {:error, "Unexpected response structure: expected results to be a list"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch library items: HTTP #{status} - #{inspect(body)}")
        {:error, "Failed to fetch library items: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end

  defp get_library_total_count(library_id, base_url, api_key) do
    url = "#{base_url}/api/libraries/#{library_id}/items"
    headers = [{"Authorization", "Bearer #{api_key}"}]
    # Just fetch the first page to get the total count
    params = [limit: 1, page: 0]

    Logger.debug("Fetching total count for library #{library_id}")

    case Req.get(url, headers: headers, params: params) do
      {:ok, %{status: 200, body: %{"total" => total}}} when is_integer(total) ->
        {:ok, total}

      {:ok, %{status: 200, body: body}} ->
        Logger.error("Unexpected response structure: #{inspect(body)}")
        {:error, "Unexpected response structure: missing total"}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch library total: HTTP #{status} - #{inspect(body)}")
        {:error, "Failed to fetch library total: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end

  defp transform_item_to_book(item, library_media_type) do
    with %{} <- item,
         media when is_map(media) <- Map.get(item, "media") do
      metadata = Map.get(media, "metadata", %{})

      # Get cover URL - Audiobookshelf provides cover path
      cover_url = build_cover_url(item)

      # Parse publication date using centralized DateUtils
      publication_date =
        FuzzyCatalog.DateUtils.parse_audiobookshelf_year(metadata["publishedYear"])

      # Parse series number
      series_number =
        case metadata["seriesSequence"] do
          sequence when is_binary(sequence) ->
            case Integer.parse(sequence) do
              {num, _} -> num
              :error -> nil
            end

          sequence when is_integer(sequence) ->
            sequence

          _ ->
            nil
        end

      # Separate ISBN and ASIN data properly
      {isbn10, isbn13, asin} = parse_isbn_asin_data(metadata)

      %{
        title: metadata["title"] || "Unknown Title",
        author: metadata["authorName"] || "Unknown Author",
        isbn10: isbn10,
        isbn13: isbn13,
        asin: asin,
        publisher: metadata["publisher"],
        publication_date: publication_date,
        pages: nil,
        cover_url: cover_url,
        subtitle: metadata["subtitle"],
        description: metadata["description"],
        genre: format_genres(metadata["genres"] || []),
        series: format_series(metadata["series"] || []),
        series_number: series_number,
        original_title: nil,
        media_type: map_audiobookshelf_media_type(library_media_type),
        external_id: item["id"]
      }
    else
      _ ->
        Logger.warning("Skipping invalid item structure: #{inspect(item)}")
        nil
    end
  end

  # Map Audiobookshelf media types to our collection item media types
  # Most book libraries in ABS are audiobooks
  defp map_audiobookshelf_media_type("book"), do: "audiobook"
  defp map_audiobookshelf_media_type("ebook"), do: "ebook"
  # Map comics to ebook since we don't have a comic type
  defp map_audiobookshelf_media_type("comic"), do: "ebook"
  # Map podcasts to audiobook
  defp map_audiobookshelf_media_type("podcast"), do: "audiobook"
  defp map_audiobookshelf_media_type(_), do: "unspecified"

  defp build_cover_url(item) do
    case get_config() do
      {:ok, {base_url, _api_key, _library_filter}} ->
        # Audiobookshelf cover URL format: /api/items/{itemId}/cover
        if item["id"] do
          "#{base_url}/api/items/#{item["id"]}/cover"
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp format_genres([]), do: nil

  defp format_genres(genres) when is_list(genres) do
    genres
    |> Enum.take(3)
    |> Enum.join(", ")
  end

  defp format_genres(_), do: nil

  defp format_series([]), do: nil

  defp format_series(series) when is_list(series) do
    case Enum.find(series, fn s -> is_map(s) and Map.has_key?(s, "name") end) do
      %{"name" => name} -> name
      _ -> nil
    end
  end

  defp format_series(_), do: nil

  defp parse_isbn_asin_data(metadata) do
    # Use the centralized ISBN utils to parse identifiers
    data = %{
      "isbn10" => metadata["isbn"],
      # Audiobookshelf typically puts everything in the isbn field
      "isbn13" => nil,
      "asin" => metadata["asin"]
    }

    IsbnUtils.parse_identifiers(data)
  end
end
