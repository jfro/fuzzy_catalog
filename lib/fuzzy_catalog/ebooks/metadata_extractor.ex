defmodule FuzzyCatalog.Ebooks.MetadataExtractor do
  @moduledoc """
  Extracts metadata from ebook files (EPUB, PDF).
  """

  require Logger

  @doc """
  Extracts metadata from an ebook file.

  Returns {:ok, metadata_map} or {:error, reason}

  Metadata map includes:
  - title: Book title
  - author: Author name
  - isbn: ISBN identifier
  - publisher: Publisher name
  - language: Language code
  - description: Book description
  - format: File format ("epub" or "pdf")
  """
  def extract(file_path) do
    unless File.exists?(file_path) do
      {:error, "file not found: #{file_path}"}
    else
      cond do
        String.ends_with?(file_path, ".epub") ->
          extract_epub_metadata(file_path)

        String.ends_with?(file_path, ".pdf") ->
          extract_pdf_metadata(file_path)

        true ->
          {:error, "Unsupported file format"}
      end
    end
  end

  @doc """
  Extracts cover image binary from ebook file.

  Returns {:ok, binary} or {:error, reason}
  """
  def extract_cover(file_path) do
    unless File.exists?(file_path) do
      {:error, "file not found: #{file_path}"}
    else
      cond do
        String.ends_with?(file_path, ".epub") ->
          extract_epub_cover(file_path)

        String.ends_with?(file_path, ".pdf") ->
          {:error, :not_implemented}

        true ->
          {:error, "Unsupported file format"}
      end
    end
  end

  # Private functions

  defp extract_epub_metadata(file_path) do
    epub = BUPE.parse(file_path)

    metadata = %{
      title: clean_metadata_value(epub.title),
      author: clean_metadata_value(epub.creator),
      isbn: clean_metadata_value(epub.identifier),
      publisher: clean_metadata_value(epub.publisher),
      language: clean_metadata_value(epub.language),
      description: clean_metadata_value(epub.description),
      format: "epub"
    }

    {:ok, metadata}
  rescue
    e ->
      error_msg = safe_format_error(e)
      Logger.error("EPUB parsing exception: #{inspect(e)}")
      {:error, "Failed to parse EPUB: #{error_msg}"}
  end

  defp safe_format_error(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  rescue
    _ -> inspect(error)
  end

  defp clean_metadata_value(nil), do: nil
  defp clean_metadata_value(""), do: nil

  defp clean_metadata_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp clean_metadata_value(value), do: value

  defp extract_epub_cover(file_path) do
    epub = BUPE.parse(file_path)

    # BUPE stores cover in the images list with properties="cover-image"
    cover_item =
      Enum.find(epub.images, fn item ->
        item.properties == "cover-image"
      end)

    case cover_item do
      nil ->
        {:error, :no_cover}

      item ->
        # BUPE already loaded the content for us
        {:ok, item.content}
    end
  rescue
    e ->
      Logger.error("Cover extraction exception: #{inspect(e)}")
      {:error, "Failed to extract cover: #{safe_format_error(e)}"}
  end

  defp extract_pdf_metadata(file_path) do
    case File.read(file_path) do
      {:ok, binary} ->
        info_objects = PDFInfo.info_objects(binary)

        # info_objects returns a map like %{"/Info 4 0 R" => [%{"Title" => "...", "Author" => "..."}]}
        # Get the first info object from the map
        info =
          info_objects
          |> Map.values()
          |> List.flatten()
          |> List.first()
          |> case do
            nil -> %{}
            obj -> obj
          end

        metadata = %{
          title: clean_metadata_value(Map.get(info, "Title")),
          author: clean_metadata_value(Map.get(info, "Author")),
          publisher: clean_metadata_value(Map.get(info, "Producer")),
          format: "pdf",
          # PDFs rarely have ISBNs in metadata
          isbn: nil,
          language: nil,
          description: nil
        }

        {:ok, metadata}

      {:error, reason} ->
        {:error, "Failed to read PDF: #{inspect(reason)}"}
    end
  rescue
    e ->
      Logger.error("PDF parsing exception: #{inspect(e)}")
      {:error, "Failed to parse PDF: #{safe_format_error(e)}"}
  end
end
