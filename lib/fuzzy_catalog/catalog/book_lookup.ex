defmodule FuzzyCatalog.Catalog.BookLookup do
  @moduledoc """
  Service for looking up book information from external APIs.
  Uses Open Library API for free book data lookup.
  """

  require Logger

  @base_url "https://openlibrary.org"
  @books_api_url "#{@base_url}/api/books"
  @search_api_url "#{@base_url}/search.json"
  @covers_api_url "https://covers.openlibrary.org"

  @doc """
  Look up a book by ISBN (10 or 13 digit).

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_isbn("0451526538")
      {:ok, %{title: "...", author: "...", ...}}
      
      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_isbn("invalid")
      {:error, "Book not found"}
  """
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

  @doc """
  Look up books by title.
  Returns multiple results if found.

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_title("Lord of the Rings")
      {:ok, [%{title: "...", author: "...", ...}, ...]}
      
      iex> FuzzyCatalog.Catalog.BookLookup.lookup_by_title("")
      {:error, "Title cannot be empty"}
  """
  def lookup_by_title(title) when is_binary(title) do
    case String.trim(title) do
      "" ->
        {:error, "Title cannot be empty"}

      clean_title ->
        encoded_title = URI.encode(clean_title)

        url =
          "#{@search_api_url}?title=#{encoded_title}&fields=title,author_name,first_publish_year,isbn,publisher,key&limit=10"

        case make_request(url) do
          {:ok, response} ->
            parse_search_response(response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Look up book by UPC/barcode.
  Note: UPC lookup uses the search API as Open Library doesn't directly support UPC.
  """
  def lookup_by_upc(upc) when is_binary(upc) do
    clean_upc = String.replace(upc, ~r/[^0-9]/, "")

    if String.length(clean_upc) == 12 do
      url =
        "#{@search_api_url}?q=#{clean_upc}&fields=title,author_name,first_publish_year,isbn,publisher,key&limit=5"

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

  # Private functions

  defp make_request(url) do
    Logger.info("Making request to: #{url}")

    case Req.get(url, headers: [{"User-Agent", "FuzzyCatalog/1.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, "Network error"}
    end
  end

  defp generate_cover_url(nil), do: nil
  defp generate_cover_url(""), do: nil

  defp generate_cover_url(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")
    "#{@covers_api_url}/b/isbn/#{clean_isbn}-M.jpg"
  end

  @doc """
  Generate cover URLs for different sizes.

  ## Examples

      iex> FuzzyCatalog.Catalog.BookLookup.cover_url("9780141439518", :small)
      "https://covers.openlibrary.org/b/isbn/9780141439518-S.jpg"
      
      iex> FuzzyCatalog.Catalog.BookLookup.cover_url("9780141439518", :medium)
      "https://covers.openlibrary.org/b/isbn/9780141439518-M.jpg"
  """
  def cover_url(nil, _size), do: nil
  def cover_url("", _size), do: nil

  def cover_url(isbn, size) when is_binary(isbn) and size in [:small, :medium, :large] do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    size_code =
      case size do
        :small -> "S"
        :medium -> "M"
        :large -> "L"
      end

    "#{@covers_api_url}/b/isbn/#{clean_isbn}-#{size_code}.jpg"
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
      publish_year: extract_publish_year(get_in(data, ["publish_date"])),
      pages: get_in(data, ["number_of_pages"]),
      cover_url: generate_cover_url(isbn13 || isbn10)
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
      publish_year: doc["first_publish_year"],
      key: doc["key"],
      cover_url: generate_cover_url(isbn13 || isbn10)
    }
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
    Enum.find(isbns, fn isbn -> String.length(String.replace(isbn, ~r/[^0-9X]/, "")) == length end)
  end

  defp extract_first_publisher(nil), do: nil
  defp extract_first_publisher([]), do: nil

  defp extract_first_publisher([publisher | _]) when is_map(publisher) do
    publisher["name"]
  end

  defp extract_first_publisher([publisher | _]) when is_binary(publisher) do
    publisher
  end

  defp extract_publish_year(nil), do: nil

  defp extract_publish_year(date) when is_binary(date) do
    case Regex.run(~r/\d{4}/, date) do
      [year] -> String.to_integer(year)
      _ -> nil
    end
  end
end
