defmodule FuzzyCatalog.Repo.Migrations.AddOidcFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :provider, :string
      add :provider_uid, :string
      add :provider_token, :text
    end

    create unique_index(:users, [:provider, :provider_uid])
  end
end
