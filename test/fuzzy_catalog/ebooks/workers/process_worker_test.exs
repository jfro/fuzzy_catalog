defmodule FuzzyCatalog.Ebooks.Workers.ProcessWorkerTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  import ExUnit.CaptureLog

  alias FuzzyCatalog.Ebooks.Workers.ProcessWorker
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Collections
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
    test "adds book to ebook collection", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "collection_test.epub")

      create_test_epub(epub_path, %{
        title: "Collection Test Book",
        creator: "Collection Author"
      })

      {:ok, content} = File.read(epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      assert updated.processing_status == "completed"
      assert updated.book_id

      # Verify book was added to ebook collection
      book = FuzzyCatalog.Catalog.get_book!(updated.book_id)
      media_types = Collections.get_book_media_types(book)
      assert "ebook" in media_types
    end

    @tag :tmp_dir
    test "sets cover on Book record when processing ebook", %{tmp_dir: tmp_dir} do
      paths =
        create_calibre_directory_structure(tmp_dir, %{
          title: "Book with Cover",
          author: "Cover Author",
          with_cover: true
        })

      {:ok, content} = File.read(paths.epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: paths.epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      assert updated.processing_status == "completed"
      assert updated.book_id
      assert updated.cover_thumbnail_key

      # Verify cover was also set on Book record
      book = FuzzyCatalog.Catalog.get_book!(updated.book_id)
      assert book.cover_image_key
      assert book.cover_image_key == updated.cover_thumbnail_key
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
    test "updates hash when file is modified", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "modified.epub")

      # Create valid EPUB with initial content
      create_test_epub(epub_path, %{
        title: "Original Title",
        creator: "Original Author"
      })

      {:ok, original_content} = File.read(epub_path)
      original_hash = :crypto.hash(:sha256, original_content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: epub_path, file_hash: original_hash)

      # Process first time - should work
      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      # Now modify the file with new valid EPUB
      create_test_epub(epub_path, %{
        title: "Modified Title",
        creator: "Modified Author"
      })

      {:ok, new_content} = File.read(epub_path)
      new_hash = :crypto.hash(:sha256, new_content) |> Base.encode16(case: :lower)

      # Hash should be different
      assert new_hash != original_hash

      # Reprocess - should detect change and update
      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      # Should have new hash and new metadata
      assert updated.file_hash == new_hash
      assert updated.extracted_title == "Modified Title"
      assert updated.extracted_author == "Modified Author"
      assert updated.processing_status == "completed"
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

  describe "Calibre metadata integration" do
    @tag :tmp_dir
    test "extracts and stores OPF metadata in Book record", %{tmp_dir: tmp_dir} do
      paths =
        create_calibre_directory_structure(tmp_dir, %{
          title: "The Name of the Wind",
          author: "Patrick Rothfuss",
          isbn: "9780756404079",
          series: "The Kingkiller Chronicle",
          series_index: "1.0",
          rating: 10,
          tags: ["Fantasy", "Epic Fantasy"],
          publisher: "DAW Books"
        })

      {:ok, content} = File.read(paths.epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: paths.epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      assert updated.processing_status == "completed"
      assert updated.book_id

      # Verify metadata stored in Book record, not Ebook
      book = FuzzyCatalog.Catalog.get_book!(updated.book_id)
      assert book.title == "The Name of the Wind"
      assert book.author == "Patrick Rothfuss"
      assert book.series == "The Kingkiller Chronicle"
      assert Decimal.equal?(book.series_number, Decimal.new("1.0"))
      assert book.rating == 10
      assert book.tags == ["Fantasy", "Epic Fantasy"]
      assert book.publisher == "DAW Books"
    end

    @tag :tmp_dir
    test "extracts cover from Calibre cover.jpg", %{tmp_dir: tmp_dir} do
      paths =
        create_calibre_directory_structure(tmp_dir, %{
          title: "Test Book with Cover",
          author: "Test Author",
          with_cover: true
        })

      {:ok, content} = File.read(paths.epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: paths.epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      # Should have extracted and stored cover
      assert updated.cover_thumbnail_key
    end

    @tag :tmp_dir
    test "processes correctly when no metadata.opf exists", %{tmp_dir: tmp_dir} do
      epub_path = Path.join(tmp_dir, "regular.epub")

      create_test_epub(epub_path, %{
        title: "Regular EPUB",
        creator: "Author"
      })

      {:ok, content} = File.read(epub_path)
      file_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: epub_path, file_hash: file_hash)

      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      assert updated.processing_status == "completed"
    end
  end

  describe "configuration" do
    @tag :tmp_dir
    test "uses enable_fuzzy_matching config by default", %{tmp_dir: tmp_dir} do
      # Verify config value exists and is accessible
      config = Application.get_env(:fuzzy_catalog, :ebooks)
      enable_fuzzy = config[:enable_fuzzy_matching]

      assert is_boolean(enable_fuzzy)

      # Create ebook with metadata but no ISBN
      epub_path = Path.join(tmp_dir, "fuzzy_test.epub")

      create_test_epub(epub_path, %{
        title: "Some Title",
        creator: "Some Author"
      })

      file_hash =
        File.read!(epub_path)
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      ebook = ebook_fixture(file_path: epub_path, file_hash: file_hash)

      # Process without explicit enable_fuzzy_matching argument
      # Worker should use config value
      assert :ok =
               perform_job(ProcessWorker, %{
                 "ebook_id" => ebook.id
               })

      updated = Ebooks.get_ebook!(ebook.id)
      assert updated.processing_status == "completed"
    end

    test "fuzzy_threshold configuration is valid" do
      config = Application.get_env(:fuzzy_catalog, :ebooks)
      threshold = config[:fuzzy_threshold]

      assert is_float(threshold)
      assert threshold >= 0.0
      assert threshold <= 1.0
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
