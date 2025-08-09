defmodule FuzzyCatalog.Repo.Migrations.AddCoverUrlToBooks do
  use Ecto.Migration

  def change do
    alter table(:books) do
      add :cover_url, :string
    end
  end
end
