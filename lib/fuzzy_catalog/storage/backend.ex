defmodule FuzzyCatalog.Storage.Backend do
  @moduledoc """
  Behavior for file storage backends.

  This behavior defines the interface for different storage backends
  like local filesystem, S3, CloudFlare, etc.
  """

  @doc """
  Store a file with the given key and content.

  ## Parameters
    - key: A unique identifier for the file
    - content: The file content as binary
    - opts: Additional options like content_type

  ## Returns
    - {:ok, key} on success
    - {:error, reason} on failure
  """
  @callback store(key :: String.t(), content :: binary(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, any()}

  @doc """
  Get the URL to access a stored file.

  ## Parameters
    - key: The unique identifier for the file

  ## Returns
    - {:ok, url} on success
    - {:error, reason} if file doesn't exist or other error
  """
  @callback retrieve_url(key :: String.t()) :: {:ok, String.t()} | {:error, any()}

  @doc """
  Delete a stored file.

  ## Parameters
    - key: The unique identifier for the file

  ## Returns
    - :ok on success (even if file doesn't exist)
    - {:error, reason} on failure
  """
  @callback delete(key :: String.t()) :: :ok | {:error, any()}

  @doc """
  Check if a file exists in storage.

  ## Parameters
    - key: The unique identifier for the file

  ## Returns
    - true if file exists
    - false if file doesn't exist
  """
  @callback exists?(key :: String.t()) :: boolean()
end
