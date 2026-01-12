# Phase 3: Metadata Extraction (EPUB/PDF Parsing)

Implement libraries and utilities to extract metadata from EPUB and PDF ebook files.

## Overview

This phase integrates Elixir libraries to:
- Parse EPUB files and extract metadata (title, author, ISBN, etc.)
- Extract cover images from EPUB files
- Parse PDF files and extract basic metadata
- Handle errors gracefully (missing files, corrupted files, etc.)

## Step 3.1: Add Dependencies

**File:** `mix.exs`

Add to the `deps` function:

```elixir
defp deps do
  [
    # ... existing dependencies ...
    {:bupe, "~> 0.6.3"},      # EPUB parsing
    {:pdfinfo, "~> 1.0"}      # PDF metadata extraction
  ]
end
```

Install dependencies:

```bash
mix deps.get
```

---

## Step 3.2: Write MetadataExtractor Tests

**File:** `test/fuzzy_catalog/ebooks/metadata_extractor_test.exs`

```elixir
defmodule FuzzyCatalog.Ebooks.MetadataExtractorTest do
  use FuzzyCatalog.DataCase, async: true

  alias FuzzyCatalog.Ebooks.MetadataExtractor

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

    test "returns error for non-existent file" do
      assert {:error, reason} = MetadataExtractor.extract("/nonexistent.epub")
      assert reason =~ "file not found"
    end

    @tag :tmp_dir
    test "returns error for corrupted EPUB", %{tmp_dir: tmp_dir} do
      # Create an invalid file
      path = Path.join(tmp_dir, "corrupt.epub")
      File.write!(path, "not a valid epub")

      assert {:error, reason} = MetadataExtractor.extract(path)
      assert reason =~ "Failed to parse EPUB" or reason =~ "invalid"
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

  # Test helper functions
  defp create_test_epub(path, metadata) do
    # For now, create a minimal EPUB structure
    # TODO: Use BUPE.Builder or create minimal ZIP structure
    # This is a simplified version - real EPUBs are ZIP files with specific structure
    File.write!(path, "placeholder for test epub")
  end

  defp create_test_epub_with_cover(path) do
    # Create EPUB with embedded cover image
    File.write!(path, "placeholder for epub with cover")
  end

  defp create_test_pdf(path, metadata) do
    # Create minimal valid PDF with metadata
    # PDFs are more complex - may need sample file or external tool
    File.write!(path, "placeholder for test pdf")
  end
end
```

**Note:** The test helper functions are placeholders. For production tests, you'll need to:
- Use BUPE.Builder to create valid EPUBs
- Include sample EPUB/PDF files in `test/fixtures/files/`
- Or use external tools to generate test files

---

## Step 3.3: Implement MetadataExtractor

**File:** `lib/fuzzy_catalog/ebooks/metadata_extractor.ex`

