defmodule FuzzyCatalog.Repo.Migrations.AddExternalIdToCollectionItems do
  use Ecto.Migration

  def change do
    alter table(:collection_items) do
      add :external_id, :string
    end

    create index(:collection_items, [:external_id])
  end
end
