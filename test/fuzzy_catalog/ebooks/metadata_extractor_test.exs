defmodule FuzzyCatalog.Ebooks.MetadataExtractorTest do
  use FuzzyCatalog.DataCase, async: true

  import ExUnit.CaptureLog

  alias FuzzyCatalog.Ebooks.MetadataExtractor
  alias FuzzyCatalog.EbooksFixtures

  describe "extract/1 for EPUB files" do
    @tag :tmp_dir
    test "extracts metadata from valid EPUB file", %{tmp_dir: tmp_dir} do
      # Create a minimal valid EPUB for testing
      epub_path = Path.join(tmp_dir, "test.epub")

      create_test_epub(epub_path, %{
        title: "Test Book",
        creator: "Test Author",
        isbn: "9780123456789"
      })

      assert {:ok, metadata} = MetadataExtractor.extract(epub_path)
      assert metadata.title == "Test Book"
      assert metadata.author == "Test Author"
      assert metadata.isbn == "9780123456789"
      assert metadata.format == "epub"
    end

    @tag :tmp_dir
    test "handles EPUB without metadata", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "no_metadata.epub")
      create_test_epub(epub_path, %{})

      assert {:ok, metadata} = MetadataExtractor.extract(epub_path)
      assert is_nil(metadata.title)
      assert is_nil(metadata.author)
    end

    @tag :tmp_dir
    test "handles container.xml with namespaced elements", %{tmp_dir: tmp_dir} do
      # Test EPUB with odfc:rootfile instead of rootfile (like some Calibre EPUBs)
      epub_path = Path.join(tmp_dir, "namespaced.epub")

      create_test_epub_with_namespaced_container(epub_path, %{
        title: "Namespaced Test",
        creator: "Test Author"
      })

      assert {:ok, metadata} = MetadataExtractor.extract(epub_path)
      assert metadata.title == "Namespaced Test"
      assert metadata.author == "Test Author"
    end

    test "returns error for non-existent file" do
      assert {:error, reason} = MetadataExtractor.extract("/nonexistent.epub")
      assert reason =~ "file not found"
    end

    @tag :tmp_dir
    test "returns error for corrupted EPUB", %{tmp_dir: tmp_dir} do
      # Create an invalid file
      path = Path.join(tmp_dir, "corrupt.epub")
      File.write!(path, "not a valid epub")

      # Capture expected error log from attempting to parse invalid EPUB
      capture_log(fn ->
        assert {:error, reason} = MetadataExtractor.extract(path)
        assert reason =~ "corrupted ZIP structure"
      end)
    end
  end

  describe "extract/1 for PDF files" do
    @tag :tmp_dir
    test "extracts metadata from valid PDF file", %{tmp_dir: tmp_dir} do
      pdf_path = Path.join(tmp_dir, "test.pdf")

      create_test_pdf(pdf_path, %{
        title: "PDF Book",
        author: "PDF Author"
      })

      assert {:ok, metadata} = MetadataExtractor.extract(pdf_path)
      assert metadata.title == "PDF Book"
      assert metadata.author == "PDF Author"
      assert metadata.format == "pdf"
    end
  end

  describe "extract_cover/1" do
    @tag :tmp_dir
    test "extracts cover image from EPUB", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "with_cover.epub")
      create_test_epub_with_cover(epub_path)

      assert {:ok, cover_binary} = MetadataExtractor.extract_cover(epub_path)
      assert is_binary(cover_binary)
      assert byte_size(cover_binary) > 0
    end

    @tag :tmp_dir
    test "returns error when no cover exists", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "no_cover.epub")
      create_test_epub(epub_path, %{})

      assert {:error, :no_cover} = MetadataExtractor.extract_cover(epub_path)
    end
  end

  describe "extract_opf_metadata/1" do
    @tag :tmp_dir
    test "extracts metadata from standalone metadata.opf file", %{tmp_dir: tmp_dir} do
      paths =
        EbooksFixtures.create_calibre_directory_structure(tmp_dir, %{
          title: "The Name of the Wind",
          author: "Patrick Rothfuss",
          isbn: "9780756404079",
          series: "The Kingkiller Chronicle",
          series_index: "1.0",
          rating: 10,
          tags: ["Fantasy", "Epic Fantasy"]
        })

      assert {:ok, metadata} = MetadataExtractor.extract_opf_metadata(paths.epub_path)
      assert metadata.title == "The Name of the Wind"
      assert metadata.author == "Patrick Rothfuss"
      assert metadata.isbn == "9780756404079"
      assert metadata.series == "The Kingkiller Chronicle"
      assert Decimal.equal?(metadata.series_index, Decimal.new("1.0"))
      assert metadata.rating == 10
      assert metadata.tags == ["Fantasy", "Epic Fantasy"]
    end

    @tag :tmp_dir
    test "returns {:ok, nil} when no metadata.opf exists", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "test.epub")
      create_test_epub(epub_path, %{})

      assert {:ok, nil} = MetadataExtractor.extract_opf_metadata(epub_path)
    end

    @tag :tmp_dir
    test "handles corrupted metadata.opf gracefully", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "test.epub")
      create_test_epub(epub_path, %{})

      # Create corrupted metadata.opf in same directory
      opf_path = Path.join(tmp_dir, "metadata.opf")
      File.write!(opf_path, "not valid xml")

      capture_log(fn ->
        assert {:error, _reason} = MetadataExtractor.extract_opf_metadata(epub_path)
      end)
    end
  end

  describe "extract_calibre_cover/1" do
    @tag :tmp_dir
    test "extracts cover.jpg from Calibre directory", %{tmp_dir: tmp_dir} do
      paths =
        EbooksFixtures.create_calibre_directory_structure(tmp_dir, %{
          title: "Test Book",
          with_cover: true
        })

      assert {:ok, cover_binary} = MetadataExtractor.extract_calibre_cover(paths.epub_path)
      assert is_binary(cover_binary)
      assert byte_size(cover_binary) > 0
    end

    @tag :tmp_dir
    test "returns {:error, :no_cover} when cover.jpg doesn't exist", %{tmp_dir: tmp_dir} do
      paths =
        EbooksFixtures.create_calibre_directory_structure(tmp_dir, %{
          title: "Test Book"
        })

      assert {:error, :no_cover} = MetadataExtractor.extract_calibre_cover(paths.epub_path)
    end
  end

  # Test helper functions
  defp create_test_epub(path, metadata) do
    # Create a minimal valid EPUB structure
    # EPUBs are ZIP files with specific structure
    files = [
      # mimetype must be first and uncompressed
      {~c"mimetype", "application/epub+zip"},
      # META-INF/container.xml
      {~c"META-INF/container.xml", container_xml()},
      # OEBPS/content.opf with metadata
      {~c"OEBPS/content.opf", content_opf(metadata)},
      # OEBPS/toc.ncx
      {~c"OEBPS/toc.ncx", toc_ncx(metadata)}
    ]

    # Create ZIP file (EPUB is just a ZIP with specific structure)
    {:ok, {~c"memory", zip_data}} = :zip.create(~c"memory", files, [:memory])
    File.write!(path, zip_data)
  end

  defp create_test_epub_with_namespaced_container(path, metadata) do
    # Create EPUB with namespaced container.xml (like some Calibre EPUBs)
    files = [
      {~c"mimetype", "application/epub+zip"},
      {~c"META-INF/container.xml", namespaced_container_xml()},
      {~c"OEBPS/content.opf", content_opf(metadata)},
      {~c"OEBPS/toc.ncx", toc_ncx(metadata)}
    ]

    {:ok, {~c"memory", zip_data}} = :zip.create(~c"memory", files, [:memory])
    File.write!(path, zip_data)
  end

  defp create_test_epub_with_cover(path) do
    # Create a 1x1 PNG image (minimal valid PNG)
    png_data = create_minimal_png()

    files = [
      {~c"mimetype", "application/epub+zip"},
      {~c"META-INF/container.xml", container_xml()},
      {~c"OEBPS/content.opf", content_opf_with_cover(%{title: "Book with Cover"})},
      {~c"OEBPS/toc.ncx", toc_ncx(%{title: "Book with Cover"})},
      {~c"OEBPS/cover.png", png_data}
    ]

    {:ok, {~c"memory", zip_data}} = :zip.create(~c"memory", files, [:memory])
    File.write!(path, zip_data)
  end

  defp create_test_pdf(path, metadata) do
    # Create minimal valid PDF with metadata
    title = Map.get(metadata, :title, "")
    author = Map.get(metadata, :author, "")

    pdf_content = """
    %PDF-1.4
    1 0 obj
    <<
    /Type /Catalog
    /Pages 2 0 R
    >>
    endobj
    2 0 obj
    <<
    /Type /Pages
    /Kids [3 0 R]
    /Count 1
    >>
    endobj
    3 0 obj
    <<
    /Type /Page
    /Parent 2 0 R
    /Resources <<
    /Font <<
    /F1 <<
    /Type /Font
    /Subtype /Type1
    /BaseFont /Helvetica
    >>
    >>
    >>
    /MediaBox [0 0 612 792]
    >>
    endobj
    4 0 obj
    <<
    /Title (#{title})
    /Author (#{author})
    >>
    endobj
    xref
    0 5
    0000000000 65535 f
    0000000009 00000 n
    0000000058 00000 n
    0000000115 00000 n
    0000000274 00000 n
    trailer
    <<
    /Size 5
    /Root 1 0 R
    /Info 4 0 R
    >>
    startxref
    340
    %%EOF
    """

    File.write!(path, pdf_content)
  end

  # EPUB file content helpers
  defp container_xml do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """
  end

  defp namespaced_container_xml do
    # Container.xml with explicit namespace prefix (like some Calibre EPUBs)
    """
    <?xml version="1.0" encoding="utf-8" standalone="no"?>
    <odfc:container xmlns:odfc="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
      <odfc:rootfiles>
        <odfc:rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </odfc:rootfiles>
    </odfc:container>
    """
  end

  defp content_opf(metadata) do
    title = Map.get(metadata, :title, "")
    creator = Map.get(metadata, :creator, "")
    isbn = Map.get(metadata, :isbn, "")

    identifier_elem =
      if isbn != "" do
        ~s(<dc:identifier id="isbn" opf:scheme="ISBN">#{isbn}</dc:identifier>)
      else
        ~s(<dc:identifier id="bookid">urn:uuid:12345</dc:identifier>)
      end

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
      <metadata>
        <dc:title>#{title}</dc:title>
        <dc:creator>#{creator}</dc:creator>
        #{identifier_elem}
        <dc:language>en</dc:language>
      </metadata>
      <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
      </manifest>
      <spine toc="ncx">
      </spine>
    </package>
    """
  end

  defp content_opf_with_cover(metadata) do
    title = Map.get(metadata, :title, "")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
      <metadata>
        <dc:title>#{title}</dc:title>
        <dc:language>en</dc:language>
      </metadata>
      <manifest>
        <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
      </manifest>
      <spine toc="ncx">
      </spine>
    </package>
    """
  end

  defp toc_ncx(metadata) do
    title = Map.get(metadata, :title, "Book")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
      <head>
        <meta name="dtb:uid" content="urn:uuid:12345"/>
      </head>
      <docTitle>
        <text>#{title}</text>
      </docTitle>
      <navMap>
      </navMap>
    </ncx>
    """
  end

  defp create_minimal_png do
    # Minimal 1x1 transparent PNG
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44,
      0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
      0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00,
      0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82>>
  end
end
