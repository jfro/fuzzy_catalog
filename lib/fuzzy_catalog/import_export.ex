defmodule FuzzyCatalog.ImportExport do
  @moduledoc """
  The ImportExport context.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo

  alias FuzzyCatalog.ImportExport.Job
  alias FuzzyCatalog.Accounts.User

  @doc """
  Returns the list of import_export_jobs for a user.

  ## Examples

      iex> list_jobs(user)
      [%Job{}, ...]

  """
  def list_jobs(%User{} = user) do
    from(j in Job, where: j.user_id == ^user.id, order_by: [desc: j.inserted_at])
    |> Repo.all()
  end

  @doc """
  Returns the list of active (non-expired) jobs for a user.

  ## Examples

      iex> list_active_jobs(user)
      [%Job{}, ...]

  """
  def list_active_jobs(%User{} = user) do
    now = DateTime.utc_now()

    from(j in Job,
      where: j.user_id == ^user.id,
      where: is_nil(j.expires_at) or j.expires_at > ^now,
      order_by: [desc: j.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single job for a user.

  Raises `Ecto.NoResultsError` if the Job does not exist or doesn't belong to the user.

  ## Examples

      iex> get_job!(user, 123)
      %Job{}

      iex> get_job!(user, 456)
      ** (Ecto.NoResultsError)

  """
  def get_job!(%User{} = user, id) do
    from(j in Job, where: j.id == ^id and j.user_id == ^user.id)
    |> Repo.one!()
  end

  @doc """
  Gets a single job for a user.

  Returns nil if the Job does not exist or doesn't belong to the user.

  ## Examples

      iex> get_job(user, 123)
      %Job{}

      iex> get_job(user, 456)
      nil

  """
  def get_job(%User{} = user, id) do
    from(j in Job, where: j.id == ^id and j.user_id == ^user.id)
    |> Repo.one()
  end

  @doc """
  Creates an export job.

  ## Examples

      iex> create_export_job(user, %{filters: %{media_type: "book"}})
      {:ok, %Job{}}

      iex> create_export_job(user, %{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_export_job(%User{} = user, attrs \\ %{}) do
    %Job{}
    |> Job.export_changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Creates an import job.

  ## Examples

      iex> create_import_job(user, %{file_path: "/tmp/import.json", file_name: "import.json"})
      {:ok, %Job{}}

      iex> create_import_job(user, %{bad_field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_import_job(%User{} = user, attrs \\ %{}) do
    %Job{}
    |> Job.import_changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates a job.

  ## Examples

      iex> update_job(job, %{status: "completed"})
      {:ok, %Job{}}

      iex> update_job(job, %{status: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates job progress.

  ## Examples

      iex> update_job_progress(job, %{processed_items: 50, progress: 50})
      {:ok, %Job{}}

  """
  def update_job_progress(%Job{} = job, attrs) do
    job
    |> Job.progress_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a job as completed.

  ## Examples

      iex> complete_job(job, %{file_path: "/tmp/export.json"})
      {:ok, %Job{}}

  """
  def complete_job(%Job{} = job, attrs \\ %{}) do
    job
    |> Job.complete_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a job as failed.

  ## Examples

      iex> fail_job(job, "Export failed due to database error")
      {:ok, %Job{}}

  """
  def fail_job(%Job{} = job, error_message) do
    job
    |> Job.fail_changeset(error_message)
    |> Repo.update()
  end

  @doc """
  Deletes a job.

  ## Examples

      iex> delete_job(job)
      {:ok, %Job{}}

      iex> delete_job(job)
      {:error, %Ecto.Changeset{}}

  """
  def delete_job(%Job{} = job) do
    Repo.delete(job)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking job changes.

  ## Examples

      iex> change_job(job)
      %Ecto.Changeset{data: %Job{}}

  """
  def change_job(%Job{} = job, attrs \\ %{}) do
    Job.changeset(job, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking export job changes.

  ## Examples

      iex> change_export_job(job)
      %Ecto.Changeset{data: %Job{}}

  """
  def change_export_job(%Job{} = job, attrs \\ %{}) do
    Job.export_changeset(job, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking import job changes.

  ## Examples

      iex> change_import_job(job)
      %Ecto.Changeset{data: %Job{}}

  """
  def change_import_job(%Job{} = job, attrs \\ %{}) do
    Job.import_changeset(job, attrs)
  end

  @doc """
  Cleans up expired jobs and their associated files.

  Returns the number of jobs cleaned up.

  ## Examples

      iex> cleanup_expired_jobs()
      5

  """
  def cleanup_expired_jobs do
    now = DateTime.utc_now()

    expired_jobs =
      from(j in Job,
        where: not is_nil(j.expires_at) and j.expires_at <= ^now,
        select: j
      )
      |> Repo.all()

    # Clean up files for expired jobs
    for job <- expired_jobs do
      if job.file_path && File.exists?(job.file_path) do
        File.rm(job.file_path)
      end
    end

    # Delete expired jobs from database
    {count, _} =
      from(j in Job,
        where: not is_nil(j.expires_at) and j.expires_at <= ^now
      )
      |> Repo.delete_all()

    count
  end
end
