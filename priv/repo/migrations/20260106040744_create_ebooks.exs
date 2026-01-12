defmodule FuzzyCatalog.Repo.Migrations.CreateEbooks do
  use Ecto.Migration

  def change do
    create table(:ebooks) do
      # File Information
      add :file_path, :string, null: false
      add :file_format, :string, null: false
      add :file_size, :bigint
      add :file_hash, :string
      add :last_modified_at, :utc_datetime

      # Extracted Metadata
      add :extracted_title, :string
      add :extracted_author, :string
      add :extracted_isbn, :string
      add :extracted_publisher, :string
      add :extracted_language, :string
      add :extracted_description, :text

      # Processing Information
      add :processing_status, :string, default: "pending", null: false
      add :processing_error, :text
      add :last_processed_at, :utc_datetime

      # Cover thumbnail
      add :cover_thumbnail_key, :string

      # Relationships
      add :book_id, references(:books, on_delete: :nilify_all)

      timestamps()
    end

    create index(:ebooks, [:book_id])
    create index(:ebooks, [:file_hash])
    create index(:ebooks, [:processing_status])
    create unique_index(:ebooks, [:file_path])
  end
end
