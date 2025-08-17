defmodule FuzzyCatalog.Catalog.Providers.LibraryOfCongressProvider do
  @moduledoc """
  Library of Congress SRU catalog provider for book lookups.

  Uses the Library of Congress SRU (Search/Retrieve via URL) catalog endpoint
  to retrieve bibliographic data in MODS XML format.
  """

  @behaviour FuzzyCatalog.Catalog.BookLookupProvider

  require Logger
  alias FuzzyCatalog.Catalog.BookLookupProvider

  @sru_base_url "http://lx2.loc.gov:210/lcdb"
  @sru_params "version=1.1&operation=searchRetrieve&recordSchema=mods&maximumRecords=10"

  @impl BookLookupProvider
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")

    case validate_isbn(clean_isbn) do
      :valid ->
        query = "bath.isbn=#{clean_isbn}"
        url = "#{@sru_base_url}?#{@sru_params}&query=#{URI.encode(query)}&maximumRecords=1"

        case make_request(url) do
          {:ok, xml_response} ->
            parse_isbn_response(xml_response)

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
        query = "bath.title=\"#{clean_title}\""
        url = "#{@sru_base_url}?#{@sru_params}&query=#{URI.encode(query)}"

        case make_request(url) do
          {:ok, xml_response} ->
            parse_search_response(xml_response)

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl BookLookupProvider
  def lookup_by_upc(_upc) do
    {:error, "UPC lookup not supported by Library of Congress"}
  end

  @impl BookLookupProvider
  def provider_name, do: "Library of Congress"

  # Private functions

  defp make_request(url) do
    Logger.info("LibraryOfCongress: Making request to: #{url}")

    case Req.get(url, headers: [{"User-Agent", "FuzzyCatalog/1.0"}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("LibraryOfCongress: Request failed: #{inspect(reason)}")
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

  defp parse_isbn_response(xml_body) do
    case parse_mods_records(xml_body) do
      [record | _] ->
        {:ok, normalize_mods_data(record)}

      [] ->
        {:error, "Book not found"}
    end
  end

  defp parse_search_response(xml_body) do
    case parse_mods_records(xml_body) do
      [] ->
        {:error, "No books found"}

      records ->
        books = Enum.map(records, &normalize_mods_data/1)
        {:ok, books}
    end
  end

  defp parse_mods_records(xml_body) do
    try do
      # Ensure we have a string
      xml_string = to_string(xml_body)
      {doc, _} = :xmerl_scan.string(String.to_charlist(xml_string))

      # Extract MODS records from SRU response - they're in the default namespace
      records =
        :xmerl_xpath.string(~c"//mods", doc, [
          {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
        ])

      Enum.map(records, &extract_mods_data/1)
    rescue
      error ->
        Logger.error("LibraryOfCongress: XML parsing failed: #{inspect(error)}")
        []
    end
  end

  defp extract_mods_data(mods_element) do
    %{
      title: extract_title(mods_element),
      author: extract_author(mods_element),
      isbn10: extract_isbn(mods_element, 10),
      isbn13: extract_isbn(mods_element, 13),
      publisher: extract_publisher(mods_element),
      publication_date: extract_publication_date(mods_element),
      pages: extract_pages(mods_element),
      subtitle: extract_subtitle(mods_element),
      description: extract_description(mods_element),
      genre: extract_genre(mods_element),
      series: extract_series(mods_element),
      suggested_media_types: []
    }
  end

  defp extract_title(mods_element) do
    case :xmerl_xpath.string(~c".//mods:titleInfo[not(@type)]/mods:title/text()", mods_element, [
           {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
         ]) do
      [title_node | _] ->
        extract_text_from_node(title_node)

      [] ->
        "Unknown Title"
    end
  end

  defp extract_subtitle(mods_element) do
    case :xmerl_xpath.string(
           ~c".//mods:titleInfo[not(@type)]/mods:subTitle/text()",
           mods_element,
           [{:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}]
         ) do
      [subtitle_node | _] ->
        extract_text_from_node(subtitle_node)

      [] ->
        nil
    end
  end

  defp extract_author(mods_element) do
    authors =
      :xmerl_xpath.string(
        ~c".//mods:name[@type=\"personal\"]/mods:namePart[not(@type) or @type=\"family\" or @type=\"given\"]/text()",
        mods_element,
        [{:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}]
      )

    case authors do
      [] ->
        "Unknown Author"

      author_nodes ->
        author_nodes
        |> Enum.map(&extract_text_from_node/1)
        |> Enum.join(", ")
    end
  end

  defp extract_isbn(mods_element, length) do
    isbn_nodes =
      :xmerl_xpath.string(~c".//mods:identifier[@type=\"isbn\"]/text()", mods_element, [
        {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
      ])

    isbn_nodes
    |> Enum.map(&extract_text_from_node/1)
    |> Enum.find(fn isbn ->
      clean_isbn = String.replace(isbn, ~r/[^0-9X]/, "")
      String.length(clean_isbn) == length
    end)
  end

  defp extract_publisher(mods_element) do
    case :xmerl_xpath.string(~c".//mods:originInfo/mods:publisher/text()", mods_element, [
           {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
         ]) do
      [publisher_node | _] ->
        extract_text_from_node(publisher_node)

      [] ->
        nil
    end
  end

  defp extract_publication_date(mods_element) do
    date_nodes =
      :xmerl_xpath.string(~c".//mods:originInfo/mods:dateIssued/text()", mods_element, [
        {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
      ])

    case date_nodes do
      [date_node | _] ->
        date_string = extract_text_from_node(date_node)
        parse_date(date_string)

      [] ->
        nil
    end
  end

  defp extract_pages(mods_element) do
    case :xmerl_xpath.string(~c".//mods:physicalDescription/mods:extent/text()", mods_element, [
           {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
         ]) do
      [extent_node | _] ->
        extent_string = extract_text_from_node(extent_node)
        extract_page_number(extent_string)

      [] ->
        nil
    end
  end

  defp extract_description(mods_element) do
    case :xmerl_xpath.string(~c".//mods:abstract/text()", mods_element, [
           {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
         ]) do
      [abstract_node | _] ->
        extract_text_from_node(abstract_node)

      [] ->
        nil
    end
  end

  defp extract_genre(mods_element) do
    genres =
      :xmerl_xpath.string(~c".//mods:genre/text()", mods_element, [
        {:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}
      ])

    case genres do
      [] ->
        nil

      genre_nodes ->
        genre_nodes
        |> Enum.take(3)
        |> Enum.map(&extract_text_from_node/1)
        |> Enum.join(", ")
    end
  end

  defp extract_series(mods_element) do
    case :xmerl_xpath.string(
           ~c".//mods:relatedItem[@type=\"series\"]/mods:titleInfo/mods:title/text()",
           mods_element,
           [{:namespace, [{~c"mods", ~c"http://www.loc.gov/mods/v3"}]}]
         ) do
      [series_node | _] ->
        extract_text_from_node(series_node)

      [] ->
        nil
    end
  end

  defp parse_date(date_string) when is_binary(date_string) do
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

  defp extract_page_number(extent_string) when is_binary(extent_string) do
    case Regex.run(~r/(\d+)\s*p/, extent_string) do
      [_, pages] -> String.to_integer(pages)
      _ -> nil
    end
  end

  defp extract_text_from_node({:xmlText, _, _, _, text, _}) when is_list(text) do
    to_string(text)
  end

  defp extract_text_from_node({:xmlText, _, _, _, text, _}) when is_binary(text) do
    text
  end

  defp extract_text_from_node(_), do: ""

  defp normalize_mods_data(mods_data) do
    # Add cover_url using OpenLibrary fallback since LOC doesn't provide cover images
    isbn = mods_data.isbn13 || mods_data.isbn10

    cover_url =
      case isbn do
        nil ->
          nil

        isbn_value ->
          "https://covers.openlibrary.org/b/isbn/#{String.replace(isbn_value, ~r/[^0-9X]/, "")}-M.jpg"
      end

    Map.put(mods_data, :cover_url, cover_url)
  end
end
