defmodule FuzzyCatalog.Repo.Migrations.RemoveExternalIdFromCollectionItems do
  use Ecto.Migration

  def up do
    # Remove external_id column and its index
    drop index(:collection_items, [:external_id])

    alter table(:collection_items) do
      remove :external_id
    end
  end

  def down do
    # Re-add external_id column and index
    alter table(:collection_items) do
      add :external_id, :string
    end

    create index(:collection_items, [:external_id])
  end
end
