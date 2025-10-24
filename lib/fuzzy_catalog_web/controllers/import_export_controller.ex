defmodule FuzzyCatalogWeb.ImportExportController do
  use FuzzyCatalogWeb, :controller

  alias FuzzyCatalog.ImportExport
  alias FuzzyCatalog.ImportExport.{Job, Exporter}
  alias FuzzyCatalog.Storage

  def index(conn, _params) do
    current_user = conn.assigns.current_scope.user
    jobs = ImportExport.list_active_jobs(current_user)

    render(conn, :index, jobs: jobs)
  end

  def new_export(conn, _params) do
    changeset = ImportExport.change_export_job(%Job{})
    filter_options = Exporter.available_filters()

    render(conn, :new_export, changeset: changeset, filter_options: filter_options)
  end

  def create_export(conn, %{"job" => job_params}) do
    current_user = conn.assigns.current_scope.user

    case ImportExport.create_export_job(current_user, job_params) do
      {:ok, job} ->
        # Start export process asynchronously
        spawn(fn -> Exporter.perform_export(job) end)

        conn
        |> put_flash(
          :info,
          "Export job started successfully. You'll be able to download the file when it's ready."
        )
        |> redirect(to: ~p"/admin/import-export")

      {:error, changeset} ->
        filter_options = Exporter.available_filters()
        render(conn, :new_export, changeset: changeset, filter_options: filter_options)
    end
  end

  def new_import(conn, _params) do
    changeset = ImportExport.change_import_job(%Job{})

    render(conn, :new_import, changeset: changeset)
  end

  def create_import(conn, %{"job" => job_params} = params) do
    current_user = conn.assigns.current_scope.user

    case Map.get(params, "file") do
      nil ->
        changeset =
          %Job{}
          |> ImportExport.change_import_job(job_params)
          |> Ecto.Changeset.add_error(:file, "Please select a file to import")

        render(conn, :new_import, changeset: changeset)

      upload ->
        case handle_file_upload(upload) do
          {:ok, file_info} ->
            job_attrs = Map.merge(job_params, file_info)

            case ImportExport.create_import_job(current_user, job_attrs) do
              {:ok, job} ->
                conn
                |> put_flash(
                  :info,
                  "Import file uploaded successfully. Review the preview before importing."
                )
                |> redirect(to: ~p"/admin/import-export/#{job.id}/preview")

              {:error, changeset} ->
                # Clean up uploaded file
                File.rm(file_info.file_path)
                render(conn, :new_import, changeset: changeset)
            end

          {:error, reason} ->
            changeset =
              %Job{}
              |> ImportExport.change_import_job(job_params)
              |> Ecto.Changeset.add_error(:file, reason)

            render(conn, :new_import, changeset: changeset)
        end
    end
  end

  def show(conn, %{"id" => id}) do
    current_user = conn.assigns.current_scope.user
    job = ImportExport.get_job!(current_user, id)

    render(conn, :show, job: job)
  end

  def preview_import(conn, %{"id" => id}) do
    current_user = conn.assigns.current_scope.user
    job = ImportExport.get_job!(current_user, id)

    if job.type != "import" do
      conn
      |> put_flash(:error, "Invalid job type for preview")
      |> redirect(to: ~p"/admin/import-export")
    else
      case validate_and_preview_import_file(job) do
        {:ok, preview_data} ->
          render(conn, :preview_import, job: job, preview_data: preview_data)

        {:error, reason} ->
          ImportExport.fail_job(job, reason)

          conn
          |> put_flash(:error, "Failed to preview import file: #{reason}")
          |> redirect(to: ~p"/admin/import-export")
      end
    end
  end

  def confirm_import(conn, %{"id" => id}) do
    current_user = conn.assigns.current_scope.user
    job = ImportExport.get_job!(current_user, id)

    if job.type != "import" or job.status != "pending" do
      conn
      |> put_flash(:error, "Invalid job for import")
      |> redirect(to: ~p"/admin/import-export")
    else
      # Start import process asynchronously
      spawn(fn -> perform_import(job) end)

      ImportExport.update_job(job, %{status: "processing"})

      conn
      |> put_flash(:info, "Import started successfully. You can monitor the progress below.")
      |> redirect(to: ~p"/admin/import-export/#{job.id}")
    end
  end

  def download(conn, %{"id" => id}) do
    current_user = conn.assigns.current_scope.user
    job = ImportExport.get_job!(current_user, id)

    if job.type != "export" or job.status != "completed" or is_nil(job.file_path) do
      conn
      |> put_flash(:error, "Export file not available")
      |> redirect(to: ~p"/admin/import-export")
    else
      case Storage.get_file_url(job.file_path) do
        {:ok, file_url} ->
          redirect(conn, external: file_url)

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Export file not found")
          |> redirect(to: ~p"/admin/import-export")
      end
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = conn.assigns.current_scope.user
    job = ImportExport.get_job!(current_user, id)

    case ImportExport.delete_job(job) do
      {:ok, _job} ->
        # Clean up associated file
        if job.file_path && File.exists?(job.file_path) do
          File.rm(job.file_path)
        end

        conn
        |> put_flash(:info, "Job deleted successfully.")
        |> redirect(to: ~p"/admin/import-export")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to delete job.")
        |> redirect(to: ~p"/admin/import-export")
    end
  end

  defp handle_file_upload(upload) do
    if upload.content_type not in ["application/json", "text/csv", "application/csv"] do
      {:error, "Only JSON and CSV files are supported"}
    else
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(":", "-")
      original_filename = upload.filename
      extension = Path.extname(original_filename)
      temp_filename = "import_#{timestamp}#{extension}"
      temp_path = Path.join(System.tmp_dir(), temp_filename)

      case File.copy(upload.path, temp_path) do
        {:ok, _bytes} ->
          file_size = File.stat!(temp_path).size

          {:ok,
           %{
             file_path: temp_path,
             file_name: original_filename,
             file_size: file_size
           }}

        {:error, reason} ->
          {:error, "Failed to save uploaded file: #{inspect(reason)}"}
      end
    end
  end

  defp validate_and_preview_import_file(%Job{} = job) do
    case Path.extname(job.file_name) do
      ".json" -> preview_json_import(job)
      ".csv" -> preview_csv_import(job)
      _ -> {:error, "Unsupported file format"}
    end
  end

  defp preview_json_import(%Job{} = job) do
    try do
      content = File.read!(job.file_path)
      data = Jason.decode!(content)

      case validate_json_structure(data) do
        {:ok, items} ->
          preview_items = Enum.take(items, 10)
          total_count = length(items)

          {:ok,
           %{
             format: "json",
             total_items: total_count,
             preview_items: preview_items,
             validation_errors: []
           }}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      Jason.DecodeError -> {:error, "Invalid JSON format"}
      File.Error -> {:error, "Cannot read import file"}
      error -> {:error, "File validation failed: #{Exception.message(error)}"}
    end
  end

  defp preview_csv_import(%Job{} = job) do
    try do
      lines = File.stream!(job.file_path) |> Enum.take(11)
      [header | data_lines] = lines

      headers = String.trim(header) |> String.split(",")

      if validate_csv_headers(headers) do
        preview_data =
          data_lines
          |> Enum.take(10)
          |> Enum.map(&parse_csv_line/1)

        total_count = File.stream!(job.file_path) |> Enum.count()
        total_lines = total_count - 1

        {:ok,
         %{
           format: "csv",
           total_items: total_lines,
           headers: headers,
           preview_items: preview_data,
           validation_errors: []
         }}
      else
        {:error, "Invalid CSV headers. Required headers: title, author"}
      end
    rescue
      File.Error -> {:error, "Cannot read import file"}
      error -> {:error, "CSV validation failed: #{Exception.message(error)}"}
    end
  end

  defp validate_json_structure(%{"items" => items}) when is_list(items) do
    {:ok, items}
  end

  defp validate_json_structure(_), do: {:error, "Invalid JSON structure. Expected 'items' array."}

  defp validate_csv_headers(headers) do
    required_headers = ["title", "author"]
    Enum.all?(required_headers, &(&1 in headers))
  end

  defp parse_csv_line(line) do
    line
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  defp perform_import(%Job{} = job) do
    # This would contain the actual import logic
    # For now, we'll just mark it as completed
    ImportExport.complete_job(job)
  end
end
