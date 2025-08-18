defmodule FuzzyCatalog.Catalog.Providers.OpenLibraryProvider do
  @moduledoc """
  OpenLibrary API provider for book lookups.
  """

  @behaviour FuzzyCatalog.Catalog.BookLookupProvider

  require Logger
  alias FuzzyCatalog.Catalog.BookLookupProvider

  @base_url "https://openlibrary.org"
  @search_api_url "#{@base_url}/search.json"
  @covers_api_url "https://covers.openlibrary.org"

  @impl BookLookupProvider
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    case validate_isbn(clean_isbn) do
      :valid ->
        url =
          "#{@search_api_url}?isbn=#{clean_isbn}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject,format,editions&limit=1"

        case make_request(url) do
          {:ok, response} ->
            parse_isbn_search_response(response)

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
          "#{@search_api_url}?title=#{encoded_title}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject,format&limit=10"

        case make_request(url) do
          {:ok, response} ->
            parse_search_response(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl BookLookupProvider
  def lookup_by_upc(upc) when is_binary(upc) do
    clean_upc = String.replace(upc, ~r/[^0-9]/, "")

    if String.length(clean_upc) == 12 do
      url =
        "#{@search_api_url}?q=#{clean_upc}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject,format&limit=5"

      case make_request(url) do
        {:ok, response} ->
          parse_search_response(response)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "Invalid UPC format (must be 12 digits)"}
    end
  end

  @impl BookLookupProvider
  def provider_name, do: "OpenLibrary"

  # Private functions

  defp map_format_to_media_type(format) when is_binary(format) do
    format_lower = String.downcase(String.trim(format))

    cond do
      String.contains?(format_lower, "hardcover") or String.contains?(format_lower, "hardback") ->
        "hardcover"

      String.contains?(format_lower, "paperback") or String.contains?(format_lower, "softcover") ->
        "paperback"

      String.contains?(format_lower, "audiobook") or String.contains?(format_lower, "audio") or
        String.contains?(format_lower, "mp3") or String.contains?(format_lower, "cd") ->
        "audiobook"

      String.contains?(format_lower, "ebook") or String.contains?(format_lower, "e-book") or
        String.contains?(format_lower, "digital") or String.contains?(format_lower, "epub") or
          String.contains?(format_lower, "kindle") ->
        "ebook"

      true ->
        nil
    end
  end

  defp map_format_to_media_type(_), do: nil

  defp extract_media_types_from_formats(nil), do: []
  defp extract_media_types_from_formats([]), do: []

  defp extract_media_types_from_formats(formats) when is_list(formats) do
    formats
    |> Enum.map(&map_format_to_media_type/1)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end

  defp extract_formats_from_editions(nil), do: []
  defp extract_formats_from_editions(%{"docs" => []}), do: []

  defp extract_formats_from_editions(%{"docs" => editions}) when is_list(editions) do
    editions
    |> Enum.flat_map(fn edition ->
      case edition["format"] do
        format when is_binary(format) -> [format]
        formats when is_list(formats) -> formats
        _ -> []
      end
    end)
    |> Enum.map(&map_format_to_media_type/1)
    |> Enum.filter(& &1)
    |> Enum.uniq()
  end

  defp extract_formats_from_editions(_), do: []

  defp make_request(url) do
    Logger.info("OpenLibrary: Making request to: #{url}")

    case Req.get(url, headers: [{"User-Agent", "FuzzyCatalog/1.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("OpenLibrary: Request failed: #{inspect(reason)}")
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

  defp parse_search_response(%{"docs" => docs, "num_found" => num_found}) when num_found > 0 do
    books = Enum.map(docs, &normalize_search_result/1)
    {:ok, books}
  end

  defp parse_search_response(%{"num_found" => 0}) do
    {:error, "No books found"}
  end

  defp parse_search_response(_) do
    {:error, "Invalid response format"}
  end

  defp parse_isbn_search_response(%{"docs" => [doc | _], "num_found" => num_found})
       when num_found > 0 do
    book_data = normalize_isbn_search_result(doc)
    {:ok, book_data}
  end

  defp parse_isbn_search_response(%{"num_found" => 0}) do
    {:error, "Book not found"}
  end

  defp parse_isbn_search_response(_) do
    {:error, "Invalid response format"}
  end

  defp normalize_search_result(doc) do
    isbn10 = extract_isbn_from_list(doc["isbn"], 10)
    isbn13 = extract_isbn_from_list(doc["isbn"], 13)

    %{
      title: doc["title"] || "Unknown Title",
      author: extract_author_names(doc["author_name"]),
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: List.first(doc["publisher"] || []),
      publication_date: extract_search_publish_date(doc),
      key: doc["key"],
      cover_url: generate_cover_url(isbn13 || isbn10),
      # New fields from search results
      subtitle: doc["subtitle"],
      genre: extract_search_subjects(doc["subject"]),
      suggested_media_types: extract_media_types_from_formats(doc["format"])
    }
  end

  defp normalize_isbn_search_result(doc) do
    isbn10 = extract_isbn_from_list(doc["isbn"], 10)
    isbn13 = extract_isbn_from_list(doc["isbn"], 13)

    # Extract format from editions if available
    edition_formats = extract_formats_from_editions(doc["editions"])

    %{
      title: doc["title"] || "Unknown Title",
      author: extract_author_names(doc["author_name"]),
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: List.first(doc["publisher"] || []),
      publication_date: extract_search_publish_date(doc),
      key: doc["key"],
      cover_url: generate_cover_url(isbn13 || isbn10),
      # New fields from search results
      subtitle: doc["subtitle"],
      genre: extract_search_subjects(doc["subject"]),
      suggested_media_types: edition_formats
    }
  end

  defp generate_cover_url(nil), do: nil
  defp generate_cover_url(""), do: nil

  defp generate_cover_url(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")
    "#{@covers_api_url}/b/isbn/#{clean_isbn}-M.jpg"
  end

  defp extract_author_names(nil), do: "Unknown Author"
  defp extract_author_names([]), do: "Unknown Author"

  defp extract_author_names(names) when is_list(names) do
    Enum.join(names, ", ")
  end

  defp extract_isbn_from_list(nil, _length), do: nil
  defp extract_isbn_from_list([], _length), do: nil

  defp extract_isbn_from_list(isbns, length) when is_list(isbns) do
    Enum.find(isbns, fn isbn ->
      String.length(String.replace(isbn, ~r/[^0-9X]/, "")) == length
    end)
  end

  defp extract_publish_date(date) do
    FuzzyCatalog.DateUtils.parse_date(date)
  end

  defp extract_search_publish_date(doc) do
    # Try publish_date first, fallback to first_publish_year
    case doc["publish_date"] do
      dates when is_list(dates) and length(dates) > 0 ->
        extract_publish_date(List.first(dates))

      date when is_binary(date) ->
        extract_publish_date(date)

      _ ->
        case doc["first_publish_year"] do
          year when is_integer(year) -> FuzzyCatalog.DateUtils.parse_date(year)
          _ -> nil
        end
    end
  end

  defp extract_search_subjects(nil), do: nil
  defp extract_search_subjects([]), do: nil

  defp extract_search_subjects(subjects) when is_list(subjects) do
    subjects
    # Limit to first 3 subjects
    |> Enum.take(3)
    |> Enum.join(", ")
  end
end
