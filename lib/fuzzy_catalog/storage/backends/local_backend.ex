defmodule FuzzyCatalog.Storage.Backends.LocalBackend do
  @moduledoc """
  Local filesystem storage backend.

  Stores files in a local directory and serves them via Phoenix static file serving.
  """

  @behaviour FuzzyCatalog.Storage.Backend

  require Logger

  @impl FuzzyCatalog.Storage.Backend
  def store(key, content, _opts \\ []) do
    file_path = build_file_path(key)

    # Ensure directory exists
    file_path
    |> Path.dirname()
    |> File.mkdir_p!()

    case File.write(file_path, content) do
      :ok ->
        Logger.info("Stored file: #{key}")
        {:ok, key}

      {:error, reason} ->
        Logger.error("Failed to store file #{key}: #{reason}")
        {:error, reason}
    end
  end

  @impl FuzzyCatalog.Storage.Backend
  def retrieve_url(key) do
    if exists?(key) do
      base_url = get_config(:base_url, "/uploads")
      url = Path.join(base_url, key)
      {:ok, url}
    else
      {:error, :not_found}
    end
  end

  @impl FuzzyCatalog.Storage.Backend
  def delete(key) do
    file_path = build_file_path(key)

    case File.rm(file_path) do
      :ok ->
        Logger.info("Deleted file: #{key}")
        :ok

      {:error, :enoent} ->
        # File doesn't exist, consider it successful
        :ok

      {:error, reason} ->
        Logger.error("Failed to delete file #{key}: #{reason}")
        {:error, reason}
    end
  end

  @impl FuzzyCatalog.Storage.Backend
  def exists?(key) do
    file_path = build_file_path(key)
    File.exists?(file_path)
  end

  # Private helper functions

  defp build_file_path(key) do
    base_path = get_config(:base_path, "priv/static/uploads")
    Path.join(base_path, key)
  end

  defp get_config(key, default) do
    :fuzzy_catalog
    |> Application.get_env(:storage, [])
    |> Keyword.get(:local, [])
    |> Keyword.get(key, default)
  end
end
