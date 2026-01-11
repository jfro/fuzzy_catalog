defmodule FuzzyCatalog.Repo.Migrations.ChangeEbookExtractedFieldsToText do
  use Ecto.Migration

  def change do
    alter table(:ebooks) do
      modify :extracted_title, :text
      modify :extracted_author, :text
      modify :extracted_publisher, :text
    end
  end
end
