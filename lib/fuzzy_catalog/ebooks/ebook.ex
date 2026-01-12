defmodule FuzzyCatalog.Ebooks.Ebook do
  use Ecto.Schema
  import Ecto.Changeset

  @file_formats ~w(epub pdf)
  @processing_statuses ~w(pending processing completed failed)

  schema "ebooks" do
    # File Information (required)
    field :file_path, :string
    field :file_format, :string
    field :file_size, :integer
    field :file_hash, :string
    field :last_modified_at, :utc_datetime

    # Extracted Metadata (optional)
    field :extracted_title, :string
    field :extracted_author, :string
    field :extracted_isbn, :string
    field :extracted_publisher, :string
    field :extracted_language, :string
    field :extracted_description, :string

    # Processing Information
    field :processing_status, :string, default: "pending"
    field :processing_error, :string
    field :last_processed_at, :utc_datetime

    # Cover thumbnail (stored via Storage backend)
    field :cover_thumbnail_key, :string

    # Optional relationship to Book
    belongs_to :book, FuzzyCatalog.Catalog.Book

    # Optional relationship to Library
    belongs_to :library, FuzzyCatalog.Ebooks.Library

    timestamps()
  end

  @doc false
  def changeset(ebook, attrs) do
    ebook
    |> cast(attrs, [
      :file_path,
      :file_format,
      :file_size,
      :file_hash,
      :last_modified_at,
      :extracted_title,
      :extracted_author,
      :extracted_isbn,
      :extracted_publisher,
      :extracted_language,
      :extracted_description,
      :processing_status,
      :processing_error,
      :last_processed_at,
      :cover_thumbnail_key,
      :book_id,
      :library_id
    ])
    |> validate_required([:file_path, :file_format])
    |> validate_inclusion(:file_format, @file_formats)
    |> validate_inclusion(:processing_status, @processing_statuses)
    |> validate_number(:file_size, greater_than: 0)
    |> foreign_key_constraint(:book_id)
    |> foreign_key_constraint(:library_id)
    |> unique_constraint(:file_path)
  end

  def file_formats, do: @file_formats
  def processing_statuses, do: @processing_statuses
end
