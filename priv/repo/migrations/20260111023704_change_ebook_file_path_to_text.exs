defmodule FuzzyCatalog.Repo.Migrations.ChangeEbookFilePathToText do
  use Ecto.Migration

  def change do
    alter table(:ebooks) do
      modify :file_path, :text, null: false
    end
  end
end
