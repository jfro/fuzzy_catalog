defmodule FuzzyCatalog.Ebooks.Library do
  @moduledoc """
  Schema for ebook libraries.

  A library represents a directory containing ebook files. Libraries can have different scan modes
  that determine how and when the directory is scanned for new or changed ebooks.

  ## Scan Modes

  - `manual`: Scans are triggered manually via the "Scan Now" button in the UI
  - `auto_watch`: Automatic scanning triggered when filesystem changes are detected (5-second debounce)
  - `scheduled`: Periodic scanning based on a cron schedule (e.g., "0 */6 * * *" for every 6 hours)

  ## Fields

  - `name`: Human-readable name for the library
  - `path`: Absolute path to the directory containing ebook files
  - `scan_mode`: One of "manual", "auto_watch", or "scheduled"
  - `schedule`: Cron expression (required when scan_mode is "scheduled")
  - `scanning_status`: Current status - "idle", "scanning", or "failed"
  - `last_scanned_at`: Timestamp of last successful scan
  - `last_scan_error`: Error message if last scan failed

  ## Scanning Status

  The `scanning_status` field prevents concurrent scans:
  - "idle": Library is ready to be scanned
  - "scanning": Scan is currently in progress
  - "failed": Last scan encountered an error

  ## Examples

      # Create a manual scan library
      %Library{
        name: "My Books",
        path: "/home/user/Books",
        scan_mode: "manual"
      }

      # Create an auto-watch library
      %Library{
        name: "Monitored Library",
        path: "/home/user/Calibre Library",
        scan_mode: "auto_watch"
      }

      # Create a scheduled library (scan every 6 hours)
      %Library{
        name: "Scheduled Library",
        path: "/mnt/ebooks",
        scan_mode: "scheduled",
        schedule: "0 */6 * * *"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @valid_scan_modes ~w(manual auto_watch scheduled)

  schema "libraries" do
    field :name, :string
    field :path, :string
    field :scan_mode, :string, default: "manual"
    field :schedule, :string
    field :scanning_status, :string, default: "idle"
    field :last_scanned_at, :utc_datetime
    field :last_scan_error, :string
    field :scan_progress_stage, :string
    field :scan_progress_current, :integer
    field :scan_progress_total, :integer

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(library, attrs) do
    library
    |> cast(attrs, [
      :name,
      :path,
      :scan_mode,
      :schedule,
      :scanning_status,
      :last_scanned_at,
      :last_scan_error,
      :scan_progress_stage,
      :scan_progress_current,
      :scan_progress_total
    ])
    |> validate_required([:name, :path, :scan_mode])
    |> validate_inclusion(:scan_mode, @valid_scan_modes)
    |> validate_path_format()
    |> validate_schedule_for_scan_mode()
    |> unique_constraint(:path)
  end

  defp validate_path_format(changeset) do
    validate_change(changeset, :path, fn :path, path ->
      if String.starts_with?(path, "/") do
        []
      else
        [path: "must be an absolute path"]
      end
    end)
  end

  defp validate_schedule_for_scan_mode(changeset) do
    scan_mode = get_field(changeset, :scan_mode)
    schedule = get_field(changeset, :schedule)

    cond do
      scan_mode == "scheduled" && is_nil(schedule) ->
        add_error(changeset, :schedule, "can't be blank when scan mode is scheduled")

      scan_mode in ["manual", "auto_watch"] && not is_nil(schedule) ->
        # Clear schedule for non-scheduled modes
        put_change(changeset, :schedule, nil)

      true ->
        changeset
    end
  end
end
