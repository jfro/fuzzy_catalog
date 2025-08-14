defmodule FuzzyCatalog.Catalog.Providers.AudiobookshelfProvider do
  @moduledoc """
  Audiobookshelf external library provider implementation.

  Synchronizes audiobooks from an Audiobookshelf instance using its REST API.
  """

  @behaviour FuzzyCatalog.Catalog.ExternalLibraryProvider

  require Logger

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

  defp transform_item_to_book(item, library_media_type) do
    # Add debug logging to understand the structure
    if not is_map(item) do
      Logger.error("Expected item to be a map but got: #{inspect(item)}")
      # Return a minimal book structure to avoid crashing
      %{
        title: "Invalid Item",
        author: "Unknown",
        isbn10: nil,
        isbn13: nil,
        publisher: nil,
        publication_date: nil,
        pages: nil,
        cover_url: nil,
        subtitle: nil,
        description: "Item structure was invalid: #{inspect(item)}",
        genre: nil,
        series: nil,
        series_number: nil,
        original_title: nil,
        media_type: map_audiobookshelf_media_type(library_media_type),
        external_id: "invalid-#{:os.system_time(:millisecond)}"
      }
    else
      media = Map.get(item, "media")

      if not is_map(media) do
        Logger.error(
          "Expected media to be a map but got: #{inspect(media)} for item: #{inspect(item)}"
        )

        # Return a minimal book structure
        %{
          title: Map.get(item, "name", "Unknown Title"),
          author: "Unknown",
          isbn10: nil,
          isbn13: nil,
          publisher: nil,
          publication_date: nil,
          pages: nil,
          cover_url: build_cover_url(item),
          subtitle: nil,
          description: "Media structure was invalid",
          genre: nil,
          series: nil,
          series_number: nil,
          original_title: nil,
          media_type: map_audiobookshelf_media_type(library_media_type),
          external_id: Map.get(item, "id", "unknown-#{:os.system_time(:millisecond)}")
        }
      else
        metadata = Map.get(media, "metadata", %{})

        # Get cover URL - Audiobookshelf provides cover path
        cover_url = build_cover_url(item)

        # Parse publication date
        publication_date =
          case metadata["publishedYear"] do
            year when is_integer(year) and year > 0 ->
              Date.new(year, 1, 1)
              |> case do
                {:ok, date} -> date
                _ -> nil
              end

            _ ->
              nil
          end

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

        %{
          title: metadata["title"] || "Unknown Title",
          author: metadata["authorName"] || "Unknown Author",
          isbn10: metadata["isbn"],
          isbn13: metadata["asin"],
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
      end
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
end
