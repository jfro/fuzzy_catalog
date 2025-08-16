defmodule FuzzyCatalog.Repo.Migrations.CreateApplicationSettings do
  use Ecto.Migration

  def change do
    create table(:application_settings) do
      add :key, :string, null: false
      add :value, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:application_settings, [:key])

    # Insert default settings
    execute """
            INSERT INTO application_settings (key, value, inserted_at, updated_at) VALUES 
            ('registration_enabled', 'true', NOW(), NOW()),
            ('email_verification_required', 'true', NOW(), NOW());
            """,
            """
            DELETE FROM application_settings WHERE key IN ('registration_enabled', 'email_verification_required');
            """
  end
end
