defmodule FuzzyCatalog.Repo.Migrations.AddExtendedMetadataToBooks do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :rating, :integer
      add :tags, {:array, :string}, default: []
      add :custom_metadata, :jsonb
    end

    create index(:books, [:rating])
    create index(:books, [:tags], using: "GIN")
  end
end
