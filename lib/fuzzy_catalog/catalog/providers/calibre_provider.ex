defmodule FuzzyCatalog.Catalog.Providers.CalibreProvider do
  @moduledoc """
  Calibre external library provider implementation.

  Synchronizes ebooks from a Calibre library by reading its SQLite metadata database.
  """

  @behaviour FuzzyCatalog.Catalog.ExternalLibraryProvider

  require Logger
  alias FuzzyCatalog.IsbnUtils

  @impl true
  def provider_name, do: "Calibre"

  @impl true
  def available? do
    case get_library_path() do
      {:ok, path} ->
        metadata_db_path = Path.join(path, "metadata.db")
        File.exists?(metadata_db_path)

      {:error, _} ->
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
    case get_library_path() do
      {:ok, library_path} ->
        metadata_db_path = Path.join(library_path, "metadata.db")

        case open_database(metadata_db_path) do
          {:ok, db} ->
            try do
              Logger.debug("Fetching books from Calibre library: #{library_path}")
              stream = create_books_stream(db, library_path)
              {:ok, stream}
            after
              close_database(db)
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  defp get_library_path do
    config = Application.get_env(:fuzzy_catalog, :calibre, [])

    case Keyword.get(config, :library_path) do
      path when is_binary(path) and path != "" ->
        if File.dir?(path) do
          {:ok, path}
        else
          {:error, "Calibre library path does not exist: #{path}"}
        end

      _ ->
        {:error, "Calibre library path must be configured"}
    end
  end

  defp open_database(db_path) do
    if File.exists?(db_path) do
      case Exqlite.Sqlite3.open(db_path) do
        {:ok, db} ->
          {:ok, db}

        {:error, reason} ->
          Logger.error("Failed to open Calibre database: #{inspect(reason)}")
          {:error, "Failed to open Calibre database: #{inspect(reason)}"}
      end
    else
      {:error, "Calibre metadata.db not found at: #{db_path}"}
    end
  end

  defp close_database(db) do
    Exqlite.Sqlite3.close(db)
  end

  defp create_books_stream(db, library_path) do
    # Query to get all books with their metadata
    query = """
    SELECT 
      b.id as book_id,
      b.title,
      b.sort as title_sort,
      b.pubdate,
      b.series_index,
      b.author_sort,
      b.isbn,
      b.path,
      b.uuid,
      b.has_cover,
      GROUP_CONCAT(a.name, ' & ') as authors,
      p.name as publisher,
      c.text as description,
      s.name as series_name
    FROM books b
    LEFT JOIN books_authors_link bal ON b.id = bal.book
    LEFT JOIN authors a ON bal.author = a.id
    LEFT JOIN books_publishers_link bpl ON b.id = bpl.book
    LEFT JOIN publishers p ON bpl.publisher = p.id
    LEFT JOIN comments c ON b.id = c.book
    LEFT JOIN books_series_link bsl ON b.id = bsl.book
    LEFT JOIN series s ON bsl.series = s.id
    GROUP BY b.id
    ORDER BY b.id
    """

    case Exqlite.Sqlite3.prepare(db, query) do
      {:ok, statement} ->
        create_streaming_results(db, statement, library_path)

      {:error, reason} ->
        Logger.error("Failed to prepare Calibre query: #{reason}")
        []
    end
  end

  defp create_streaming_results(db, statement, library_path) do
    Stream.resource(
      fn -> statement end,
      fn stmt ->
        case Exqlite.Sqlite3.step(db, stmt) do
          {:row, row} ->
            case transform_row_to_book(row, library_path, db) do
              nil -> {[], stmt}
              book -> {[book], stmt}
            end

          :done ->
            {:halt, stmt}

          {:error, reason} ->
            Logger.error("Error stepping through Calibre results: #{reason}")
            {:halt, stmt}
        end
      end,
      fn stmt ->
        Exqlite.Sqlite3.release(db, stmt)
      end
    )
  end


  defp transform_row_to_book(row, library_path, db) do
    try do
      [
        book_id,
        title,
        _title_sort,
        pubdate,
        series_index,
        _author_sort,
        isbn,
        path,
        _uuid,
        has_cover,
        authors,
        publisher,
        description,
        series_name
      ] = row

      # Parse publication date
      publication_date = parse_publication_date(pubdate)

      # Get additional identifiers
      {isbn10, isbn13, asin} = get_book_identifiers(db, book_id, isbn)

      # Build cover URL if cover exists
      cover_url = build_cover_url(library_path, path, has_cover)

      # Parse series information
      {series, series_number} = parse_series_info(series_name, series_index)

      %{
        title: title || "Unknown Title",
        author: authors || "Unknown Author",
        isbn10: isbn10,
        isbn13: isbn13,
        asin: asin,
        publisher: publisher,
        publication_date: publication_date,
        pages: nil,
        cover_url: cover_url,
        subtitle: nil,
        description: description,
        genre: nil,
        series: series,
        series_number: series_number,
        original_title: nil,
        media_type: "ebook",
        external_id: to_string(book_id)
      }
    rescue
      error ->
        Logger.warning("Failed to transform Calibre book row: #{inspect(error)}")
        nil
    end
  end

  defp parse_publication_date(nil), do: nil
  defp parse_publication_date(""), do: nil

  defp parse_publication_date(pubdate) when is_binary(pubdate) do
    # Calibre stores dates as ISO strings, sometimes with timezone
    case Date.from_iso8601(String.slice(pubdate, 0, 10)) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp parse_publication_date(_), do: nil

  defp get_book_identifiers(db, book_id, main_isbn) do
    # Query identifiers table for additional ISBNs and ASINs
    query = "SELECT type, val FROM identifiers WHERE book = ?"

    identifiers =
      case Exqlite.Sqlite3.prepare(db, query) do
        {:ok, statement} ->
          :ok = Exqlite.Sqlite3.bind(statement, [book_id])
          rows = collect_identifier_rows(db, statement, [])
          Exqlite.Sqlite3.release(db, statement)
          rows

        {:error, _reason} ->
          []
      end

    # Build identifier map including main ISBN
    identifier_map =
      identifiers
      |> Enum.reduce(%{"isbn" => main_isbn}, fn [type, val], acc ->
        Map.put(acc, type, val)
      end)

    # Use ISBN utils to parse and normalize
    IsbnUtils.parse_identifiers(identifier_map)
  end

  defp collect_identifier_rows(db, statement, acc) do
    case Exqlite.Sqlite3.step(db, statement) do
      {:row, row} ->
        collect_identifier_rows(db, statement, [row | acc])

      :done ->
        Enum.reverse(acc)

      {:error, _reason} ->
        Enum.reverse(acc)
    end
  end

  defp build_cover_url(_library_path, nil, _), do: nil
  defp build_cover_url(_library_path, "", _), do: nil
  defp build_cover_url(_library_path, _path, 0), do: nil
  defp build_cover_url(_library_path, _path, false), do: nil

  defp build_cover_url(library_path, book_path, _) do
    # Calibre stores covers as cover.jpg in the book's directory
    cover_path = Path.join([library_path, book_path, "cover.jpg"])

    if File.exists?(cover_path) do
      "file://" <> cover_path
    else
      nil
    end
  end

  defp parse_series_info(nil, _), do: {nil, nil}
  defp parse_series_info("", _), do: {nil, nil}

  defp parse_series_info(series_name, series_index) do
    series_number =
      case series_index do
        num when is_number(num) ->
          round(num)

        str when is_binary(str) ->
          case Float.parse(str) do
            {num, _} -> round(num)
            :error -> nil
          end

        _ ->
          nil
      end

    {series_name, series_number}
  end
end
