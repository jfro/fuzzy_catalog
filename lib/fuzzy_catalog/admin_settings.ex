defmodule FuzzyCatalog.AdminSettings do
  @moduledoc """
  The AdminSettings context for managing application-wide settings.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.AdminSettings.Setting

  @doc """
  Gets a setting by key.

  ## Examples

      iex> get_setting("registration_enabled")
      %Setting{}

      iex> get_setting("nonexistent")
      nil

  """
  def get_setting(key) when is_binary(key) do
    Repo.get_by(Setting, key: key)
  end

  @doc """
  Gets the value of a setting by key, returning the default if not found.

  ## Examples

      iex> get_setting_value("registration_enabled", true)
      false

      iex> get_setting_value("nonexistent", "default")
      "default"

  """
  def get_setting_value(key, default \\ nil) when is_binary(key) do
    case get_setting(key) do
      %Setting{value: value} -> parse_value(value)
      nil -> default
    end
  end

  @doc """
  Updates or creates a setting.

  ## Examples

      iex> put_setting("registration_enabled", false)
      {:ok, %Setting{}}

      iex> put_setting("invalid_key", "value")
      {:error, %Ecto.Changeset{}}

  """
  def put_setting(key, value) when is_binary(key) do
    attrs = %{key: key, value: serialize_value(value)}

    case get_setting(key) do
      nil ->
        %Setting{}
        |> Setting.changeset(attrs)
        |> Repo.insert()

      setting ->
        setting
        |> Setting.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Returns true if registration is enabled.
  """
  def registration_enabled? do
    get_setting_value("registration_enabled", true)
  end

  @doc """
  Returns true if email verification is required for registration.
  """
  def email_verification_required? do
    get_setting_value("email_verification_required", false)
  end

  @doc """
  Enables or disables registration.
  """
  def set_registration_enabled(enabled) when is_boolean(enabled) do
    put_setting("registration_enabled", enabled)
  end

  @doc """
  Enables or disables email verification requirement.
  """
  def set_email_verification_required(required) when is_boolean(required) do
    put_setting("email_verification_required", required)
  end

  @doc """
  Returns the provider refresh interval setting.
  Defaults to "disabled" if not set.
  """
  def get_provider_refresh_interval do
    get_setting_value("provider_refresh_interval", "disabled")
  end

  @doc """
  Sets the provider refresh interval.
  Accepts time intervals like "1h", "30m", "15m" or "disabled".
  """
  def set_provider_refresh_interval(interval) when is_binary(interval) do
    put_setting("provider_refresh_interval", interval)
  end

  @doc """
  Returns all settings as a map.
  """
  def all_settings do
    Setting
    |> Repo.all()
    |> Enum.into(%{}, fn %Setting{key: key, value: value} ->
      {key, parse_value(value)}
    end)
  end

  # Private functions

  defp serialize_value(value) when is_boolean(value), do: to_string(value)
  defp serialize_value(value) when is_binary(value), do: value
  defp serialize_value(value), do: inspect(value)

  defp parse_value("true"), do: true
  defp parse_value("false"), do: false
  defp parse_value(value), do: value
end
