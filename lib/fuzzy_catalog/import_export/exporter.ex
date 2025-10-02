defmodule FuzzyCatalog.ImportExport.Exporter do
  @moduledoc """
  Handles exporting catalog data to various formats.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Catalog.Book
  alias FuzzyCatalog.Collections.CollectionItem
  alias FuzzyCatalog.ImportExport
  alias FuzzyCatalog.ImportExport.Job
  alias FuzzyCatalog.Storage

  @supported_formats ["json", "csv"]

  @doc """
  Performs an export job asynchronously.
  """
  def perform_export(%Job{} = job) do
    case update_job_status(job, "processing") do
      {:ok, job} ->
        try do
          export_data(job)
        rescue
          error ->
            ImportExport.fail_job(job, "Export failed: #{Exception.message(error)}")
        end

      {:error, _changeset} ->
        {:error, "Failed to update job status"}
    end
  end

  defp export_data(%Job{} = job) do
    filters = job.filters || %{}
    format = Map.get(filters, "format", "json")

    unless format in @supported_formats do
      ImportExport.fail_job(job, "Unsupported format: #{format}")
    end

    # Get filtered data
    query_result = build_export_query(filters)
    collection_items = Repo.all(query_result.query)
    total_items = length(collection_items)

    # Update job with total count
    ImportExport.update_job_progress(job, %{
      total_items: total_items,
      processed_items: 0,
      progress: 0
    })

    # Process data in chunks for large exports
    chunk_size = 100
    chunks = Enum.chunk_every(collection_items, chunk_size)

    case format do
      "json" -> export_to_json(job, chunks, total_items)
      "csv" -> export_to_csv(job, chunks, total_items)
    end
  end

  defp build_export_query(filters) do
    base_query =
      from ci in CollectionItem,
        join: b in Book,
        on: ci.book_id == b.id,
        preload: [book: b],
        order_by: [desc: ci.added_at]

    query =
      base_query
      |> apply_media_type_filter(filters)
      |> apply_external_id_filter(filters)
      |> apply_date_range_filter(filters)
      |> apply_series_filter(filters)
      |> apply_genre_filter(filters)

    %{
      query: query,
      description: build_filter_description(filters)
    }
  end

  defp apply_media_type_filter(query, %{"media_type" => media_type})
       when is_binary(media_type) and media_type != "" do
    from [ci, b] in query, where: ci.media_type == ^media_type
  end

  defp apply_media_type_filter(query, _), do: query

  defp apply_external_id_filter(query, %{"no_external_id" => "true"}) do
    from [ci, b] in query,
      left_join: ell in FuzzyCatalog.Catalog.ExternalLibraryLink,
      on: ell.book_id == b.id,
      where: is_nil(ell.id)
  end

  defp apply_external_id_filter(query, _), do: query

  defp apply_date_range_filter(query, %{"date_from" => date_from})
       when is_binary(date_from) and date_from != "" do
    case Date.from_iso8601(date_from) do
      {:ok, date} ->
        from [ci, b] in query, where: ci.added_at >= ^date

      _ ->
        query
    end
  end

  defp apply_date_range_filter(query, _), do: query

  defp apply_series_filter(query, %{"series" => series})
       when is_binary(series) and series != "" do
    from [ci, b] in query, where: ilike(b.series, ^"%#{series}%")
  end

  defp apply_series_filter(query, _), do: query

  defp apply_genre_filter(query, %{"genre" => genre})
       when is_binary(genre) and genre != "" do
    from [ci, b] in query, where: ilike(b.genre, ^"%#{genre}%")
  end

  defp apply_genre_filter(query, _), do: query

  defp build_filter_description(filters) do
    descriptions = []

    descriptions =
      if media_type = filters["media_type"], do: ["Media type: #{media_type}" | descriptions], else: descriptions

    descriptions =
      if filters["no_external_id"] == "true",
        do: ["Items without external IDs" | descriptions],
        else: descriptions

    descriptions =
      if date_from = filters["date_from"], do: ["Added after: #{date_from}" | descriptions], else: descriptions

    descriptions =
      if series = filters["series"], do: ["Series: #{series}" | descriptions], else: descriptions

    descriptions =
      if genre = filters["genre"], do: ["Genre: #{genre}" | descriptions], else: descriptions

    case descriptions do
      [] -> "All items"
      list -> Enum.join(list, ", ")
    end
  end

  defp export_to_json(%Job{} = job, chunks, total_items) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    filename = "fuzzy_catalog_export_#{timestamp}.json"
    temp_path = Path.join(System.tmp_dir(), filename)

    try do
      File.open!(temp_path, [:write], fn file ->
        # Write JSON header
        IO.write(file, """
        {
          "export_info": {
            "exported_at": "#{DateTime.utc_now() |> DateTime.to_iso8601()}",
            "total_items": #{total_items},
            "filters": #{Jason.encode!(job.filters || %{})},
            "version": "1.0"
          },
          "items": [
        """)

        # Process chunks
        {_final_count, _} =
          Enum.reduce(chunks, {0, true}, fn chunk, {processed_count, is_first} ->
            chunk_data =
              Enum.map(chunk, fn collection_item ->
                %{
                  id: collection_item.id,
                  media_type: collection_item.media_type,
                  added_at: collection_item.added_at,
                  book: serialize_book(collection_item.book)
                }
              end)

            # Write chunk data
            chunk_json =
              chunk_data
              |> Enum.map(&Jason.encode!/1)
              |> Enum.join(",\n    ")

            if is_first do
              IO.write(file, "\n    #{chunk_json}")
            else
              IO.write(file, ",\n    #{chunk_json}")
            end

            new_processed = processed_count + length(chunk)
            progress = round(new_processed / total_items * 100)

            ImportExport.update_job_progress(job, %{
              processed_items: new_processed,
              progress: progress
            })

            {new_processed, false}
          end)

        # Write JSON footer
        IO.write(file, "\n  ]\n}")
      end)

      # Store file and complete job
      store_and_complete_job(job, temp_path, filename)
    rescue
      error ->
        File.rm(temp_path)
        ImportExport.fail_job(job, "JSON export failed: #{Exception.message(error)}")
    end
  end

  defp export_to_csv(%Job{} = job, chunks, total_items) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
    filename = "fuzzy_catalog_export_#{timestamp}.csv"
    temp_path = Path.join(System.tmp_dir(), filename)

    try do
      File.open!(temp_path, [:write], fn file ->
        # Write CSV header
        headers = [
          "collection_item_id",
          "media_type",
          "added_at",
          "title",
          "author",
          "isbn10",
          "isbn13",
          "upc",
          "amazon_asin",
          "publisher",
          "publication_date",
          "pages",
          "genre",
          "subtitle",
          "description",
          "series",
          "series_number",
          "original_title"
        ]

        IO.write(file, Enum.join(headers, ",") <> "\n")

        # Process chunks
        {_final_count, _} =
          Enum.reduce(chunks, {0, true}, fn chunk, {processed_count, _is_first} ->
            csv_rows =
              Enum.map(chunk, fn collection_item ->
                book = collection_item.book

                [
                  collection_item.id,
                  collection_item.media_type,
                  collection_item.added_at,
                  escape_csv_field(book.title),
                  escape_csv_field(book.author),
                  book.isbn10,
                  book.isbn13,
                  book.upc,
                  book.amazon_asin,
                  escape_csv_field(book.publisher),
                  book.publication_date,
                  book.pages,
                  escape_csv_field(book.genre),
                  escape_csv_field(book.subtitle),
                  escape_csv_field(book.description),
                  escape_csv_field(book.series),
                  book.series_number,
                  escape_csv_field(book.original_title)
                ]
                |> Enum.map(&to_string/1)
                |> Enum.join(",")
              end)

            IO.write(file, Enum.join(csv_rows, "\n") <> "\n")

            new_processed = processed_count + length(chunk)
            progress = round(new_processed / total_items * 100)

            ImportExport.update_job_progress(job, %{
              processed_items: new_processed,
              progress: progress
            })

            {new_processed, false}
          end)
      end)

      # Store file and complete job
      store_and_complete_job(job, temp_path, filename)
    rescue
      error ->
        File.rm(temp_path)
        ImportExport.fail_job(job, "CSV export failed: #{Exception.message(error)}")
    end
  end

  defp serialize_book(book) do
    %{
      id: book.id,
      title: book.title,
      author: book.author,
      isbn10: book.isbn10,
      isbn13: book.isbn13,
      upc: book.upc,
      amazon_asin: book.amazon_asin,
      cover_image_key: book.cover_image_key,
      publisher: book.publisher,
      publication_date: book.publication_date,
      pages: book.pages,
      genre: book.genre,
      subtitle: book.subtitle,
      description: book.description,
      series: book.series,
      series_number: book.series_number,
      original_title: book.original_title,
      inserted_at: book.inserted_at,
      updated_at: book.updated_at
    }
  end

  defp escape_csv_field(nil), do: ""
  defp escape_csv_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"#{String.replace(value, "\"", "\"\"")}\""
    else
      value
    end
  end
  defp escape_csv_field(value), do: to_string(value)

  defp store_and_complete_job(%Job{} = job, temp_path, filename) do
    case Storage.store_file(temp_path, "exports/#{filename}") do
      {:ok, stored_path} ->
        file_size = File.stat!(temp_path).size

        ImportExport.complete_job(job, %{
          file_path: stored_path,
          file_name: filename,
          file_size: file_size
        })

        File.rm(temp_path)
        {:ok, job}

      {:error, reason} ->
        File.rm(temp_path)
        ImportExport.fail_job(job, "Failed to store export file: #{inspect(reason)}")
    end
  end

  defp update_job_status(%Job{} = job, status) do
    ImportExport.update_job(job, %{status: status})
  end

  @doc """
  Returns available filter options for the export form.
  """
  def available_filters do
    media_types =
      from(ci in CollectionItem, select: ci.media_type, distinct: true)
      |> Repo.all()
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    genres =
      from(b in Book, select: b.genre, distinct: true, where: not is_nil(b.genre))
      |> Repo.all()
      |> Enum.reject(&(&1 == ""))
      |> Enum.sort()

    %{
      media_types: media_types,
      genres: genres,
      formats: @supported_formats
    }
  end
end