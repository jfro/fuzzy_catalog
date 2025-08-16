defmodule FuzzyCatalogWeb.UserAdminAuth do
  @moduledoc """
  Admin authorization functions for the web application.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias FuzzyCatalog.Accounts

  @doc """
  Plug to require admin privileges.

  If the user is not an admin, they are redirected with an error message.
  """
  def require_admin(conn, _opts) do
    case get_current_scope(conn) do
      %{user: user} when not is_nil(user) ->
        if Accounts.admin?(user) && Accounts.active?(user) do
          conn
        else
          conn
          |> put_flash(:error, "Access denied. Admin privileges required.")
          |> redirect(to: "/")
          |> halt()
        end

      _ ->
        conn
        |> put_flash(:error, "You must be logged in to access this page.")
        |> redirect(to: "/users/log-in")
        |> halt()
    end
  end

  @doc """
  Returns true if the current user is an admin.
  """
  def admin?(conn) do
    case get_current_scope(conn) do
      %{user: user} when not is_nil(user) ->
        Accounts.admin?(user) && Accounts.active?(user)

      _ ->
        false
    end
  end

  defp get_current_scope(conn) do
    conn.assigns[:current_scope]
  end
end
