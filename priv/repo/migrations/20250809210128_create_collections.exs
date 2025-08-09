defmodule FuzzyCatalog.Repo.Migrations.CreateCollections do
  use Ecto.Migration

  def change do
    create table(:collections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :book_id, references(:books, on_delete: :delete_all), null: false
      add :added_at, :utc_datetime, default: fragment("now()"), null: false
      add :notes, :text

      timestamps()
    end

    create index(:collections, [:user_id])
    create index(:collections, [:book_id])
    create unique_index(:collections, [:user_id, :book_id])
  end
end
