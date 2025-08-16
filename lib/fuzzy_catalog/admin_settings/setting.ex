defmodule FuzzyCatalog.AdminSettings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "application_settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> validate_length(:key, max: 255)
    |> validate_length(:value, max: 1000)
    |> unique_constraint(:key)
  end
end
