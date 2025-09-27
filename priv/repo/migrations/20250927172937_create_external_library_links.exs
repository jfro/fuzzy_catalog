defmodule FuzzyCatalog.Repo.Migrations.CreateExternalLibraryLinks do
  use Ecto.Migration

  def change do
    create table(:external_library_links) do
      add :book_id, references(:books, on_delete: :delete_all), null: false
      add :media_type, :string, null: false
      add :provider, :string, null: false
      add :external_id, :string, null: false

      timestamps()
    end

    create index(:external_library_links, [:book_id])
    create index(:external_library_links, [:external_id])
    create index(:external_library_links, [:provider])
    create unique_index(:external_library_links, [:book_id, :media_type, :provider])
  end
end
