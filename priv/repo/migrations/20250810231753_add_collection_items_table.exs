defmodule FuzzyCatalog.Repo.Migrations.AddCollectionItemsTable do
  use Ecto.Migration

  def change do
    create table(:collection_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :book_id, references(:books, on_delete: :delete_all), null: false
      add :media_type, :string, null: false, default: "unspecified"
      add :added_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :notes, :text

      timestamps()
    end

    create index(:collection_items, [:user_id])
    create index(:collection_items, [:book_id])
    create unique_index(:collection_items, [:user_id, :book_id, :media_type])

    # Migrate existing collections data to collection_items
    execute(
      """
      INSERT INTO collection_items (user_id, book_id, media_type, added_at, notes, inserted_at, updated_at)
      SELECT user_id, book_id, 'unspecified', COALESCE(added_at, NOW()), notes, inserted_at, updated_at
      FROM collections
      """,
      """
      INSERT INTO collections (user_id, book_id, added_at, notes, inserted_at, updated_at)
      SELECT user_id, book_id, added_at, notes, inserted_at, updated_at
      FROM collection_items
      WHERE media_type = 'unspecified'
      """
    )
  end
end
