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
end
