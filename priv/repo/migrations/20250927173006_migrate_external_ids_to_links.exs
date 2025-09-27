defmodule FuzzyCatalog.Repo.Migrations.MigrateExternalIdsToLinks do
  use Ecto.Migration

  def up do
    # Migrate existing external_id data from collection_items to external_library_links
    execute """
    INSERT INTO external_library_links (book_id, media_type, provider, external_id, inserted_at, updated_at)
    SELECT
      ci.book_id,
      ci.media_type,
      CASE
        WHEN ci.media_type = 'audiobook' THEN 'audiobookshelf'
        WHEN ci.media_type = 'ebook' THEN 'calibre'
        ELSE 'audiobookshelf'  -- default fallback
      END as provider,
      ci.external_id,
      NOW(),
      NOW()
    FROM collection_items ci
    WHERE ci.external_id IS NOT NULL AND ci.external_id != ''
    """
  end

  def down do
    # Remove all external_library_links (this is destructive)
    execute "DELETE FROM external_library_links"
  end
end
