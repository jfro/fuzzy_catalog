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
          "#{@search_api_url}?isbn=#{clean_isbn}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject,format,editions,series,series_name,number_of_pages,notes,work_titles,alternative_title,edition_notes,lcc,ddc,number_of_pages_median&limit=1"

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
          "#{@search_api_url}?title=#{encoded_title}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject,format,series,series_name,number_of_pages,notes,work_titles,alternative_title,edition_notes,lcc,ddc,number_of_pages_median&limit=10"

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
        "#{@search_api_url}?q=#{clean_upc}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject,format,series,series_name,number_of_pages,notes,work_titles,alternative_title,edition_notes,lcc,ddc,number_of_pages_median&limit=5"

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

  # Fetch edition data from OpenLibrary edition endpoint
  defp fetch_edition_data(edition_key) when is_binary(edition_key) do
    # Edition key comes in format "/books/OL49030283M" or "OL49030283M"
    clean_key = String.trim_leading(edition_key, "/")
    edition_url = "#{@base_url}/#{clean_key}.json"

    Logger.debug("Fetching OpenLibrary edition data from: #{edition_url}")

    case make_request(edition_url) do
      {:ok, edition_data} ->
        Logger.debug("OpenLibrary edition response: #{inspect(edition_data, pretty: true)}")
        {:ok, edition_data}

      {:error, reason} ->
        Logger.warning("Failed to fetch OpenLibrary edition data for #{edition_key}: #{reason}")
        {:error, reason}
    end
  end

  # Extract series data from edition JSON response
  defp extract_series_from_edition(edition_data) when is_map(edition_data) do
    # Edition JSON can have series data in multiple formats
    series_candidates = [
      edition_data["series"],
      edition_data["notes"],
      edition_data["description"],
      edition_data["subtitle"]
    ]

    # Try to find series info in any field
    result =
      Enum.find_value(series_candidates, {nil, nil}, fn candidate ->
        case extract_series_from_edition_field(candidate) do
          {nil, nil} -> false
          series_data -> series_data
        end
      end)

    case result do
      {series_name, series_number} when series_name != nil ->
        Logger.debug(
          "OpenLibrary edition series extracted: '#{series_name}' ##{inspect(series_number)}"
        )

        result

      _ ->
        Logger.debug("No series data found in edition JSON")
        {nil, nil}
    end
  rescue
    error ->
      Logger.warning("Error extracting series from edition data: #{inspect(error)}")
      {nil, nil}
  end

  defp extract_series_from_edition(_), do: {nil, nil}

  # Extract series from individual edition fields
  defp extract_series_from_edition_field(nil), do: {nil, nil}
  defp extract_series_from_edition_field(""), do: {nil, nil}
  defp extract_series_from_edition_field([]), do: {nil, nil}

  # Handle series as array (common format in edition JSON)
  defp extract_series_from_edition_field(series_list) when is_list(series_list) do
    case Enum.find(series_list, fn item ->
           is_binary(item) and String.trim(item) != ""
         end) do
      nil -> {nil, nil}
      series_string -> parse_series_with_number(String.trim(series_string))
    end
  end

  # Handle series as string
  defp extract_series_from_edition_field(field_value) when is_binary(field_value) do
    trimmed = String.trim(field_value)

    # First try direct series parsing
    case parse_series_with_number(trimmed) do
      {nil, nil} ->
        # Fallback to notes parsing for free-text descriptions
        parse_series_from_text(trimmed)

      result ->
        result
    end
  end

  defp extract_series_from_edition_field(_), do: {nil, nil}

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
    # Debug logging for title/UPC search responses (log first result)
    if length(docs) > 0 do
      first_doc = List.first(docs)

      Logger.debug(
        "OpenLibrary search response (first result): #{inspect(first_doc, pretty: true)}"
      )
    end

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
    # Debug logging to see actual OpenLibrary response structure
    Logger.debug("OpenLibrary ISBN search response: #{inspect(doc, pretty: true)}")

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

    # Try to get series data from edition endpoint using edition key
    {series_name, series_number} =
      case get_in(doc, ["editions", "docs"]) do
        [first_edition | _] when is_map(first_edition) ->
          case first_edition["key"] do
            edition_key when is_binary(edition_key) ->
              case fetch_edition_data(edition_key) do
                {:ok, edition_data} -> extract_series_from_edition(edition_data)
                # Fallback to search data
                {:error, _} -> extract_series_data(doc)
              end

            _ ->
              # Fallback to search data
              extract_series_data(doc)
          end

        _ ->
          # Fallback to search data
          extract_series_data(doc)
      end

    %{
      title: doc["title"] || "Unknown Title",
      author: extract_author_names(doc["author_name"]),
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: List.first(doc["publisher"] || []),
      publication_date: extract_search_publish_date(doc),
      pages: doc["number_of_pages"] || doc["number_of_pages_median"],
      key: doc["key"],
      cover_url: generate_cover_url(isbn13 || isbn10),
      # New fields from search results
      subtitle: doc["subtitle"],
      genre: extract_search_subjects(doc["subject"]),
      series: series_name,
      series_number: series_number,
      suggested_media_types: extract_media_types_from_formats(doc["format"])
    }
  end

  defp normalize_isbn_search_result(doc) do
    isbn10 = extract_isbn_from_list(doc["isbn"], 10)
    isbn13 = extract_isbn_from_list(doc["isbn"], 13)

    # Try to get series data from edition endpoint using edition key
    {series_name, series_number} =
      case get_in(doc, ["editions", "docs"]) do
        [first_edition | _] when is_map(first_edition) ->
          case first_edition["key"] do
            edition_key when is_binary(edition_key) ->
              case fetch_edition_data(edition_key) do
                {:ok, edition_data} -> extract_series_from_edition(edition_data)
                # Fallback to search data
                {:error, _} -> extract_series_data(doc)
              end

            _ ->
              # Fallback to search data
              extract_series_data(doc)
          end

        _ ->
          # Fallback to search data
          extract_series_data(doc)
      end

    # Extract format from editions if available
    edition_formats = extract_formats_from_editions(doc["editions"])

    %{
      title: doc["title"] || "Unknown Title",
      author: extract_author_names(doc["author_name"]),
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: List.first(doc["publisher"] || []),
      publication_date: extract_search_publish_date(doc),
      pages: doc["number_of_pages"] || doc["number_of_pages_median"],
      key: doc["key"],
      cover_url: generate_cover_url(isbn13 || isbn10),
      # New fields from search results
      subtitle: doc["subtitle"],
      genre: extract_search_subjects(doc["subject"]),
      series: series_name,
      series_number: series_number,
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

  # Extract series data from OpenLibrary response
  defp extract_series_data(doc) do
    # Try different possible series fields
    series_data = doc["series"] || doc["series_name"] || []

    case extract_series_from_data(series_data) do
      {nil, nil} ->
        # Try extracting from notes fields as fallback
        extract_series_from_notes(doc)

      {series_name, series_number} ->
        # Log successful extraction
        Logger.debug("OpenLibrary series extracted: '#{series_name}' ##{inspect(series_number)}")
        {series_name, series_number}
    end
  rescue
    error ->
      Logger.warning("Error extracting OpenLibrary series data: #{inspect(error)}")
      Logger.debug("Problematic series data: #{inspect([doc["series"], doc["series_name"]])}")
      {nil, nil}
  end

  # Extract series from notes fields when direct series fields are empty
  defp extract_series_from_notes(doc) do
    # Check notes fields that might contain series information
    notes_fields = [
      doc["notes"],
      doc["edition_notes"],
      doc["work_titles"],
      doc["alternative_title"]
    ]

    # Try to find series data in any notes field
    Enum.find_value(notes_fields, {nil, nil}, fn notes_data ->
      case extract_series_from_notes_text(notes_data) do
        # Continue searching
        {nil, nil} -> false
        # Found series data
        result -> result
      end
    end)
  end

  # Parse series information from free-text notes
  defp extract_series_from_notes_text(nil), do: {nil, nil}
  defp extract_series_from_notes_text(""), do: {nil, nil}
  defp extract_series_from_notes_text([]), do: {nil, nil}

  # Handle notes as a string
  defp extract_series_from_notes_text(notes) when is_binary(notes) do
    parse_series_from_text(String.trim(notes))
  end

  # Handle notes as a list of strings
  defp extract_series_from_notes_text(notes_list) when is_list(notes_list) do
    notes_list
    |> Enum.find_value({nil, nil}, fn notes ->
      case extract_series_from_notes_text(notes) do
        {nil, nil} -> false
        result -> result
      end
    end)
  end

  defp extract_series_from_notes_text(_), do: {nil, nil}

  # Parse series from free text using common patterns
  defp parse_series_from_text(text) when is_binary(text) do
    # Common series patterns in notes
    patterns = [
      # "Book 1 of The Series Name"
      ~r/(?:Book|Volume|Vol\.?|Part)\s+(\d+)\s+of\s+(.+?)(?:\.|$)/i,
      # "The Series Name, Book 1" or "The Series Name #1"
      ~r/(.+?),?\s+(?:Book|Volume|Vol\.?|Part|#)\s*(\d+)/i,
      # "(Series Name ; 1)" or "(Series Name, v. 1)"
      ~r/\((.+?)\s*[;,]\s*(?:v\.?|vol\.?|book)?\s*(\d+)\)/i,
      # Just series name without number - "Part of The Series Name"
      ~r/(?:Part of|From)\s+(.+?)(?:\.|$)/i
    ]

    # Try each pattern with index to handle special cases
    result =
      patterns
      |> Enum.with_index()
      |> Enum.find_value({nil, nil}, fn {pattern, index} ->
        case Regex.run(pattern, text) do
          # Handle "Book 1 of The Series Name" - swap the captures for first pattern
          [_, number_str, series_name] when index == 0 ->
            cleaned_series = String.trim(series_name)
            series_number = parse_series_number(number_str)
            if cleaned_series != "", do: {cleaned_series, series_number}, else: false

          # Handle other patterns normally
          [_, series_name, number_str] ->
            cleaned_series = String.trim(series_name)
            series_number = parse_series_number(number_str)
            if cleaned_series != "", do: {cleaned_series, series_number}, else: false

          [_, series_name] ->
            cleaned_series = String.trim(series_name)
            if cleaned_series != "", do: {cleaned_series, nil}, else: false

          _ ->
            false
        end
      end)

    # Log if we found series in notes
    case result do
      {series_name, series_number} when series_name != nil ->
        Logger.debug(
          "OpenLibrary series extracted from notes: '#{series_name}' ##{inspect(series_number)} in text: #{String.slice(text, 0, 100)}..."
        )

        result

      _ ->
        {nil, nil}
    end
  end

  # Extract series name and optional number from various data formats
  defp extract_series_from_data([]), do: {nil, nil}
  defp extract_series_from_data(nil), do: {nil, nil}
  defp extract_series_from_data(""), do: {nil, nil}

  # Handle series as a string
  defp extract_series_from_data(series) when is_binary(series) do
    parse_series_with_number(String.trim(series))
  end

  # Handle series as a list of strings (common in OpenLibrary)
  defp extract_series_from_data(series_list) when is_list(series_list) do
    case Enum.find(series_list, fn s -> is_binary(s) and String.trim(s) != "" end) do
      nil -> {nil, nil}
      series_string -> parse_series_with_number(String.trim(series_string))
    end
  end

  defp extract_series_from_data(_), do: {nil, nil}

  # Parse series string and extract number if present in "Series Name #Number" format
  defp parse_series_with_number(series_string) when is_binary(series_string) do
    case String.split(series_string, " #", parts: 2) do
      # Format: "Series Name #Number"
      [series_part, number_part] when series_part != "" ->
        series_name = String.trim(series_part)
        series_number = parse_series_number(number_part)
        {series_name, series_number}

      # Format: just "Series Name" (no number)
      [series_part] when series_part != "" ->
        {String.trim(series_part), nil}

      # Empty or malformed
      _ ->
        {nil, nil}
    end
  end

  # Parse series number from string
  defp parse_series_number(number_str) when is_binary(number_str) do
    case String.trim(number_str) do
      "" ->
        nil

      trimmed ->
        case Integer.parse(trimmed) do
          {num, _} ->
            num

          :error ->
            # Try float parsing as fallback
            case Float.parse(trimmed) do
              {num, _} -> round(num)
              :error -> nil
            end
        end
    end
  end

  defp parse_series_number(_), do: nil
end
