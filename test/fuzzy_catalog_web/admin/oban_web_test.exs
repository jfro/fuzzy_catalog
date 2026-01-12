defmodule FuzzyCatalogWeb.Admin.ObanWebTest do
  use FuzzyCatalogWeb.ConnCase, async: true

  import FuzzyCatalog.AccountsFixtures

  describe "GET /admin/oban" do
    test "redirects to login when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/admin/oban")
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "redirects non-admin users with error message", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/admin/oban")
      assert redirected_to(conn) == ~p"/"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Access denied. Admin privileges required."
    end
  end
end
