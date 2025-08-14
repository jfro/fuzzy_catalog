defmodule FuzzyCatalog.Repo.Migrations.AddCoverImageKeyToBooks do
  use Ecto.Migration

  def change do
    alter table(:books) do
      remove :cover_url, :string
      add :cover_image_key, :string
    end
  end
end
