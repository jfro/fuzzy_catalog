defmodule FuzzyCatalog.Catalog.Providers.OpenLibraryProvider do
  @moduledoc """
  OpenLibrary API provider for book lookups.
  """

  @behaviour FuzzyCatalog.Catalog.BookLookupProvider

  require Logger
  alias FuzzyCatalog.Catalog.BookLookupProvider

  @base_url "https://openlibrary.org"
  @books_api_url "#{@base_url}/api/books"
  @search_api_url "#{@base_url}/search.json"
  @covers_api_url "https://covers.openlibrary.org"

  @impl BookLookupProvider
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    case validate_isbn(clean_isbn) do
      :valid ->
        bibkey = "ISBN:#{clean_isbn}"
        url = "#{@books_api_url}?bibkeys=#{bibkey}&format=json&jscmd=data"

        case make_request(url) do
          {:ok, response} ->
            parse_book_response(response, bibkey)
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
          "#{@search_api_url}?title=#{encoded_title}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject&limit=10"

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
        "#{@search_api_url}?q=#{clean_upc}&fields=title,author_name,first_publish_year,publish_date,isbn,publisher,key,subtitle,subject&limit=5"

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

  defp parse_book_response(response, bibkey) do
    case response do
      %{^bibkey => book_data} ->
        {:ok, normalize_book_data(book_data)}
      _ ->
        {:error, "Book not found"}
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

  defp normalize_book_data(data) do
    isbn10 = extract_isbn(data, 10)
    isbn13 = extract_isbn(data, 13)

    %{
      title: get_in(data, ["title"]) || "Unknown Title",
      author: extract_authors(get_in(data, ["authors"])),
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: extract_first_publisher(get_in(data, ["publishers"])),
      publication_date: extract_publish_date(get_in(data, ["publish_date"])),
      pages: get_in(data, ["number_of_pages"]),
      cover_url: generate_cover_url(isbn13 || isbn10),
      # New fields
      subtitle: get_in(data, ["subtitle"]),
      description: extract_description(data),
      genre: extract_subjects(get_in(data, ["subjects"])),
      series: extract_series(data)
    }
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
      genre: extract_search_subjects(doc["subject"])
    }
  end

  defp generate_cover_url(nil), do: nil
  defp generate_cover_url(""), do: nil
  defp generate_cover_url(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")
    "#{@covers_api_url}/b/isbn/#{clean_isbn}-M.jpg"
  end

  defp extract_authors(nil), do: "Unknown Author"
  defp extract_authors([]), do: "Unknown Author"
  defp extract_authors(authors) when is_list(authors) do
    authors
    |> Enum.map(fn author -> author["name"] || "Unknown" end)
    |> Enum.join(", ")
  end

  defp extract_author_names(nil), do: "Unknown Author"
  defp extract_author_names([]), do: "Unknown Author"
  defp extract_author_names(names) when is_list(names) do
    Enum.join(names, ", ")
  end

  defp extract_isbn(data, length) do
    case get_in(data, ["identifiers", "isbn_#{length}"]) do
      [isbn | _] -> isbn
      _ -> nil
    end
  end

  defp extract_isbn_from_list(nil, _length), do: nil
  defp extract_isbn_from_list([], _length), do: nil
  defp extract_isbn_from_list(isbns, length) when is_list(isbns) do
    Enum.find(isbns, fn isbn -> 
      String.length(String.replace(isbn, ~r/[^0-9X]/, "")) == length 
    end)
  end

  defp extract_first_publisher(nil), do: nil
  defp extract_first_publisher([]), do: nil
  defp extract_first_publisher([publisher | _]) when is_map(publisher) do
    publisher["name"]
  end
  defp extract_first_publisher([publisher | _]) when is_binary(publisher) do
    publisher
  end

  defp extract_publish_date(nil), do: nil
  defp extract_publish_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, parsed_date} -> parsed_date
      {:error, _} ->
        # Try to parse just the year if full date parsing fails
        case Regex.run(~r/\d{4}/, date) do
          [year] -> Date.new!(String.to_integer(year), 1, 1)
          _ -> nil
        end
    end
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
          year when is_integer(year) -> Date.new!(year, 1, 1)
          _ -> nil
        end
    end
  end

  defp extract_description(data) do
    case get_in(data, ["description"]) do
      %{"value" => value} when is_binary(value) -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp extract_subjects(nil), do: nil
  defp extract_subjects([]), do: nil
  defp extract_subjects(subjects) when is_list(subjects) do
    subjects
    |> Enum.take(3)  # Limit to first 3 subjects
    |> Enum.map(fn
      %{"name" => name} when is_binary(name) -> name
      subject when is_binary(subject) -> subject
      _ -> nil
    end)
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      names -> Enum.join(names, ", ")
    end
  end

  defp extract_search_subjects(nil), do: nil
  defp extract_search_subjects([]), do: nil
  defp extract_search_subjects(subjects) when is_list(subjects) do
    subjects
    |> Enum.take(3)  # Limit to first 3 subjects
    |> Enum.join(", ")
  end

  defp extract_series(data) do
    # OpenLibrary might have series info in different places
    case get_in(data, ["series"]) do
      [series | _] when is_binary(series) -> series
      series when is_binary(series) -> series
      _ -> nil
    end
  end
end