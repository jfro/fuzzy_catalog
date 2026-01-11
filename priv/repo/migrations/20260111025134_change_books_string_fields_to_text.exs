defmodule FuzzyCatalog.Repo.Migrations.ChangeBooksStringFieldsToText do
  use Ecto.Migration

  def change do
    alter table(:books) do
      modify :title, :text, null: false
      modify :author, :text, null: false
      modify :publisher, :text
      modify :genre, :text
      modify :subtitle, :text
      modify :series, :text
      modify :original_title, :text
    end
  end
end
