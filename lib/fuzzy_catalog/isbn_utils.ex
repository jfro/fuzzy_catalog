defmodule FuzzyCatalog.IsbnUtils do
  @moduledoc """
  Utilities for working with ISBN and ASIN identifiers.

  Provides validation, normalization, and parsing functions for book identifiers.
  """

  @doc """
  Normalizes and validates an ISBN string for a specific format.

  Removes non-alphanumeric characters and validates format.

  ## Examples

      iex> normalize_isbn("978-0-123456-78-9", 13)
      "9780123456789"
      
      iex> normalize_isbn("0-123456-78-X", 10)
      "012345678X"
      
      iex> normalize_isbn("invalid", 10)
      nil
      
  """
  def normalize_isbn(value, expected_length) when is_binary(value) do
    # Remove any non-alphanumeric characters
    cleaned = String.replace(value, ~r/[^0-9X]/i, "")

    # Check if it matches the expected ISBN format
    case String.length(cleaned) do
      ^expected_length when expected_length == 10 ->
        if valid_isbn10?(cleaned), do: cleaned, else: nil

      ^expected_length when expected_length == 13 ->
        if valid_isbn13?(cleaned), do: cleaned, else: nil

      _ ->
        nil
    end
  end

  def normalize_isbn(_, _), do: nil

  @doc """
  Validates an ISBN-10 format.

  ## Examples

      iex> valid_isbn10?("0123456789")
      true
      
      iex> valid_isbn10?("012345678X")
      true
      
      iex> valid_isbn10?("invalid")
      false
      
  """
  def valid_isbn10?(isbn) when byte_size(isbn) == 10 do
    # Basic ISBN-10 validation - all digits except last char can be X
    String.match?(isbn, ~r/^\d{9}[\dX]$/i)
  end

  def valid_isbn10?(_), do: false

  @doc """
  Validates an ISBN-13 format.

  ## Examples

      iex> valid_isbn13?("9780123456789")
      true
      
      iex> valid_isbn13?("9790123456789")
      true
      
      iex> valid_isbn13?("1234567890123")
      false
      
  """
  def valid_isbn13?(isbn) when byte_size(isbn) == 13 do
    # Basic ISBN-13 validation - all digits, starts with 978 or 979
    String.match?(isbn, ~r/^97[89]\d{10}$/)
  end

  def valid_isbn13?(_), do: false

  @doc """
  Validates an Amazon ASIN format.

  ASINs are typically 10 characters, alphanumeric, and not valid ISBNs.

  ## Examples

      iex> valid_asin?("B01234567X")
      true
      
      iex> valid_asin?("1234567890")
      false  # This could be an ISBN-10
      
      iex> valid_asin?("invalid")
      false
      
  """
  def valid_asin?(value) when is_binary(value) do
    # ASIN is typically 10 characters, alphanumeric, often starts with B for books
    cleaned = String.replace(value, ~r/[^A-Z0-9]/i, "")

    String.length(cleaned) == 10 and
      String.match?(cleaned, ~r/^[A-Z0-9]{10}$/i) and
      not valid_isbn10?(cleaned)
  end

  def valid_asin?(_), do: false

  @doc """
  Parses and separates ISBN and ASIN data from mixed identifier fields.

  Takes a map with potential isbn10, isbn13, and asin fields and returns
  normalized and validated values.

  ## Examples

      iex> parse_identifiers(%{isbn10: "012345678X", isbn13: nil, asin: "B01234567X"})
      {"012345678X", nil, "B01234567X"}
      
      iex> parse_identifiers(%{isbn10: nil, isbn13: "B01234567X", asin: nil})
      {nil, nil, "B01234567X"}
      
  """
  def parse_identifiers(data) when is_map(data) do
    isbn10 = normalize_isbn(data[:isbn10] || data["isbn10"], 10)
    isbn13 = normalize_isbn(data[:isbn13] || data["isbn13"], 13)

    # Check for ASIN - prefer direct asin field, then check isbn fields for misplaced ASINs
    asin =
      cond do
        # Direct ASIN field
        valid_asin?(data[:asin] || data["asin"]) ->
          data[:asin] || data["asin"]

        # Check if ISBN fields contain ASINs
        is_nil(isbn10) and valid_asin?(data[:isbn10] || data["isbn10"]) ->
          data[:isbn10] || data["isbn10"]

        is_nil(isbn13) and valid_asin?(data[:isbn13] || data["isbn13"]) ->
          data[:isbn13] || data["isbn13"]

        true ->
          nil
      end

    {isbn10, isbn13, asin}
  end

  @doc """
  Finds ASIN values that may be misplaced in ISBN fields.

  Useful for legacy data where ASINs were incorrectly stored as ISBNs.

  ## Examples

      iex> find_asin_in_isbn_fields(%{isbn10: "B01234567X", isbn13: "9780123456789"})
      "B01234567X"
      
      iex> find_asin_in_isbn_fields(%{isbn10: "0123456789", isbn13: "9780123456789"})
      nil
      
  """
  def find_asin_in_isbn_fields(data) when is_map(data) do
    candidates = [
      data[:isbn10] || data["isbn10"],
      data[:isbn13] || data["isbn13"]
    ]

    Enum.find_value(candidates, fn value ->
      if valid_asin?(value), do: value, else: nil
    end)
  end
end
