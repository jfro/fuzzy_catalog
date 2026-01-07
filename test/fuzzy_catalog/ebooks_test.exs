defmodule FuzzyCatalog.EbooksTest do
  use FuzzyCatalog.DataCase, async: true

  alias FuzzyCatalog.Ebooks
  import FuzzyCatalog.EbooksFixtures

  describe "list_ebooks/0" do
    test "returns all ebooks" do
      ebook1 = ebook_fixture()
      ebook2 = ebook_fixture()

      ebooks = Ebooks.list_ebooks()

      assert length(ebooks) == 2
      assert Enum.any?(ebooks, &(&1.id == ebook1.id))
      assert Enum.any?(ebooks, &(&1.id == ebook2.id))
    end
  end

  describe "get_ebook!/1" do
    test "returns the ebook with given id" do
      ebook = ebook_fixture()

      assert Ebooks.get_ebook!(ebook.id).id == ebook.id
    end

    test "raises if ebook doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Ebooks.get_ebook!(999_999)
      end
    end
  end

  describe "create_ebook/1" do
    test "creates ebook with valid data" do
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1_024_000
      }

      assert {:ok, ebook} = Ebooks.create_ebook(attrs)
      assert ebook.file_path == "/path/to/book.epub"
    end

    test "returns error with invalid data" do
      assert {:error, changeset} = Ebooks.create_ebook(%{})
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_ebook/2" do
    test "updates ebook with valid data" do
      ebook = ebook_fixture()

      assert {:ok, updated} =
               Ebooks.update_ebook(ebook, %{
                 extracted_title: "New Title",
                 processing_status: "completed"
               })

      assert updated.extracted_title == "New Title"
      assert updated.processing_status == "completed"
    end
  end

  describe "get_ebook_by_path/1" do
    test "returns ebook by file path" do
      ebook = ebook_fixture(file_path: "/unique/path/book.epub")

      assert found = Ebooks.get_ebook_by_path("/unique/path/book.epub")
      assert found.id == ebook.id
    end

    test "returns nil if path doesn't exist" do
      assert is_nil(Ebooks.get_ebook_by_path("/nonexistent.epub"))
    end
  end
end
