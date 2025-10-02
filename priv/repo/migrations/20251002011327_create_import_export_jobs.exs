defmodule FuzzyCatalog.Repo.Migrations.CreateImportExportJobs do
  use Ecto.Migration

  def change do
    create table(:import_export_jobs) do
      add :type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :file_path, :string
      add :file_name, :string
      add :file_size, :integer
      add :progress, :integer, default: 0
      add :total_items, :integer
      add :processed_items, :integer, default: 0
      add :error_message, :text
      add :filters, :map
      add :expires_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:import_export_jobs, [:user_id])
    create index(:import_export_jobs, [:status])
    create index(:import_export_jobs, [:type])
    create index(:import_export_jobs, [:expires_at])
  end
end
