defmodule FuzzyCatalog.Repo.Migrations.AddRoleAndStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :role, :string, null: false, default: "user"
      add :status, :string, null: false, default: "active"
    end

    create index(:users, [:role])
    create index(:users, [:status])
  end
end
