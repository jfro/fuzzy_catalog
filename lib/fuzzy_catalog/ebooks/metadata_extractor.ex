defmodule FuzzyCatalog.Ebooks.MetadataExtractor do
  @moduledoc """
  Extracts metadata from ebook files (EPUB, PDF) and Calibre OPF files.
  """

  require Logger

  alias FuzzyCatalog.Ebooks.OpfParser
  alias FuzzyCatalog.Ebooks.EpubParser

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

  @doc """
  Checks for and extracts metadata from a Calibre metadata.opf file
  located in the same directory as the ebook file.

  Returns {:ok, metadata} if found and parsed successfully.
  Returns {:ok, nil} if no metadata.opf file exists.
  Returns {:error, reason} if parsing fails.
  """
  def extract_opf_metadata(ebook_file_path) do
    dir = Path.dirname(ebook_file_path)
    opf_path = Path.join(dir, "metadata.opf")

    if File.exists?(opf_path) do
      OpfParser.parse_opf_file(opf_path)
    else
      {:ok, nil}
    end
  end

  @doc """
  Extracts cover.jpg from Calibre directory structure.

  Looks for cover.jpg in the same directory as the ebook file.
  Returns {:ok, binary} if found, {:error, :no_cover} if not found.
  """
  def extract_calibre_cover(ebook_file_path) do
    dir = Path.dirname(ebook_file_path)
    cover_path = Path.join(dir, "cover.jpg")

    if File.exists?(cover_path) do
      File.read(cover_path)
    else
      {:error, :no_cover}
    end
  end

  # Private functions

  defp extract_epub_metadata(file_path) do
    # Use our EpubParser which extracts OPF directly (gets all metadata including Calibre fields)
    case EpubParser.extract_metadata(file_path) do
      {:ok, metadata} ->
        # Normalize field names to match expected output
        normalized = %{
          title: metadata.title,
          author: metadata.author,
          isbn: metadata.isbn,
          publisher: metadata.publisher,
          language: metadata.language,
          description: metadata.description,
          format: metadata.format,
          # Include Calibre fields if present
          series: metadata[:series],
          series_index: metadata[:series_index],
          rating: metadata[:rating],
          tags: metadata[:tags] || [],
          custom_metadata: metadata[:custom_metadata] || %{}
        }

        {:ok, normalized}

      {:error, reason} ->
        Logger.error("EPUB parsing failed: #{reason}")
        # Pass through user-friendly errors without wrapping
        if user_friendly_error?(reason) do
          {:error, reason}
        else
          {:error, "Failed to parse EPUB: #{reason}"}
        end
    end
  end

  # Check if an error message is already user-friendly (starts with "EPUB file" or "PDF file")
  defp user_friendly_error?(message) when is_binary(message) do
    String.starts_with?(message, "EPUB file") or String.starts_with?(message, "PDF file")
  end

  defp user_friendly_error?(_), do: false

  defp extract_epub_cover(file_path) do
    # Use our EpubParser which extracts cover directly from the EPUB
    case EpubParser.extract_cover(file_path) do
      {:ok, cover_binary} ->
        {:ok, cover_binary}

      {:error, :no_cover} ->
        {:error, :no_cover}

      {:error, reason} ->
        Logger.error("Cover extraction failed: #{reason}")
        {:error, reason}
    end
  end

  defp clean_metadata_value(nil), do: nil
  defp clean_metadata_value(""), do: nil

  defp clean_metadata_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp clean_metadata_value(value), do: value

  defp safe_format_error(error) do
    if is_exception(error) do
      Exception.message(error)
    else
      inspect(error)
    end
  rescue
    _ -> inspect(error)
  end

  defp extract_pdf_metadata(file_path) do
    # Use command-line pdfinfo for better performance on large files
    # Avoids loading entire PDF into memory (which can hang on 50MB+ files)
    case System.cmd("pdfinfo", [file_path], stderr_to_stdout: true) do
      {output, 0} ->
        # Parse pdfinfo output
        info = parse_pdfinfo_output(output)

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

      {error_output, _exit_code} ->
        {:error, "Failed to extract PDF metadata: #{error_output}"}
    end
  rescue
    e ->
      Logger.error("PDF parsing exception: #{inspect(e)}")
      {:error, "Failed to parse PDF: #{safe_format_error(e)}"}
  end

  # Parse pdfinfo command output into a map
  defp parse_pdfinfo_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          Map.put(acc, String.trim(key), String.trim(value))

        _ ->
          acc
      end
    end)
  end
end
