defmodule FuzzyCatalog.Repo.Migrations.AddScanProgressToLibraries do
  use Ecto.Migration

  def change do
    alter table(:libraries) do
      # "scanning" or "processing"
      add :scan_progress_stage, :string
      # Current count
      add :scan_progress_current, :integer
      # Total count
      add :scan_progress_total, :integer
    end
  end
end
