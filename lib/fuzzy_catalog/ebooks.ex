defmodule FuzzyCatalog.Ebooks do
  @moduledoc """
  The Ebooks context for managing ebook files.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Ebooks.Ebook
  alias FuzzyCatalog.Ebooks.Workers.{ScanWorker, ProcessWorker}

  @doc """
  Returns the list of ebooks.
  """
  def list_ebooks do
    Ebook
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single ebook.
  Raises `Ecto.NoResultsError` if the Ebook does not exist.
  """
  def get_ebook!(id) do
    Repo.get!(Ebook, id)
  end

  @doc """
  Creates an ebook.
  """
  def create_ebook(attrs \\ %{}) do
    %Ebook{}
    |> Ebook.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an ebook.
  """
  def update_ebook(%Ebook{} = ebook, attrs) do
    ebook
    |> Ebook.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets an ebook by file path.
  """
  def get_ebook_by_path(file_path) do
    Ebook
    |> where([e], e.file_path == ^file_path)
    |> Repo.one()
  end

  @doc """
  Triggers a directory scan for ebook files.

  ## Options

  - `:directory` - Required. Path to scan
  - `:recursive` - Optional. Whether to scan subdirectories (default: true)

  ## Examples

      iex> trigger_scan(directory: "/ebooks")
      {:ok, %Oban.Job{}}

      iex> trigger_scan(directory: "/ebooks", recursive: false)
      {:ok, %Oban.Job{}}
  """
  def trigger_scan(opts) do
    %{
      directory: Keyword.fetch!(opts, :directory),
      recursive: Keyword.get(opts, :recursive, true)
    }
    |> ScanWorker.new()
    |> Oban.insert()
  end

  @doc """
  Triggers reprocessing of an ebook.

  ## Options

  - `:enable_fuzzy_matching` - Optional. Enable fuzzy title/author matching (default: false)

  ## Examples

      iex> trigger_reprocess(123)
      {:ok, %Oban.Job{}}

      iex> trigger_reprocess(123, enable_fuzzy_matching: true)
      {:ok, %Oban.Job{}}
  """
  def trigger_reprocess(ebook_id, opts \\ []) do
    args = %{ebook_id: ebook_id}

    args =
      if Keyword.get(opts, :enable_fuzzy_matching, false) do
        Map.put(args, :enable_fuzzy_matching, true)
      else
        args
      end

    args
    |> ProcessWorker.new()
    |> Oban.insert()
  end

  @doc """
  Lists ebooks with pending processing status.

  ## Examples

      iex> list_pending_ebooks()
      [%Ebook{}, ...]
  """
  def list_pending_ebooks do
    Ebook
    |> where([e], e.processing_status == "pending")
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists ebooks with failed processing status.

  ## Examples

      iex> list_failed_ebooks()
      [%Ebook{}, ...]
  """
  def list_failed_ebooks do
    Ebook
    |> where([e], e.processing_status == "failed")
    |> order_by([e], desc: e.last_processed_at)
    |> Repo.all()
  end

  @doc """
  Deletes an ebook.

  ## Examples

      iex> delete_ebook(ebook)
      {:ok, %Ebook{}}

      iex> delete_ebook(ebook)
      {:error, %Ecto.Changeset{}}
  """
  def delete_ebook(%Ebook{} = ebook) do
    Repo.delete(ebook)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ebook changes.

  ## Examples

      iex> change_ebook(ebook)
      %Ecto.Changeset{data: %Ebook{}}
  """
  def change_ebook(%Ebook{} = ebook, attrs \\ %{}) do
    Ebook.changeset(ebook, attrs)
  end
end
