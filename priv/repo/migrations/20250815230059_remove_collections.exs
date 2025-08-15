defmodule FuzzyCatalog.Repo.Migrations.RemoveCollections do
  use Ecto.Migration

  def change do
    drop table(:collections)
  end
end