```elixir
defmodule FuzzyCatalog.Ebooks.MetadataExtractor do
  @moduledoc """
  Extracts metadata from ebook files (EPUB, PDF).
  """

  require Logger

  @doc """
  Extracts metadata from an ebook file.

  Returns {:ok, metadata_map} or {:error, reason}

  Metadata map includes:
  - title: Book title
  - author: Author name
  - isbn: ISBN identifier
  - publisher: Publisher name
  - language: Language code
  - description: Book description
  - format: File format ("epub" or "pdf")
  """
  def extract(file_path) do
    unless File.exists?(file_path) do
      {:error, "file not found: #{file_path}"}
    else
      cond do
        String.ends_with?(file_path, ".epub") ->
          extract_epub_metadata(file_path)

        String.ends_with?(file_path, ".pdf") ->
          extract_pdf_metadata(file_path)

        true ->
          {:error, "Unsupported file format"}
      end
    end
  end

  @doc """
  Extracts cover image binary from ebook file.

  Returns {:ok, binary} or {:error, reason}
  """
  def extract_cover(file_path) do
    unless File.exists?(file_path) do
      {:error, "file not found: #{file_path}"}
    else
      cond do
        String.ends_with?(file_path, ".epub") ->
          extract_epub_cover(file_path)

        String.ends_with?(file_path, ".pdf") ->
          {:error, :not_implemented}

        true ->
          {:error, "Unsupported file format"}
      end
    end
  end

  # Private functions

  defp extract_epub_metadata(file_path) do
    case BUPE.Parser.parse(file_path) do
      {:ok, epub} ->
        metadata = %{
          title: get_in(epub, [:metadata, :title]),
          author: get_in(epub, [:metadata, :creator]),
          isbn: find_isbn(epub),
          publisher: get_in(epub, [:metadata, :publisher]),
          language: get_in(epub, [:metadata, :language]),
          description: get_in(epub, [:metadata, :description]),
          format: "epub"
        }

        {:ok, metadata}

      {:error, reason} ->
        {:error, "Failed to parse EPUB: #{inspect(reason)}"}
    end
  rescue
    e ->
      Logger.error("EPUB parsing exception: #{inspect(e)}")
      {:error, "Failed to parse EPUB: #{Exception.message(e)}"}
  end

  defp find_isbn(epub) do
    # EPUB may have ISBN in identifier field with scheme
    identifiers = get_in(epub, [:metadata, :identifier]) || []

    case identifiers do
      list when is_list(list) ->
        Enum.find_value(list, fn
          %{scheme: "ISBN", value: isbn} -> isbn
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp extract_epub_cover(file_path) do
    with {:ok, epub} <- BUPE.Parser.parse(file_path),
         {:ok, cover_path} <- find_cover_in_epub(epub),
         {:ok, binary} <- read_cover_from_epub(file_path, cover_path) do
      {:ok, binary}
    else
      {:error, :no_cover} -> {:error, :no_cover}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("Cover extraction exception: #{inspect(e)}")
      {:error, "Failed to extract cover: #{Exception.message(e)}"}
  end

  defp find_cover_in_epub(epub) do
    # Look for cover in manifest
    # EPUB may specify cover in various ways:
    # 1. metadata cover-image property
    # 2. manifest item with properties="cover-image"
    # 3. guide reference type="cover"

    # Simplified version - check manifest for cover-image property
    manifest = get_in(epub, [:manifest]) || []

    cover_item = Enum.find(manifest, fn item ->
      properties = Map.get(item, :properties, "")
      String.contains?(properties, "cover-image")
    end)

    if cover_item do
      {:ok, Map.get(cover_item, :href)}
    else
      {:error, :no_cover}
    end
  end

  defp read_cover_from_epub(epub_path, cover_path) do
    # EPUBs are ZIP files, extract cover image
    # This requires unzipping the EPUB and reading the specific file
    # For now, return placeholder - full implementation would use :zip module
    {:error, :not_implemented}
  end

  defp extract_pdf_metadata(file_path) do
    case File.read(file_path) do
      {:ok, binary} ->
        case PDFInfo.parse(binary) do
          {:ok, info} ->
            metadata = %{
              title: Map.get(info, :title),
              author: Map.get(info, :author),
              publisher: Map.get(info, :producer),
              format: "pdf",
              # PDFs rarely have ISBNs in metadata
              isbn: nil,
              language: nil,
              description: nil
            }

            {:ok, metadata}

          {:error, reason} ->
            {:error, "Failed to parse PDF: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read PDF: #{inspect(reason)}"}
    end
  rescue
    e ->
      Logger.error("PDF parsing exception: #{inspect(e)}")
      {:error, "Failed to parse PDF: #{Exception.message(e)}"}
  end
end
```

**Implementation Notes:**

1. **EPUB Cover Extraction:** The `read_cover_from_epub/2` function is marked as `:not_implemented`. Full implementation would:
   - Use `:zip.extract/2` to unzip the EPUB
   - Read the cover image file from the unzipped content
   - Return the binary

2. **PDF Limitations:** PDF files don't typically include ISBN or detailed metadata like EPUBs. The `pdfinfo` library extracts basic metadata (title, author, producer).

3. **Error Handling:** All functions gracefully handle errors and return `{:error, reason}` tuples.

---

## Verification

Run tests:

```bash
mix test test/fuzzy_catalog/ebooks/metadata_extractor_test.exs
```

**Expected:** Some tests may fail due to placeholder implementations in test helpers. This is acceptable for initial TDD iteration. Update test helpers to create real EPUBs/PDFs or skip those tests until full implementation.

---

## Optional: Enhanced EPUB Cover Extraction

If you want to fully implement cover extraction, add this to MetadataExtractor:

```elixir
defp read_cover_from_epub(epub_path, cover_path) do
  case :zip.extract(to_charlist(epub_path), [:memory]) do
    {:ok, files} ->
      # Find the cover file in extracted files
      cover_file = Enum.find(files, fn {name, _binary} ->
        List.to_string(name) =~ cover_path
      end)

      case cover_file do
        {_name, binary} -> {:ok, binary}
        nil -> {:error, :cover_file_not_found}
      end

    {:error, reason} ->
      {:error, "Failed to extract EPUB: #{inspect(reason)}"}
  end
end
```

---

## Next Steps

Continue to [Phase 4: ScanWorker](./04-scan-worker.md) to implement file discovery.
