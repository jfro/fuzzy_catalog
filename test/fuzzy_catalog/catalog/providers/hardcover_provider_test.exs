defmodule FuzzyCatalog.Catalog.Providers.HardcoverProviderTest do
  use ExUnit.Case, async: true

  alias FuzzyCatalog.Catalog.Providers.HardcoverProvider

  describe "map_edition_format_to_media_types/1" do
    test "returns empty list for nil" do
      assert [] == HardcoverProvider.__map_edition_format_to_media_types__(nil)
    end

    test "returns empty list for empty string" do
      assert [] == HardcoverProvider.__map_edition_format_to_media_types__("")
    end

    test "maps hardcover format" do
      assert ["hardcover"] == HardcoverProvider.__map_edition_format_to_media_types__("Hardcover")
      assert ["hardcover"] == HardcoverProvider.__map_edition_format_to_media_types__("hardcover")
      assert ["hardcover"] == HardcoverProvider.__map_edition_format_to_media_types__("HARDCOVER")
    end

    test "maps paperback format" do
      assert ["paperback"] == HardcoverProvider.__map_edition_format_to_media_types__("Paperback")
      assert ["paperback"] == HardcoverProvider.__map_edition_format_to_media_types__("paperback")
      assert ["paperback"] == HardcoverProvider.__map_edition_format_to_media_types__("PAPERBACK")
    end

    test "maps audiobook format" do
      assert ["audiobook"] == HardcoverProvider.__map_edition_format_to_media_types__("Audiobook")
      assert ["audiobook"] == HardcoverProvider.__map_edition_format_to_media_types__("audiobook")
      assert ["audiobook"] == HardcoverProvider.__map_edition_format_to_media_types__("Audio")
      assert ["audiobook"] == HardcoverProvider.__map_edition_format_to_media_types__("audio")
    end

    test "maps ebook format" do
      assert ["ebook"] == HardcoverProvider.__map_edition_format_to_media_types__("ebook")
      assert ["ebook"] == HardcoverProvider.__map_edition_format_to_media_types__("Ebook")
      assert ["ebook"] == HardcoverProvider.__map_edition_format_to_media_types__("Digital")
      assert ["ebook"] == HardcoverProvider.__map_edition_format_to_media_types__("digital")
    end

    test "maps paperback variations" do
      assert ["paperback"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Mass Market Paperback")

      assert ["paperback"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Trade Paperback")
    end

    test "maps hardcover variations" do
      assert ["hardcover"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Board Book")

      assert ["hardcover"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Library Binding")
    end

    test "maps Kindle formats to ebook" do
      assert ["ebook"] == HardcoverProvider.__map_edition_format_to_media_types__("Kindle")

      assert ["ebook"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Kindle Edition")
    end

    test "maps audio formats to audiobook" do
      assert ["audiobook"] == HardcoverProvider.__map_edition_format_to_media_types__("Audio CD")

      assert ["audiobook"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Audio Download")

      assert ["audiobook"] == HardcoverProvider.__map_edition_format_to_media_types__("MP3 CD")
    end

    test "returns empty list for unknown formats" do
      assert [] ==
               HardcoverProvider.__map_edition_format_to_media_types__("Unknown Format Type")

      assert [] == HardcoverProvider.__map_edition_format_to_media_types__("Something Else")
    end

    test "handles whitespace in format strings" do
      assert ["hardcover"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("  Hardcover  ")

      assert ["paperback"] ==
               HardcoverProvider.__map_edition_format_to_media_types__("  Paperback  ")
    end
  end

  describe "extract_from_cached/1" do
    test "returns nil for nil input" do
      assert nil == HardcoverProvider.__extract_from_cached__(nil)
    end

    test "parses valid JSON string" do
      json = Jason.encode!(%{"name" => "Test", "value" => 123})

      assert %{"name" => "Test", "value" => 123} ==
               HardcoverProvider.__extract_from_cached__(json)
    end

    test "returns nil for invalid JSON string" do
      assert nil == HardcoverProvider.__extract_from_cached__("not valid json")
    end

    test "passes through map unchanged" do
      data = %{"test" => "data"}
      assert data == HardcoverProvider.__extract_from_cached__(data)
    end

    test "passes through list unchanged" do
      data = ["item1", "item2"]
      assert data == HardcoverProvider.__extract_from_cached__(data)
    end
  end

  describe "format_contributors/1" do
    test "returns default for nil" do
      assert "Unknown Author" == HardcoverProvider.__format_contributors__(nil)
    end

    test "returns default for empty list" do
      assert "Unknown Author" == HardcoverProvider.__format_contributors__([])
    end

    test "formats single contributor with name key" do
      contributors = [%{"name" => "John Doe"}]
      assert "John Doe" == HardcoverProvider.__format_contributors__(contributors)
    end

    test "formats multiple contributors with name keys" do
      contributors = [%{"name" => "John Doe"}, %{"name" => "Jane Smith"}]
      assert "John Doe, Jane Smith" == HardcoverProvider.__format_contributors__(contributors)
    end

    test "formats string contributors" do
      contributors = ["John Doe", "Jane Smith"]
      assert "John Doe, Jane Smith" == HardcoverProvider.__format_contributors__(contributors)
    end

    test "filters out nil values" do
      contributors = [%{"name" => "John Doe"}, nil, %{"name" => "Jane Smith"}]
      assert "John Doe, Jane Smith" == HardcoverProvider.__format_contributors__(contributors)
    end

    test "returns default when all values are nil" do
      contributors = [nil, nil]
      assert "Unknown Author" == HardcoverProvider.__format_contributors__(contributors)
    end
  end

  describe "format_genres/1" do
    test "returns nil for nil input" do
      assert nil == HardcoverProvider.__format_genres__(nil)
    end

    test "returns nil for empty list" do
      assert nil == HardcoverProvider.__format_genres__([])
    end

    test "formats single genre with name key" do
      genres = [%{"name" => "Fantasy"}]
      assert "Fantasy" == HardcoverProvider.__format_genres__(genres)
    end

    test "formats multiple genres" do
      genres = [%{"name" => "Fantasy"}, %{"name" => "Adventure"}, %{"name" => "Fiction"}]
      assert "Fantasy, Adventure, Fiction" == HardcoverProvider.__format_genres__(genres)
    end

    test "limits to 3 genres" do
      genres = [
        %{"name" => "Fantasy"},
        %{"name" => "Adventure"},
        %{"name" => "Fiction"},
        %{"name" => "Epic"}
      ]

      assert "Fantasy, Adventure, Fiction" == HardcoverProvider.__format_genres__(genres)
    end

    test "formats string genres" do
      genres = ["Fantasy", "Adventure"]
      assert "Fantasy, Adventure" == HardcoverProvider.__format_genres__(genres)
    end

    test "filters out nil values" do
      genres = [%{"name" => "Fantasy"}, nil, %{"name" => "Adventure"}]
      assert "Fantasy, Adventure" == HardcoverProvider.__format_genres__(genres)
    end

    test "returns nil when all values are nil" do
      genres = [nil, nil]
      assert nil == HardcoverProvider.__format_genres__(genres)
    end
  end

  describe "format_series/1" do
    test "returns nil for nil input" do
      assert nil == HardcoverProvider.__format_series__(nil)
    end

    test "returns nil for empty list" do
      assert nil == HardcoverProvider.__format_series__([])
    end

    test "extracts first series name from nested structure" do
      series = [%{"series" => %{"name" => "The Stormlight Archive"}}]
      assert "The Stormlight Archive" == HardcoverProvider.__format_series__(series)
    end

    test "extracts first series name when multiple exist" do
      series = [
        %{"series" => %{"name" => "The Stormlight Archive"}},
        %{"series" => %{"name" => "Another Series"}}
      ]

      assert "The Stormlight Archive" == HardcoverProvider.__format_series__(series)
    end

    test "handles malformed series data gracefully" do
      series = [%{"name" => "The Stormlight Archive"}]
      assert nil == HardcoverProvider.__format_series__(series)
    end

    test "returns nil for unexpected format" do
      assert nil == HardcoverProvider.__format_series__([123, 456])
    end
  end
end
