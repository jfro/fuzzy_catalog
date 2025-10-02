defmodule FuzzyCatalog.ImportExport.Job do
  use Ecto.Schema
  import Ecto.Changeset

  alias FuzzyCatalog.Accounts.User

  @type_values ["export", "import"]
  @status_values ["pending", "processing", "completed", "failed"]

  schema "import_export_jobs" do
    field :type, :string
    field :status, :string, default: "pending"
    field :file_path, :string
    field :file_name, :string
    field :file_size, :integer
    field :progress, :integer, default: 0
    field :total_items, :integer
    field :processed_items, :integer, default: 0
    field :error_message, :string
    field :filters, :map
    field :expires_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :type,
      :status,
      :file_path,
      :file_name,
      :file_size,
      :progress,
      :total_items,
      :processed_items,
      :error_message,
      :filters,
      :expires_at,
      :completed_at,
      :user_id
    ])
    |> validate_required([:type, :status, :user_id])
    |> validate_inclusion(:type, @type_values)
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:processed_items, greater_than_or_equal_to: 0)
    |> validate_number(:total_items, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a changeset for export job creation
  """
  def export_changeset(job, attrs) do
    job
    |> changeset(attrs)
    |> put_change(:type, "export")
    |> put_change(:expires_at, DateTime.utc_now() |> DateTime.add(7, :day))
  end

  @doc """
  Creates a changeset for import job creation
  """
  def import_changeset(job, attrs) do
    job
    |> changeset(attrs)
    |> put_change(:type, "import")
    |> validate_required([:file_path, :file_name])
  end

  @doc """
  Updates job progress
  """
  def progress_changeset(job, attrs) do
    job
    |> cast(attrs, [:processed_items, :progress, :status])
    |> validate_inclusion(:status, @status_values)
    |> validate_number(:progress, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end

  @doc """
  Marks job as completed
  """
  def complete_changeset(job, attrs \\ %{}) do
    job
    |> cast(attrs, [:file_path, :file_name, :file_size, :error_message])
    |> put_change(:status, "completed")
    |> put_change(:completed_at, DateTime.utc_now())
    |> put_change(:progress, 100)
  end

  @doc """
  Marks job as failed
  """
  def fail_changeset(job, error_message) do
    job
    |> cast(%{error_message: error_message}, [:error_message])
    |> put_change(:status, "failed")
    |> put_change(:completed_at, DateTime.utc_now())
  end

  @doc """
  Returns true if the job has expired
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Returns true if the job is still processing
  """
  def processing?(%__MODULE__{status: status}) when status in ["pending", "processing"], do: true
  def processing?(_), do: false

  @doc """
  Returns true if the job is completed successfully
  """
  def completed?(%__MODULE__{status: "completed"}), do: true
  def completed?(_), do: false

  @doc """
  Returns true if the job has failed
  """
  def failed?(%__MODULE__{status: "failed"}), do: true
  def failed?(_), do: false
end