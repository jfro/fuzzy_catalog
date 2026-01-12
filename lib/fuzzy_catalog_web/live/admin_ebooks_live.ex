defmodule FuzzyCatalogWeb.AdminEbooksLive do
  @moduledoc """
  LiveView for viewing and managing problem ebooks (admin only).

  Shows ebooks that failed during processing with their error messages.
  Allows admins to:
  - View failed ebook details (file path, error, format)
  - Retry processing failed ebooks
  - Delete failed ebook records

  ## Access Control

  Only accessible to admin users. Non-admin users are redirected to the home page.

  ## Route

      live "/admin/ebooks", AdminEbooksLive, :index
  """
  use FuzzyCatalogWeb, :live_view

  require Logger
  alias FuzzyCatalog.Accounts
  alias FuzzyCatalog.Ebooks

  @impl true
  def mount(_params, session, socket) do
    current_scope = get_current_scope_from_session(session)

    if current_scope.user && Accounts.admin?(current_scope.user) do
      failed_ebooks = Ebooks.list_failed_ebooks()

      socket =
        socket
        |> assign(:current_scope, current_scope)
        |> assign(:failed_ebooks, failed_ebooks)

      {:ok, socket, layout: {FuzzyCatalogWeb.Layouts, :live}}
    else
      socket =
        socket
        |> put_flash(:error, "Access denied. Admin privileges required.")
        |> push_navigate(to: ~p"/")

      {:ok, socket}
    end
  end

  @impl true
  def handle_event("retry_processing", %{"id" => id}, socket) do
    ebook = Ebooks.get_ebook!(id)

    case Ebooks.trigger_reprocess(String.to_integer(id)) do
      {:ok, _job} ->
        # Update ebook status to pending
        {:ok, _updated} = Ebooks.update_ebook(ebook, %{processing_status: "pending"})

        # Reload failed ebooks
        failed_ebooks = Ebooks.list_failed_ebooks()

        socket =
          socket
          |> assign(:failed_ebooks, failed_ebooks)
          |> put_flash(:info, "Reprocessing ebook: #{Path.basename(ebook.file_path)}")

        {:noreply, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to enqueue reprocessing job")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_ebook", %{"id" => id}, socket) do
    ebook = Ebooks.get_ebook!(id)

    case Ebooks.delete_ebook(ebook) do
      {:ok, _deleted} ->
        # Reload failed ebooks
        failed_ebooks = Ebooks.list_failed_ebooks()

        socket =
          socket
          |> assign(:failed_ebooks, failed_ebooks)
          |> put_flash(:info, "Ebook record deleted")

        {:noreply, socket}

      {:error, _changeset} ->
        socket =
          socket
          |> put_flash(:error, "Failed to delete ebook")

        {:noreply, socket}
    end
  end

  defp get_current_scope_from_session(session) do
    case session["user_token"] do
      nil ->
        Accounts.Scope.for_user(nil)

      user_token ->
        case Accounts.get_user_by_session_token(user_token) do
          {user, _inserted_at} -> Accounts.Scope.for_user(user)
          nil -> Accounts.Scope.for_user(nil)
        end
    end
  end

  defp format_file_size(nil), do: "Unknown"
  defp format_file_size(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  defp format_file_size(bytes) when is_integer(bytes) and bytes < 1_048_576 do
    kb = Float.round(bytes / 1024, 1)
    "#{kb} KB"
  end

  defp format_file_size(bytes) when is_integer(bytes) and bytes < 1_073_741_824 do
    mb = Float.round(bytes / 1_048_576, 1)
    "#{mb} MB"
  end

  defp format_file_size(bytes) when is_integer(bytes) do
    gb = Float.round(bytes / 1_073_741_824, 1)
    "#{gb} GB"
  end

  defp format_file_size(_), do: "Unknown"
end
