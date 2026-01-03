defmodule FuzzyCatalog.Catalog.Providers.DNBProvider do
  @moduledoc """
  Book lookup provider backed by Deutsche Nationalbibliothek (DNB).

  Features:
  - Lookup by ISBN, title, or UPC/barcode (treated as ISBN)
  - Full book metadata from DNB SRU OAI-DC records
  - Includes page count, description, subjects, publisher, date
  - Fetches covers directly from DNB cover service
  """

  @behaviour FuzzyCatalog.Catalog.BookLookupProvider

  import SweetXml
  require Logger

  @sru_base "https://services.dnb.de/sru/dnb"

  # ------------------------------------------------------------
  # Behaviour callbacks
  # ------------------------------------------------------------

  @impl true
  def provider_name, do: "DNB"

  @impl true
  def lookup_by_isbn(isbn) when is_binary(isbn) do
    isbn
    |> sru_search("isbn")
    |> first_record()
  end

  @impl true
  def lookup_by_title(title) when is_binary(title) do
    title
    |> sru_search("title")
    |> all_records()
  end

  @impl true
  # UPC / barcode often *is* an ISBN → treat identically
  def lookup_by_upc(upc) when is_binary(upc) do
    lookup_by_isbn(upc)
  end

  # ------------------------------------------------------------
  # SRU search
  # ------------------------------------------------------------

  defp sru_search(term, field) do
    query = "#{field}=\"#{term}\""

    url =
      @sru_base <>
        "?version=1.1" <>
        "&operation=searchRetrieve" <>
        "&recordSchema=oai_dc" <>
        "&query=#{URI.encode(query)}"

    case HTTPoison.get(url, [], follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: code}} -> {:error, "SRU HTTP #{code}"}
      {:error, reason} -> {:error, "SRU HTTP error: #{inspect(reason)}"}
    end
  end

  # ------------------------------------------------------------
  # Result handling
  # ------------------------------------------------------------

  defp first_record({:error, _} = err), do: err

  defp first_record({:ok, xml_or_doc}) do
    case extract_records(xml_or_doc) do
      {:ok, [record | _]} -> safe_build_book(record)
      {:ok, []} -> {:error, "No DNB record found"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp all_records({:error, _} = err), do: err

  defp all_records({:ok, xml_or_doc}) do
    case extract_records(xml_or_doc) do
      {:ok, records} ->
        records
        |> Enum.map(&safe_build_book/1)
        |> collect_build_results()

      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_build_results(results) do
    {oks, errs} = Enum.split_with(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)

    case errs do
      [] -> {:ok, Enum.map(oks, fn {:ok, b} -> b end)}
      _ -> {:error, "One or more records could not be parsed"}
    end
  end

  # ------------------------------------------------------------
  # XML parsing
  # ------------------------------------------------------------

  defp extract_records(doc) when is_tuple(doc) do
    # Already parsed xmerl document
    {:ok, xpath(doc, ~x"//record"l)}
  end

  defp extract_records(xml) when is_binary(xml) do
    xml = String.trim(xml || "")

    cond do
      xml == "" -> {:error, "Empty response from DNB"}
      not String.starts_with?(xml, "<") -> {:error, "Non-XML response from DNB"}
      true ->
        case parse_xml(xml) do
          {:ok, doc} -> {:ok, xpath(doc, ~x"//record"l)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp parse_xml(xml) when is_binary(xml) do
    try do
      {:ok, SweetXml.parse(xml)}
    catch
      :exit, reason ->
        Logger.debug("DNB XML parse exit (raw): #{inspect(reason)}")
        {:error, "Invalid XML response from DNB"}
    rescue
      e ->
        Logger.debug("DNB XML parse exception (raw): #{Exception.format(:error, e, __STACKTRACE__)}")
        {:error, "XML parse error from DNB"}
    end
  end

  defp safe_build_book(record) do
    try do
      {:ok, build_book(record)}
    catch
      kind, reason ->
        Logger.debug("Failed building DNB book (#{inspect(kind)}): #{inspect(reason)}")
        {:error, "Invalid XML record from DNB"}
    rescue
      e ->
        Logger.debug("Exception building DNB book (raw): #{Exception.format(:error, e, __STACKTRACE__)}")
        {:error, "Internal parsing error"}
    end
  end

  defp build_book(xml) do
    # Use relative XPaths so we search within the record node rather than
    # attempting to re-parse or query the whole document.
    title = text(xml, ".//dc:title") || ""
    subtitle = text(xml, ".//dc:title[@xsi:type='subtitle']")

    authors = texts(xml, ".//dc:creator") |> Enum.join(", ")

    identifiers = texts(xml, ".//dc:identifier")
    {isbn10, isbn13} = extract_isbns(identifiers)

    %{
      title: title,
      subtitle: subtitle,
      author: authors,
      isbn10: isbn10,
      isbn13: isbn13,
      publisher: text(xml, ".//dc:publisher"),
      publication_date: parse_date(text(xml, ".//dc:date")),
      pages: parse_pages(text(xml, ".//dc:extent")),
      description: text(xml, ".//dc:description"),
      genre: text(xml, ".//dc:subject"),
      series: nil,
      series_number: nil,
      original_title: nil,
      cover_url: cover_url(isbn13 || isbn10)
    }
  end

  # ------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------

  defp text(xml, path) do
    case xpath(xml, ~x"#{path}/text()"s, dc: dc_ns(), xsi: xsi_ns()) do
      nil -> nil
      v -> String.trim(v)
    end
  end

  defp texts(xml, path) do
    case xpath(xml, ~x"#{path}/text()"l, dc: dc_ns()) do
      nil -> []
      list -> Enum.map(list, &String.trim/1)
    end
  end

  defp extract_isbns(ids) do
    ids = ids || []

    clean = Enum.map(ids, &String.replace(&1 || "", ~r/[^0-9X]/i, ""))

    isbn10 = Enum.find(clean, &(String.length(&1) == 10))
    isbn13 = Enum.find(clean, &(String.length(&1) == 13))

    {isbn10, isbn13}
  end

  defp parse_pages(nil), do: nil
  defp parse_pages(extent) when is_binary(extent) do
    case Regex.run(~r/(\d+)/, extent) do
      [_, num] -> String.to_integer(num)
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp cover_url(nil), do: nil
  defp cover_url(isbn) do
    normalized = isbn |> String.replace(~r/[^0-9X]/i, "")
    "https://portal.dnb.de/opac/mvb/cover?isbn=#{hyphenate_isbn(normalized)}"
  end

  defp hyphenate_isbn(isbn) do
    case String.length(isbn || "") do
      13 -> String.replace(isbn, ~r/^(\d{3})(\d)(\d{4})(\d{4})(\d)$/, "\\1-\\2-\\3-\\4-\\5")
      10 -> String.replace(isbn, ~r/^(\d)(\d{4})(\d{4})([\dX])$/, "\\1-\\2-\\3-\\4")
      _ -> isbn
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp dc_ns, do: "http://purl.org/dc/elements/1.1/"
  defp xsi_ns, do: "http://www.w3.org/2001/XMLSchema-instance"
end
