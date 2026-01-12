defmodule FuzzyCatalog.Ebooks.EbookTest do
  use FuzzyCatalog.DataCase, async: true

  alias FuzzyCatalog.Ebooks.Ebook
  import FuzzyCatalog.EbooksFixtures

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1_024_000,
        file_hash: "abc123def456"
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
    end

    test "requires file_path" do
      attrs = %{file_format: "epub", file_size: 1024}
      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires file_format" do
      attrs = %{file_path: "/path/to/book.epub", file_size: 1024}
      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_format: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates file_format is in allowed list" do
      attrs = %{
        file_path: "/path/to/book.txt",
        file_format: "txt",
        file_size: 1024
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_format: ["is invalid"]} = errors_on(changeset)
    end

    test "validates file_size is positive" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: -100
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_size: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "accepts optional book_id for linking to existing book" do
      book = book_fixture()

      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        book_id: book.id
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :book_id) == book.id
    end

    test "accepts extracted metadata fields" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        extracted_title: "The Great Gatsby",
        extracted_author: "F. Scott Fitzgerald",
        extracted_isbn: "9780743273565",
        extracted_publisher: "Scribner"
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
    end

    test "accepts processing status fields" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        processing_status: "completed",
        last_processed_at: DateTime.utc_now()
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
    end

    test "validates processing_status is in allowed list" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        processing_status: "invalid_status"
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{processing_status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "associations" do
    test "belongs_to book (optional)" do
      ebook = ebook_fixture()
      assert %Ecto.Association.NotLoaded{} = ebook.book

      ebook_with_book = ebook |> Repo.preload(:book)
      assert is_nil(ebook_with_book.book)
    end

    test "can link to existing book" do
      book = book_fixture()
      ebook = ebook_fixture(book_id: book.id)
      ebook_with_book = ebook |> Repo.preload(:book)

      assert ebook_with_book.book.id == book.id
    end
  end
end
