defmodule FuzzyCatalog.Ebooks.EpubParser do
  @moduledoc """
  Efficient EPUB parser that extracts metadata and cover images.

  Uses zstream to extract only necessary files without unpacking the entire
  EPUB archive, making it memory-efficient for large files.
  """

  require Logger

  alias FuzzyCatalog.Ebooks.OpfParser

  @doc """
  Extracts metadata from an EPUB file by parsing its internal OPF.

  Returns the same metadata structure as OpfParser:
  - title, author, publisher, language, description (Dublin Core)
  - isbn, asin, goodreads_id (identifiers)
  - series, series_index, rating, tags (Calibre extensions)
  - custom_metadata (Calibre custom columns)
  """
  @spec extract_metadata(String.t()) :: {:ok, map()} | {:error, String.t()}
  def extract_metadata(epub_path) do
    with {:ok, opf_path} <- find_opf_path(epub_path),
         {:ok, opf_content} <- extract_file_content(epub_path, opf_path),
         {:ok, metadata} <- parse_opf_content(opf_content) do
      {:ok, Map.put(metadata, :format, "epub")}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts cover image binary from EPUB file.

  Looks for the cover image referenced in the OPF manifest with properties="cover-image".
  """
  @spec extract_cover(String.t()) :: {:ok, binary()} | {:error, atom() | String.t()}
  def extract_cover(epub_path) do
    with {:ok, opf_path} <- find_opf_path(epub_path),
         {:ok, opf_content} <- extract_file_content(epub_path, opf_path),
         {:ok, cover_href} <- find_cover_href(opf_content),
         opf_dir <- Path.dirname(opf_path),
         cover_path <- Path.join(opf_dir, cover_href),
         {:ok, cover_binary} <- extract_file_content(epub_path, cover_path) do
      {:ok, cover_binary}
    else
      {:error, :no_cover} -> {:error, :no_cover}
      {:error, reason} -> {:error, reason}
    end
  end

  # Find the path to the OPF file by reading META-INF/container.xml
  defp find_opf_path(epub_path) do
    container_path = "META-INF/container.xml"

    case extract_file_content(epub_path, container_path) do
      {:ok, xml_content} ->
        parse_container_xml(xml_content)

      {:error, reason} ->
        # Pass through user-friendly errors without wrapping
        if user_friendly_error?(reason) do
          {:error, reason}
        else
          {:error, "Failed to read container.xml: #{reason}"}
        end
    end
  end

  # Extract a specific file from the EPUB (ZIP) archive
  # Tries zstream first, falls back to erlang :zip for unsupported ZIP variants
  defp extract_file_content(epub_path, file_path) do
    case extract_with_zstream(epub_path, file_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, :unsupported_zip_format} ->
        # Fall back to erlang :zip for ZIP variants zstream doesn't support
        extract_with_erlang_zip(epub_path, file_path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Try extracting with zstream (preferred for most files)
  defp extract_with_zstream(epub_path, file_path) do
    try do
      result =
        epub_path
        |> File.stream!([], 2048)
        |> Zstream.unzip()
        |> Enum.reduce_while({:searching, []}, fn
          {:entry, %Zstream.Entry{name: ^file_path}}, {:searching, _} ->
            # Found the target file, start collecting its data
            {:cont, {:collecting, []}}

          {:entry, _other_entry}, state ->
            # Different file, keep searching
            {:cont, state}

          {:data, :eof}, {:collecting, chunks} ->
            # End of target file, return collected data
            {:halt, {:found, chunks}}

          {:data, chunk}, {:collecting, chunks} ->
            # Accumulate data chunks for target file
            {:cont, {:collecting, [chunk | chunks]}}

          {:data, _}, state ->
            # Data for different file, ignore
            {:cont, state}
        end)

      case result do
        {:found, chunks} ->
          # Reverse chunks (they were prepended) and join
          content = chunks |> Enum.reverse() |> IO.iodata_to_binary()
          {:ok, content}

        {:searching, _} ->
          {:error, "File not found in EPUB: #{file_path}"}

        {:collecting, _} ->
          # This shouldn't happen (file started but no EOF)
          {:error, "File not found in EPUB: #{file_path}"}
      end
    rescue
      e in [Zstream.Unzip.Error] ->
        if e.message =~ "data descriptor" do
          # zstream doesn't support data descriptor records, fall back
          Logger.debug("EPUB uses data descriptor records, falling back to erlang :zip")
          {:error, :unsupported_zip_format}
        else
          Logger.error("Unexpected zstream error: #{inspect(e)}")
          {:error, "EPUB file has corrupted ZIP structure and cannot be processed."}
        end

      _e in [MatchError] ->
        # zstream encountered a ZIP structure it doesn't understand, fall back
        Logger.debug("zstream failed to parse ZIP structure, falling back to erlang :zip")
        {:error, :unsupported_zip_format}

      e in [File.Error] ->
        {:error, "Failed to read EPUB file: #{Exception.message(e)}"}

      e ->
        Logger.error("Unexpected error extracting from EPUB: #{inspect(e)}")
        {:error, "EPUB file has corrupted ZIP structure and cannot be processed."}
    end
  end

  # Fallback using erlang :zip for ZIP variants zstream doesn't support
  defp extract_with_erlang_zip(epub_path, file_path) do
    epub_charlist = String.to_charlist(epub_path)
    file_charlist = String.to_charlist(file_path)

    try do
      case :zip.extract(epub_charlist, [{:file_list, [file_charlist]}, :memory]) do
        {:ok, [{^file_charlist, content}]} ->
          {:ok, content}

        {:ok, []} ->
          {:error, "File not found in EPUB: #{file_path}"}

        {:error, {:EXIT, {:function_clause, [{:calendar, function, _args, _} | _]}}}
        when function in [:last_day_of_the_month1, :date_to_gregorian_days] ->
          {:error,
           "EPUB file has corrupted ZIP metadata (invalid date/time values). Most ebook readers ignore this, but the file cannot be processed here."}

        {:error, {:EXIT, _reason}} ->
          {:error, "EPUB file has corrupted ZIP structure and cannot be processed."}

        {:error, reason} ->
          {:error, "ZIP extraction failed: #{inspect(reason)}"}
      end
    catch
      :exit, {:function_clause, [{:calendar, function, _args, _} | _]}
      when function in [:last_day_of_the_month1, :date_to_gregorian_days] ->
        {:error,
         "EPUB file has corrupted ZIP metadata (invalid date/time values). Most ebook readers ignore this, but the file cannot be processed here."}

      :exit, _reason ->
        {:error, "EPUB file has corrupted ZIP structure and cannot be processed."}
    end
  end

  # Parse container.xml using Saxy to find the OPF file path
  defp parse_container_xml(xml_content) do
    handler = %{opf_path: nil}

    case Saxy.parse_string(xml_content, __MODULE__.ContainerHandler, handler) do
      {:ok, %{opf_path: opf_path}} when not is_nil(opf_path) ->
        {:ok, opf_path}

      {:ok, %{opf_path: nil}} ->
        {:error, "No OPF file found in container.xml"}

      {:error, reason} ->
        Logger.error("Failed to parse container.xml: #{inspect(reason)}")
        {:error, "Failed to parse container.xml"}
    end
  end

  # Parse OPF content using OpfParser
  defp parse_opf_content(opf_binary) do
    # Write to temporary file for OpfParser (it expects a file path)
    tmp_path = Path.join(System.tmp_dir!(), "opf_#{System.unique_integer([:positive])}.opf")

    try do
      File.write!(tmp_path, opf_binary)
      OpfParser.parse_opf_file(tmp_path)
    after
      File.rm(tmp_path)
    end
  end

  # Find cover image href from OPF manifest using Saxy
  defp find_cover_href(opf_binary) do
    handler = %{cover_href: nil}

    case Saxy.parse_string(opf_binary, __MODULE__.CoverHandler, handler) do
      {:ok, %{cover_href: href}} when not is_nil(href) ->
        {:ok, href}

      {:ok, %{cover_href: nil}} ->
        {:error, :no_cover}

      {:error, _reason} ->
        {:error, :no_cover}
    end
  end

  # Check if an error message is already user-friendly (starts with "EPUB file")
  defp user_friendly_error?(message) when is_binary(message) do
    String.starts_with?(message, "EPUB file")
  end

  defp user_friendly_error?(_), do: false

  # Saxy handler for parsing container.xml
  defmodule ContainerHandler do
    @behaviour Saxy.Handler

    def handle_event(:start_element, {element_name, attributes}, state) do
      # Handle both namespaced and non-namespaced rootfile elements
      # e.g., "rootfile" or "odfc:rootfile" or {"urn:...", "rootfile"}
      is_rootfile =
        case element_name do
          "rootfile" -> true
          name when is_binary(name) -> String.ends_with?(name, ":rootfile")
          {_namespace, "rootfile"} -> true
          _ -> false
        end

      if is_rootfile do
        media_type = get_attribute(attributes, "media-type")

        if media_type == "application/oebps-package+xml" do
          opf_path = get_attribute(attributes, "full-path")
          {:ok, %{state | opf_path: opf_path}}
        else
          {:ok, state}
        end
      else
        {:ok, state}
      end
    end

    def handle_event(_event, _data, state), do: {:ok, state}

    defp get_attribute(attributes, name) do
      Enum.find_value(attributes, fn {attr_name, value} ->
        if attr_name == name, do: value
      end)
    end
  end

  # Saxy handler for finding cover image in OPF
  defmodule CoverHandler do
    @behaviour Saxy.Handler

    def handle_event(:start_element, {element_name, attributes}, state) do
      # Handle both namespaced and non-namespaced item elements
      is_item =
        case element_name do
          "item" -> true
          name when is_binary(name) -> String.ends_with?(name, ":item")
          {_namespace, "item"} -> true
          _ -> false
        end

      if is_item do
        properties = get_attribute(attributes, "properties")

        if properties == "cover-image" do
          href = get_attribute(attributes, "href")
          {:ok, %{state | cover_href: href}}
        else
          {:ok, state}
        end
      else
        {:ok, state}
      end
    end

    def handle_event(_event, _data, state), do: {:ok, state}

    defp get_attribute(attributes, name) do
      Enum.find_value(attributes, fn {attr_name, value} ->
        if attr_name == name, do: value
      end)
    end
  end
end
