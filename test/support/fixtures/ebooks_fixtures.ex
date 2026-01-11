defmodule FuzzyCatalog.EbooksFixtures do
  @moduledoc """
  Test helpers for creating ebook entities.
  """

  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Catalog

  def unique_file_path do
    "/test/ebooks/book_#{System.unique_integer([:positive])}.epub"
  end

  def valid_ebook_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      file_path: unique_file_path(),
      file_format: "epub",
      file_size: 1_024_000,
      file_hash: "abc123def456"
    })
  end

  def ebook_fixture(attrs \\ %{}) do
    {:ok, ebook} =
      attrs
      |> valid_ebook_attributes()
      |> Ebooks.create_ebook()

    ebook
  end

  def book_fixture(attrs \\ %{}) do
    default_attrs = %{
      title: "Test Book #{System.unique_integer([:positive])}",
      author: "Test Author"
    }

    {:ok, book} =
      default_attrs
      |> Map.merge(attrs)
      |> Catalog.create_book_without_collection()

    book
  end

  @doc """
  Creates a Calibre directory structure with metadata.opf and ebook file.

  Options:
  - title: Book title (default: "Test Book")
  - author: Author name (default: "Test Author")
  - isbn: ISBN identifier (default: nil)
  - series: Series name (default: nil)
  - series_index: Series position (default: nil)
  - rating: Rating 0-10 (default: nil)
  - tags: List of tags (default: [])
  - custom: Map of custom metadata fields (default: %{})
  - with_cover: Create cover.jpg (default: false)
  """
  def create_calibre_directory_structure(tmp_dir, opts \\ %{}) do
    author = opts[:author] || "Test Author"
    title = opts[:title] || "Test Book"
    book_id = opts[:book_id] || "123"

    # Create Calibre directory structure: Author/Title (book_id)/
    book_dir = Path.join([tmp_dir, author, "#{title} (#{book_id})"])
    File.mkdir_p!(book_dir)

    # Create metadata.opf
    opf_path = Path.join(book_dir, "metadata.opf")
    opf_content = create_calibre_opf_content(opts)
    File.write!(opf_path, opf_content)

    # Create epub file
    epub_path = Path.join(book_dir, "#{title}.epub")
    create_test_epub(epub_path, opts)

    # Optionally create cover.jpg
    cover_path =
      if opts[:with_cover] do
        path = Path.join(book_dir, "cover.jpg")
        create_test_cover(path)
        path
      end

    %{
      book_dir: book_dir,
      opf_path: opf_path,
      epub_path: epub_path,
      cover_path: cover_path
    }
  end

  @doc """
  Creates a valid metadata.opf XML content with the given metadata.
  """
  def create_calibre_opf_content(opts \\ %{}) do
    title = opts[:title] || "Test Book"
    author = opts[:author] || "Test Author"
    publisher = opts[:publisher] || nil
    language = opts[:language] || "en"
    description = opts[:description] || nil
    isbn = opts[:isbn] || nil
    asin = opts[:asin] || nil
    goodreads_id = opts[:goodreads_id] || nil
    series = opts[:series] || nil
    series_index = opts[:series_index] || nil
    rating = opts[:rating] || nil
    tags = opts[:tags] || []
    custom = opts[:custom] || %{}
    publication_date = opts[:publication_date] || "2020-01-01T00:00:00+00:00"

    identifiers =
      [
        if(isbn, do: ~s(<dc:identifier opf:scheme="ISBN">#{isbn}</dc:identifier>)),
        if(asin, do: ~s(<dc:identifier opf:scheme="AMAZON">#{asin}</dc:identifier>)),
        if(goodreads_id,
          do: ~s(<dc:identifier opf:scheme="GOODREADS">#{goodreads_id}</dc:identifier>)
        )
      ]
      |> Enum.filter(& &1)
      |> Enum.join("\n    ")

    publisher_tag =
      if publisher, do: "<dc:publisher>#{publisher}</dc:publisher>", else: ""

    description_tag =
      if description, do: "<dc:description>#{description}</dc:description>", else: ""

    series_meta =
      if series do
        [
          ~s(<meta name="calibre:series" content="#{series}"/>),
          if(series_index,
            do: ~s(<meta name="calibre:series_index" content="#{series_index}"/>)
          )
        ]
        |> Enum.filter(& &1)
        |> Enum.join("\n    ")
      else
        ""
      end

    rating_meta =
      if rating, do: ~s(<meta name="calibre:rating" content="#{rating}"/>), else: ""

    subject_tags =
      tags
      |> Enum.map(&"<dc:subject>#{&1}</dc:subject>")
      |> Enum.join("\n    ")

    custom_meta =
      custom
      |> Enum.map(fn {key, value} ->
        # Use HTML entities for quotes to avoid XML parsing issues
        json_content = ~s({"#value#": "#{value}"}) |> String.replace("\"", "&quot;")
        ~s(<meta name="calibre:user_metadata:#{key}" content="#{json_content}"/>)
      end)
      |> Enum.join("\n    ")

    """
    <?xml version='1.0' encoding='utf-8'?>
    <package xmlns="http://www.idpf.org/2007/opf"
             xmlns:dc="http://purl.org/dc/elements/1.1/"
             xmlns:opf="http://www.idpf.org/2007/opf"
             xmlns:calibre="http://calibre.kovidgoyal.net/2009/metadata"
             version="2.0">
      <metadata>
        <dc:title>#{title}</dc:title>
        <dc:creator opf:file-as="#{author}" opf:role="aut">#{author}</dc:creator>
        #{publisher_tag}
        <dc:date>#{publication_date}</dc:date>
        <dc:language>#{language}</dc:language>
        #{description_tag}
        #{identifiers}
        #{series_meta}
        #{rating_meta}
        #{subject_tags}
        #{custom_meta}
      </metadata>
    </package>
    """
  end

  defp create_test_epub(path, opts) do
    # Create minimal valid EPUB structure
    title = opts[:title] || "Test Book"
    author = opts[:author] || "Test Author"

    mimetype = "application/epub+zip"

    container_xml = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    content_opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>#{title}</dc:title>
        <dc:creator>#{author}</dc:creator>
        <dc:language>en</dc:language>
      </metadata>
    </package>
    """

    files = [
      {~c"mimetype", mimetype},
      {~c"META-INF/container.xml", container_xml},
      {~c"OEBPS/content.opf", content_opf}
    ]

    {:ok, {_, zip_content}} = :zip.create(~c"test.epub", files, [:memory])
    File.write!(path, zip_content)
  end

  defp create_test_cover(path) do
    # Create a minimal valid 1x1 pixel JPEG
    jpeg_data =
      <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00,
        0x48, 0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xFF, 0xFF, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x11, 0x00,
        0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
        0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x7F, 0xFF, 0xD9>>

    File.write!(path, jpeg_data)
  end
end
