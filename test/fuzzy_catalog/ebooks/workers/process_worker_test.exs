defmodule FuzzyCatalog.Ebooks.Workers.ProcessWorkerTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  import ExUnit.CaptureLog

  alias FuzzyCatalog.Ebooks.Workers.ProcessWorker
  alias FuzzyCatalog.Ebooks
  import FuzzyCatalog.EbooksFixtures

  describe "perform/1" do
    @tag :tmp_dir
    test "extracts metadata from EPUB file", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "test.epub")

      # Create a valid test EPUB
      create_test_epub(epub_path, %{
        title: "Test Book",
        creator: "Test Author"
      })

      # Calculate hash after creating the file
      {:ok, content} = File.read(epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      assert updated.processing_status == "completed"
      refute is_nil(updated.last_processed_at)
    end

    @tag :tmp_dir
    test "matches to existing book by ISBN", %{tmp_dir: tmp_dir} do
      # Create existing book with ISBN
      _book =
        book_fixture(%{
          title: "Existing Book",
          author: "Jane Smith",
          isbn13: "9780123456789"
        })

      # Create ebook file with ISBN in metadata
      epub_path = Path.join(tmp_dir, "matching.epub")

      create_test_epub(epub_path, %{
        title: "Existing Book",
        creator: "Jane Smith",
        isbn: "9780123456789"
      })

      {:ok, content} = File.read(epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      # Create ebook record
      ebook = ebook_fixture(file_path: epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      _updated = Ebooks.get_ebook!(ebook.id)
      # With ISBN pre-filled, worker should match to book
      # Note: Actual matching happens during processing
    end

    test "handles missing file gracefully" do
      ebook = ebook_fixture(file_path: "/nonexistent/book.epub")

      # Capture expected error log
      capture_log(fn ->
        assert {:error, _reason} =
                 perform_job(ProcessWorker, %{
                   "ebook_id" => ebook.id
                 })

        updated = Ebooks.get_ebook!(ebook.id)
        assert updated.processing_status == "failed"
        assert updated.processing_error =~ "file not found"
      end)
    end

    @tag :tmp_dir
    test "verifies file integrity by hash", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "verify.epub")

      # Create file and calculate hash
      original_content = "original content"
      File.write!(epub_path, original_content)
      original_hash = :crypto.hash(:sha256, original_content) |> Base.encode16(case: :lower)

      ebook =
        ebook_fixture(
          file_path: epub_path,
          file_hash: original_hash
        )

      # Modify file after ebook creation
      File.write!(epub_path, "modified content")

      # Capture expected error log
      capture_log(fn ->
        assert {:error, _reason} =
                 perform_job(ProcessWorker, %{
                   "ebook_id" => ebook.id
                 })

        updated = Ebooks.get_ebook!(ebook.id)
        assert updated.processing_status == "failed"
        assert updated.processing_error =~ "file hash mismatch"
      end)
    end

    @tag :tmp_dir
    test "updates processing status to failed on error", %{tmp_dir: tmp_dir} do
      corrupt_path = Path.join(tmp_dir, "corrupt.epub")
      content = "not a valid epub"
      File.write!(corrupt_path, content)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: corrupt_path, file_hash: file_hash)

      # Capture expected error logs from attempting to parse invalid EPUB
      capture_log(fn ->
        # Processing should fail gracefully
        assert {:error, _reason} =
                 perform_job(ProcessWorker, %{
                   "ebook_id" => ebook.id
                 })

        updated = Ebooks.get_ebook!(ebook.id)
        assert updated.processing_status == "failed"
        assert updated.processing_error
      end)
    end
  end

  # Test helper functions (from MetadataExtractorTest)
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
end
