defmodule FuzzyCatalog.Repo.Migrations.RemoveUserIdFromCollections do
  use Ecto.Migration

  def up do
    # Consolidate collection_items by removing duplicates across users
    # Keep the earliest added_at date and concatenate notes
    execute("""
      WITH consolidated AS (
        SELECT 
          book_id,
          media_type,
          MIN(added_at) as earliest_added_at,
          STRING_AGG(DISTINCT notes, '; ') FILTER (WHERE notes IS NOT NULL AND notes != '') as combined_notes,
          MIN(inserted_at) as earliest_inserted_at,
          MAX(updated_at) as latest_updated_at
        FROM collection_items
        GROUP BY book_id, media_type
      ),
      rows_to_keep AS (
        SELECT DISTINCT ON (ci.book_id, ci.media_type) ci.id
        FROM collection_items ci
        INNER JOIN consolidated c ON ci.book_id = c.book_id AND ci.media_type = c.media_type
        ORDER BY ci.book_id, ci.media_type, ci.added_at ASC
      )
      UPDATE collection_items 
      SET 
        added_at = c.earliest_added_at,
        notes = c.combined_notes,
        inserted_at = c.earliest_inserted_at,
        updated_at = c.latest_updated_at
      FROM consolidated c
      WHERE collection_items.book_id = c.book_id 
        AND collection_items.media_type = c.media_type
        AND collection_items.id IN (SELECT id FROM rows_to_keep)
    """)

    # Remove duplicate rows, keeping only the consolidated ones
    execute("""
      DELETE FROM collection_items 
      WHERE id NOT IN (
        SELECT DISTINCT ON (book_id, media_type) id
        FROM collection_items
        ORDER BY book_id, media_type, added_at ASC
      )
    """)

    # Drop user-related constraints and indexes
    drop_if_exists unique_index(:collection_items, [:user_id, :book_id, :media_type])
    drop_if_exists index(:collection_items, [:user_id])
    drop_if_exists constraint(:collection_items, "collection_items_user_id_fkey")

    # Remove user_id column
    alter table(:collection_items) do
      remove :user_id
    end

    # Add new unique constraint for book_id + media_type
    create unique_index(:collection_items, [:book_id, :media_type])

    # Handle the old collections table similarly
    execute("""
      WITH consolidated AS (
        SELECT 
          book_id,
          MIN(added_at) as earliest_added_at,
          STRING_AGG(DISTINCT notes, '; ') FILTER (WHERE notes IS NOT NULL AND notes != '') as combined_notes,
          MIN(inserted_at) as earliest_inserted_at,
          MAX(updated_at) as latest_updated_at
        FROM collections
        GROUP BY book_id
      ),
      rows_to_keep AS (
        SELECT DISTINCT ON (c.book_id) c.id
        FROM collections c
        INNER JOIN consolidated con ON c.book_id = con.book_id
        ORDER BY c.book_id, c.added_at ASC
      )
      UPDATE collections 
      SET 
        added_at = con.earliest_added_at,
        notes = con.combined_notes,
        inserted_at = con.earliest_inserted_at,
        updated_at = con.latest_updated_at
      FROM consolidated con
      WHERE collections.book_id = con.book_id 
        AND collections.id IN (SELECT id FROM rows_to_keep)
    """)

    # Remove duplicate rows from collections table
    execute("""
      DELETE FROM collections 
      WHERE id NOT IN (
        SELECT DISTINCT ON (book_id) id
        FROM collections
        ORDER BY book_id, added_at ASC
      )
    """)

    # Drop user-related constraints and indexes from collections
    drop_if_exists unique_index(:collections, [:user_id, :book_id])
    drop_if_exists index(:collections, [:user_id])
    drop_if_exists constraint(:collections, "collections_user_id_fkey")

    # Remove user_id column from collections
    alter table(:collections) do
      remove :user_id
    end

    # Add new unique constraint for book_id only
    drop_if_exists unique_index(:collections, [:book_id])
    create unique_index(:collections, [:book_id])
  end

  def down do
    # This is a destructive migration - we can't fully reverse it
    # because we've lost the user associations
    drop_if_exists unique_index(:collection_items, [:book_id, :media_type])
    drop_if_exists unique_index(:collections, [:book_id])

    alter table(:collection_items) do
      add :user_id, references(:users, on_delete: :delete_all), null: true
    end

    alter table(:collections) do
      add :user_id, references(:users, on_delete: :delete_all), null: true
    end

    create index(:collection_items, [:user_id])
    create index(:collections, [:user_id])

    # Note: We cannot restore the original user associations
    # Manual data restoration would be required
  end
end
