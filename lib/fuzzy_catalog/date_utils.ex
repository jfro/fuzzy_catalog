defmodule FuzzyCatalog.DateUtils do
  @moduledoc """
  Centralized utilities for parsing and handling dates in various formats,
  particularly for converting them to ISO 8601 partial date strings.

  This module handles date parsing from multiple sources including:
  - External book providers (Google Books, Open Library, etc.)
  - User input in forms
  - Various date string formats

  All functions return ISO 8601 partial date strings like:
  - "2023" (year only)
  - "2023-05" (year-month)
  - "2023-05-15" (full date)
  """

  @doc """
  Parse a date string from any source into an ISO 8601 partial date string.

  This is the main entry point for date parsing and handles:
  - Full ISO dates: "2023-05-15" -> "2023-05-15"
  - Year only: "2023" -> "2023"
  - Year from regex extraction: "Published in 2023" -> "2023"
  - Slash separated: "2023/05/15" -> "2023-05-15"
  - Integer years: 2023 -> "2023"

  ## Examples

      iex> FuzzyCatalog.DateUtils.parse_date("2023-05-15")
      "2023-05-15"
      
      iex> FuzzyCatalog.DateUtils.parse_date("2023")
      "2023"
      
      iex> FuzzyCatalog.DateUtils.parse_date("Published in 2023")
      "2023"
      
      iex> FuzzyCatalog.DateUtils.parse_date(nil)
      nil
  """
  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(year) when is_integer(year) do
    current_year = Date.utc_today().year

    if year >= 1000 and year <= current_year + 10 do
      String.pad_leading(to_string(year), 4, "0")
    else
      nil
    end
  end

  def parse_date(date_string) when is_binary(date_string) do
    trimmed = String.trim(date_string)

    cond do
      # Try parsing as full ISO 8601 date first
      match?({:ok, _}, Date.from_iso8601(trimmed)) ->
        case Date.from_iso8601(trimmed) do
          {:ok, %Date{year: year, month: month, day: day}} ->
            current_year = Date.utc_today().year

            if year >= 1000 and year <= current_year + 10 do
              # Return full ISO date string
              year_str = String.pad_leading(to_string(year), 4, "0")
              month_str = String.pad_leading(to_string(month), 2, "0")
              day_str = String.pad_leading(to_string(day), 2, "0")
              "#{year_str}-#{month_str}-#{day_str}"
            else
              nil
            end
        end

      # Check if it's already a partial ISO date (YYYY or YYYY-MM)
      Regex.match?(~r/^\d{4}(-\d{2})?$/, trimmed) ->
        case validate_partial_iso_date(trimmed) do
          {:ok, validated_date} -> validated_date
          :error -> parse_date_fallback(trimmed)
        end

      # Try parsing as slash-separated date (YYYY/MM/DD, YYYY/MM)
      Regex.match?(~r/^\d{4}(\/\d{1,2}(\/\d{1,2})?)?$/, trimmed) ->
        convert_slash_date_to_iso(trimmed)

      # Extract year from text (e.g., "Published in 2023", "2023 edition")
      true ->
        parse_year_from_text(trimmed)
    end
  end

  def parse_date(_), do: nil

  @doc """
  Parse flexible date input, particularly useful for user form input.
  This handles a wide variety of input formats and is more lenient.
  """
  def parse_flexible_date_input(input) do
    parse_date(input)
  end

  @doc """
  Parse publication dates specifically from Calibre database.
  Calibre stores dates as ISO strings, sometimes with timezone info.
  """
  def parse_calibre_date(nil), do: nil
  def parse_calibre_date(""), do: nil

  def parse_calibre_date(pubdate) when is_binary(pubdate) do
    # Calibre stores dates as ISO strings, sometimes with timezone
    # Extract just the date part (first 10 characters)
    iso_date_part = String.slice(pubdate, 0, 10)
    parse_date(iso_date_part)
  end

  def parse_calibre_date(_), do: nil

  @doc """
  Parse year values from Audiobookshelf metadata.
  Handles both integer and string year values with appropriate logging.
  """
  def parse_audiobookshelf_year(nil), do: nil

  def parse_audiobookshelf_year(year) when is_integer(year) and year > 0 do
    parse_date(year)
  end

  def parse_audiobookshelf_year(year_str) when is_binary(year_str) do
    case String.trim(year_str) |> Integer.parse() do
      {year, _} when year > 0 ->
        current_year = Date.utc_today().year

        if year <= current_year + 10 do
          parse_date(year)
        else
          require Logger
          Logger.warning("publishedYear too far in future in Audiobookshelf: #{year}")
          nil
        end

      _ ->
        require Logger
        Logger.warning("Invalid publishedYear format in Audiobookshelf: #{inspect(year_str)}")
        nil
    end
  end

  def parse_audiobookshelf_year(other) do
    require Logger
    Logger.debug("No valid publishedYear found in Audiobookshelf metadata: #{inspect(other)}")
    nil
  end

  # Private helper functions

  defp validate_partial_iso_date(date_string) do
    current_year = Date.utc_today().year

    case String.split(date_string, "-") do
      # Year only: "2023"
      [year_str] when byte_size(year_str) == 4 ->
        case Integer.parse(year_str) do
          {year, ""} when year >= 1000 and year <= current_year + 10 ->
            {:ok, date_string}

          _ ->
            :error
        end

      # Year-month: "2023-05"
      [year_str, month_str] when byte_size(year_str) == 4 and byte_size(month_str) == 2 ->
        with {year, ""} <- Integer.parse(year_str),
             {month, ""} <- Integer.parse(month_str),
             true <- year >= 1000 and year <= current_year + 10,
             true <- month >= 1 and month <= 12 do
          {:ok, date_string}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp convert_slash_date_to_iso(date_string) do
    date_string
    |> String.replace("/", "-")
    |> ensure_two_digit_components()
    |> parse_date()
  end

  defp ensure_two_digit_components(date_string) do
    case String.split(date_string, "-") do
      [year] ->
        year

      [year, month] ->
        "#{year}-#{String.pad_leading(month, 2, "0")}"

      [year, month, day] ->
        "#{year}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}"

      _ ->
        date_string
    end
  end

  defp parse_year_from_text(text) do
    case Regex.run(~r/\b(\d{4})\b/, text) do
      [_, year] ->
        case Integer.parse(year) do
          {year_int, _} -> parse_date(year_int)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_date_fallback(date_string) do
    # Last resort: try to extract year from the string
    parse_year_from_text(date_string)
  end
end
