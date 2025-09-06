defmodule FuzzyCatalog.Repo.Migrations.AddProviderRefreshIntervalSetting do
  use Ecto.Migration

  def change do
    # Insert default provider refresh interval setting
    execute """
            INSERT INTO application_settings (key, value, inserted_at, updated_at) VALUES 
            ('provider_refresh_interval', 'disabled', NOW(), NOW());
            """,
            """
            DELETE FROM application_settings WHERE key = 'provider_refresh_interval';
            """
  end
end
