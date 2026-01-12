defmodule FuzzyCatalog.Repo.Migrations.CreateLibraries do
  use Ecto.Migration

  def change do
    create table(:libraries) do
      add :name, :string, null: false
      add :path, :string, null: false
      add :scan_mode, :string, null: false, default: "manual"
      add :schedule, :string
      add :scanning_status, :string, default: "idle"
      add :last_scanned_at, :utc_datetime
      add :last_scan_error, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:libraries, [:path])
    create index(:libraries, [:scan_mode])
    create index(:libraries, [:scanning_status])
  end
end
