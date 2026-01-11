defmodule FuzzyCatalog.Ebooks.OpfParserTest do
  use FuzzyCatalog.DataCase, async: true

  alias FuzzyCatalog.Ebooks.OpfParser
  alias FuzzyCatalog.EbooksFixtures

  describe "parse_opf_file/1" do
    @tag :tmp_dir
    test "parses valid OPF with basic Dublin Core metadata", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "The Name of the Wind",
          author: "Patrick Rothfuss",
          publisher: "DAW Books",
          language: "en",
          description: "A great fantasy novel"
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.title == "The Name of the Wind"
      assert metadata.author == "Patrick Rothfuss"
      assert metadata.publisher == "DAW Books"
      assert metadata.language == "en"
      assert metadata.description == "A great fantasy novel"
    end

    @tag :tmp_dir
    test "extracts identifiers (ISBN, ASIN, Goodreads)", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author",
          isbn: "9780756404079",
          asin: "B0010SKUYM",
          goodreads_id: "186074"
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.isbn == "9780756404079"
      assert metadata.asin == "B0010SKUYM"
      assert metadata.goodreads_id == "186074"
    end

    @tag :tmp_dir
    test "extracts Calibre series metadata", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "The Name of the Wind",
          author: "Patrick Rothfuss",
          series: "The Kingkiller Chronicle",
          series_index: "1.0"
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.series == "The Kingkiller Chronicle"
      assert Decimal.equal?(metadata.series_index, Decimal.new("1.0"))
    end

    @tag :tmp_dir
    test "extracts Calibre rating", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author",
          rating: 10
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.rating == 10
    end

    @tag :tmp_dir
    test "extracts tags from dc:subject elements", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author",
          tags: ["Fantasy", "Epic Fantasy", "Adventure"]
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.tags == ["Fantasy", "Epic Fantasy", "Adventure"]
    end

    @tag :tmp_dir
    test "extracts custom Calibre columns", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author",
          custom: %{
            "#genre" => "Epic Fantasy",
            "#read_date" => "2024-01-15"
          }
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.custom_metadata["#genre"] == "Epic Fantasy"
      assert metadata.custom_metadata["#read_date"] == "2024-01-15"
    end

    @tag :tmp_dir
    test "handles missing optional fields gracefully", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      # Minimal OPF with only required fields
      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author"
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.title == "Test Book"
      assert metadata.author == "Test Author"
      assert is_nil(metadata.series)
      assert is_nil(metadata.series_index)
      assert is_nil(metadata.rating)
      assert is_nil(metadata.isbn)
      assert metadata.tags == []
      assert metadata.custom_metadata == %{}
    end

    @tag :tmp_dir
    test "returns error for malformed XML", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")
      File.write!(opf_path, "not valid xml <<>>")

      assert {:error, reason} = OpfParser.parse_opf_file(opf_path)
      assert reason =~ "Failed to parse OPF"
    end

    @tag :tmp_dir
    test "returns error for missing file", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "nonexistent.opf")

      assert {:error, reason} = OpfParser.parse_opf_file(opf_path)
      assert reason =~ "File not found"
    end

    @tag :tmp_dir
    test "handles series_index as decimal", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author",
          series: "Test Series",
          series_index: "1.5"
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert Decimal.equal?(metadata.series_index, Decimal.new("1.5"))
    end

    @tag :tmp_dir
    test "extracts publication date", %{tmp_dir: tmp_dir} do
      opf_path = Path.join(tmp_dir, "metadata.opf")

      content =
        EbooksFixtures.create_calibre_opf_content(%{
          title: "Test Book",
          author: "Test Author",
          publication_date: "2007-03-27T00:00:00+00:00"
        })

      File.write!(opf_path, content)

      assert {:ok, metadata} = OpfParser.parse_opf_file(opf_path)
      assert metadata.publication_date == "2007-03-27"
    end
  end
end
