defmodule FuzzyCatalog.Repo.Migrations.AddLibraryIdToEbooks do
  use Ecto.Migration

  def change do
    alter table(:ebooks) do
      add :library_id, references(:libraries, on_delete: :nilify_all)
    end

    create index(:ebooks, [:library_id])
  end
end
