defmodule FuzzyCatalog.Repo.Migrations.ChangeSeriesNumberToDecimal do
  use Ecto.Migration

  def change do
    alter table(:books) do
      modify :series_number, :decimal, precision: 8, scale: 2
    end
  end
end
