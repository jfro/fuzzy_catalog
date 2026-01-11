defmodule FuzzyCatalog.Ebooks.OpfParser do
  @moduledoc """
  Parses OPF (Open Package Format) files to extract ebook metadata.

  Supports both standard Dublin Core metadata and Calibre-specific extensions.
  Uses Saxy for XML parsing.
  """

  require Logger

  @doc """
  Parses an OPF file and extracts metadata.

  Returns `{:ok, metadata}` with a map containing:
  - title, author, publisher, language, description (Dublin Core)
  - isbn, asin, goodreads_id (identifiers)
  - series, series_index, rating, tags (Calibre extensions)
  - custom_metadata (Calibre custom columns)

  Returns `{:error, reason}` if the file cannot be parsed.
  """
  @spec parse_opf_file(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_opf_file(file_path) do
    if File.exists?(file_path) do
      parse_opf_content(file_path)
    else
      {:error, "File not found: #{file_path}"}
    end
  end

  defp parse_opf_content(file_path) do
    try do
      content = File.read!(file_path)

      case Saxy.SimpleForm.parse_string(content) do
        {:ok, document} ->
          metadata = %{
            title: extract_dublin_core(document, "title"),
            author: extract_dublin_core(document, "creator"),
            publisher: extract_dublin_core(document, "publisher"),
            language: extract_dublin_core(document, "language"),
            description: extract_dublin_core(document, "description"),
            publication_date: extract_publication_date(document),
            isbn: extract_identifier(document, "ISBN"),
            asin: extract_identifier(document, "AMAZON"),
            goodreads_id: extract_identifier(document, "GOODREADS"),
            series: extract_calibre_meta(document, "calibre:series"),
            series_index: extract_series_index(document),
            rating: extract_rating(document),
            tags: extract_tags(document),
            custom_metadata: extract_custom_metadata(document)
          }

          {:ok, metadata}

        {:error, reason} ->
          Logger.error("Failed to parse OPF file #{file_path}: #{inspect(reason)}")
          {:error, "Failed to parse OPF: #{inspect(reason)}"}
      end
    rescue
      e ->
        Logger.error("Failed to parse OPF file #{file_path}: #{Exception.message(e)}")
        {:error, "Failed to parse OPF: #{Exception.message(e)}"}
    end
  end

  # Extract Dublin Core metadata element
  defp extract_dublin_core(document, field_name) do
    dc_tag = "dc:#{field_name}"

    find_in_tree(document, fn
      {tag, _attrs, content} when tag == dc_tag or tag == field_name ->
        get_text_content(content)

      _ ->
        nil
    end)
  end

  # Extract publication date and format as YYYY-MM-DD
  defp extract_publication_date(document) do
    case extract_dublin_core(document, "date") do
      nil ->
        nil

      date_str ->
        # Extract just the date portion (YYYY-MM-DD) from ISO 8601 timestamp
        case String.split(date_str, "T") do
          [date | _] -> date
          _ -> date_str
        end
    end
  end

  # Extract identifier by scheme (ISBN, AMAZON, GOODREADS, etc.)
  defp extract_identifier(document, scheme) do
    find_in_tree(document, fn
      {"dc:identifier", attrs, content} ->
        case List.keyfind(attrs, "opf:scheme", 0) || List.keyfind(attrs, "scheme", 0) do
          {_, ^scheme} -> get_text_content(content)
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  # Extract Calibre meta tag by name
  defp extract_calibre_meta(document, name) do
    find_in_tree(document, fn
      {"meta", attrs, _content} ->
        case List.keyfind(attrs, "name", 0) do
          {_, ^name} ->
            case List.keyfind(attrs, "content", 0) do
              {_, content} -> content
              _ -> nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end)
  end

  # Extract series index as Decimal
  defp extract_series_index(document) do
    case extract_calibre_meta(document, "calibre:series_index") do
      nil -> nil
      value when is_binary(value) -> Decimal.new(value)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Extract rating as integer
  defp extract_rating(document) do
    case extract_calibre_meta(document, "calibre:rating") do
      nil -> nil
      value when is_binary(value) -> String.to_integer(value)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  # Extract tags from dc:subject elements
  defp extract_tags(document) do
    collect_in_tree(document, fn
      {"dc:subject", _attrs, content} -> get_text_content(content)
      {"subject", _attrs, content} -> get_text_content(content)
      _ -> nil
    end)
  end

  # Extract Calibre custom metadata columns
  defp extract_custom_metadata(document) do
    collect_in_tree(document, fn
      {"meta", attrs, _content} ->
        case List.keyfind(attrs, "name", 0) do
          {_, name} when is_binary(name) ->
            if String.starts_with?(name, "calibre:user_metadata:") do
              case List.keyfind(attrs, "content", 0) do
                {_, content} ->
                  field_name = String.replace_prefix(name, "calibre:user_metadata:", "")
                  value = extract_custom_field_value(content)
                  {field_name, value}

                _ ->
                  nil
              end
            else
              nil
            end

          _ ->
            nil
        end

      _ ->
        nil
    end)
    |> Enum.into(%{})
  end

  # Extract value from Calibre custom field JSON format
  # Format: {"#value#": "actual value"} (may have HTML entities)
  defp extract_custom_field_value(content_str) when is_binary(content_str) do
    # Decode HTML entities first
    decoded =
      content_str
      |> String.replace("&quot;", "\"")
      |> String.replace("&amp;", "&")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")

    case Jason.decode(decoded) do
      {:ok, %{"#value#" => value}} -> value
      _ -> content_str
    end
  end

  defp extract_custom_field_value(content), do: content

  # Helper: Find first matching element in tree
  defp find_in_tree(tree, matcher_fn) do
    find_in_tree_recursive(tree, matcher_fn)
  end

  defp find_in_tree_recursive({tag, attrs, children}, matcher_fn) do
    case matcher_fn.({tag, attrs, children}) do
      nil ->
        Enum.find_value(children, fn child ->
          find_in_tree_recursive(child, matcher_fn)
        end)

      result ->
        result
    end
  end

  defp find_in_tree_recursive(_, _), do: nil

  # Helper: Collect all matching elements in tree
  defp collect_in_tree(tree, matcher_fn) do
    collect_in_tree_recursive(tree, matcher_fn, [])
    |> Enum.reverse()
  end

  defp collect_in_tree_recursive({tag, attrs, children}, matcher_fn, acc) do
    acc =
      case matcher_fn.({tag, attrs, children}) do
        nil -> acc
        result -> [result | acc]
      end

    Enum.reduce(children, acc, fn child, acc ->
      collect_in_tree_recursive(child, matcher_fn, acc)
    end)
  end

  defp collect_in_tree_recursive(_, _, acc), do: acc

  # Helper: Extract text content from element children
  defp get_text_content([text]) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp get_text_content(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp get_text_content(children) when is_list(children) do
    result =
      children
      |> Enum.map(fn
        text when is_binary(text) -> text
        {_tag, _attrs, nested_children} -> get_text_content(nested_children)
      end)
      |> Enum.join("")
      |> String.trim()

    case result do
      "" -> nil
      _ -> result
    end
  end

  defp get_text_content(_), do: nil
end
