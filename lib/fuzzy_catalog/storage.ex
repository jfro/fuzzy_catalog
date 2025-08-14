defmodule FuzzyCatalog.Storage do
  @moduledoc """
  High-level interface for file storage operations.

  This module provides a clean API for storing and retrieving files
  using the configured storage backend.
  """

  require Logger

  @doc """
  Store a cover image for a book.

  ## Parameters
    - file_content: The binary content of the image file
    - opts: Options including:
      - content_type: MIME type of the file
      - extension: File extension (e.g., ".jpg", ".png")

  ## Returns
    - {:ok, storage_key} on success
    - {:error, reason} on failure
  """
  def store_cover(file_content, opts \\ []) when is_binary(file_content) do
    content_type = Keyword.get(opts, :content_type, "image/jpeg")
    extension = Keyword.get(opts, :extension) || determine_extension(content_type)

    # Generate unique key for the file
    storage_key = generate_cover_key(extension)

    # Validate the content type
    case validate_image_content_type(content_type) do
      :ok ->
        backend().store(storage_key, file_content, content_type: content_type)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the URL for a stored cover image.

  ## Parameters
    - storage_key: The unique key for the stored file

  ## Returns
    - {:ok, url} on success
    - {:error, reason} if file doesn't exist or other error
  """
  def get_cover_url(storage_key) when is_binary(storage_key) do
    backend().retrieve_url(storage_key)
  end

  def get_cover_url(nil), do: {:error, :no_key}

  @doc """
  Delete a stored cover image.

  ## Parameters
    - storage_key: The unique key for the stored file

  ## Returns
    - :ok on success (even if file doesn't exist)
    - {:error, reason} on failure
  """
  def delete_cover(storage_key) when is_binary(storage_key) do
    backend().delete(storage_key)
  end

  def delete_cover(nil), do: :ok

  @doc """
  Check if a cover image exists in storage.

  ## Parameters
    - storage_key: The unique key for the stored file

  ## Returns
    - true if file exists
    - false if file doesn't exist
  """
  def cover_exists?(storage_key) when is_binary(storage_key) do
    backend().exists?(storage_key)
  end

  def cover_exists?(nil), do: false

  @doc """
  Download and store a cover image from a URL.

  ## Parameters
    - url: The URL to download the image from

  ## Returns
    - {:ok, storage_key} on success
    - {:error, reason} on failure
  """
  def download_and_store_cover(url) when is_binary(url) do
    Logger.info("Downloading cover image from: #{url}")

    case download_image(url) do
      {:ok, file_content, content_type} ->
        Logger.info("Downloaded #{byte_size(file_content)} bytes, content-type: #{content_type}")
        store_cover(file_content, content_type: content_type)

      {:error, reason} ->
        Logger.warning("Failed to download cover image from #{url}: #{reason}")
        {:error, reason}
    end
  end

  # Private helper functions

  defp backend do
    Application.get_env(:fuzzy_catalog, :storage, [])
    |> Keyword.get(:backend, FuzzyCatalog.Storage.Backends.LocalBackend)
  end

  defp generate_cover_key(extension) do
    uuid = Ecto.UUID.generate()
    "#{uuid}#{extension}"
  end

  defp determine_extension(content_type) do
    case content_type do
      "image/jpeg" -> ".jpg"
      "image/jpg" -> ".jpg"
      "image/png" -> ".png"
      "image/gif" -> ".gif"
      "image/webp" -> ".webp"
      _ -> ".jpg"
    end
  end

  defp validate_image_content_type(content_type) do
    allowed_types = [
      "image/jpeg",
      "image/jpg",
      "image/png",
      "image/gif",
      "image/webp"
    ]

    if content_type in allowed_types do
      :ok
    else
      {:error, "Unsupported image type: #{content_type}"}
    end
  end

  defp download_image(url) do
    headers = [{"User-Agent", "FuzzyCatalog/1.0"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        content_type =
          case Enum.find(headers, fn {key, _value} ->
                 String.downcase(key) == "content-type"
               end) do
            {_key, value} when is_binary(value) ->
              value
              |> String.split(";")
              |> List.first()
              |> String.trim()

            {_key, [value | _]} when is_binary(value) ->
              value
              |> String.split(";")
              |> List.first()
              |> String.trim()

            _ ->
              "image/jpeg"
          end

        {:ok, body, content_type}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
