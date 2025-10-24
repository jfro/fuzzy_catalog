defmodule FuzzyCatalogWeb.ImportExportHTML do
  use FuzzyCatalogWeb, :html

  embed_templates "import_export_html/*"

  def format_file_size(nil), do: "Unknown"

  def format_file_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 2)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 2)} MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      true -> "#{bytes} B"
    end
  end

  def format_datetime(nil), do: ""

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  def status_badge_class(status) do
    case status do
      "completed" -> "bg-green-100 text-green-800"
      "processing" -> "bg-blue-100 text-blue-800"
      "pending" -> "bg-yellow-100 text-yellow-800"
      "failed" -> "bg-red-100 text-red-800"
      _ -> "bg-gray-100 text-gray-800"
    end
  end

  def status_text(status) do
    case status do
      "completed" -> "Completed"
      "processing" -> "Processing"
      "pending" -> "Pending"
      "failed" -> "Failed"
      _ -> String.capitalize(status)
    end
  end

  def progress_bar_class(status) do
    case status do
      "completed" -> "bg-green-600"
      "processing" -> "bg-blue-600"
      "failed" -> "bg-red-600"
      _ -> "bg-gray-600"
    end
  end
end
