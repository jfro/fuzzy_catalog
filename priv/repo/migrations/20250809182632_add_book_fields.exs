defmodule FuzzyCatalog.Repo.Migrations.AddBookFields do
  use Ecto.Migration

  def change do
    alter table(:books) do
      # Publishing Information
      add :publisher, :string
      add :publication_date, :date
      add :pages, :integer
      add :genre, :string
      
      # Content Details
      add :subtitle, :string
      add :description, :text
      add :series, :string
      add :series_number, :integer
      add :original_title, :string
    end
  end
end
