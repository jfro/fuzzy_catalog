defmodule FuzzyCatalog.Repo.Migrations.CreateBooks do
  use Ecto.Migration

  def change do
    create table(:books) do
      add :title, :string, null: false
      add :author, :string, null: false
      add :upc, :string
      add :isbn10, :string
      add :isbn13, :string
      add :amazon_asin, :string

      timestamps()
    end
  end
end
