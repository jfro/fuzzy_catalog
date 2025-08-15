defmodule FuzzyCatalog.TitleUtils do
  @moduledoc """
  Utilities for working with book titles.

  Provides normalization and matching functions for book titles.
  """

  @common_postfixes [
    # Audio-specific postfixes
    "(Unabridged)",
    "(Abridged)",
    "(Audio CD)",
    "(Audiobook)",

    # Format-specific postfixes
    "(Paperback)",
    "(Hardcover)",
    "(Kindle Edition)",
    "(eBook)",
    "(Digital)",

    # Edition-specific postfixes
    "(1st Edition)",
    "(2nd Edition)",
    "(3rd Edition)",
    "(First Edition)",
    "(Second Edition)",
    "(Third Edition)",
    "(Revised Edition)",
    "(Updated Edition)",
    "(Anniversary Edition)",

    # Generic edition markers
    ~r/\(\d+(?:st|nd|rd|th) Edition\)/,
    ~r/\(.*? Edition\)/
  ]

  @doc """
  Normalizes a title by removing common postfixes that don't affect the core title.

  Removes parenthetical postfixes like "(Unabridged)", "(Paperback)", etc.
  that are often added to distinguish different formats or editions of the same book.

  ## Examples

      iex> normalize_title("The Martian (Unabridged)")
      "The Martian"
      
      iex> normalize_title("1984 (Kindle Edition)")
      "1984"
      
      iex> normalize_title("The Great Gatsby (1st Edition)")
      "The Great Gatsby"

      iex> normalize_title("Normal Title")
      "Normal Title"

  """
  def normalize_title(title) when is_binary(title) do
    title
    |> String.trim()
    |> remove_common_postfixes()
    |> String.trim()
  end

  def normalize_title(nil), do: nil

  defp remove_common_postfixes(title) do
    Enum.reduce(@common_postfixes, title, fn postfix, acc ->
      case postfix do
        %Regex{} = regex ->
          String.replace(acc, regex, "")

        string_postfix when is_binary(string_postfix) ->
          String.replace(acc, string_postfix, "")
      end
    end)
  end
end
