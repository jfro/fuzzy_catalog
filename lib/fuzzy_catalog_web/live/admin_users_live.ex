defmodule FuzzyCatalogWeb.AdminUsersLive do
  use FuzzyCatalogWeb, :live_view

  alias FuzzyCatalog.Accounts
  alias FuzzyCatalog.Accounts.User
  alias FuzzyCatalog.AdminSettings

  @impl true
  def mount(_params, session, socket) do
    current_scope = get_current_scope_from_session(session)

    # Verify user is admin
    if current_scope.user && Accounts.admin?(current_scope.user) do
      socket =
        socket
        |> assign(:current_scope, current_scope)
        |> assign(:page_title, "User Management")
        |> assign(:users, Accounts.list_users())
        |> assign(:show_create_form, false)
        |> assign(:creating_user, false)
        |> assign(:editing_user, nil)
        |> assign(:create_changeset, User.registration_changeset(%User{}, %{}))
        |> assign(:settings, AdminSettings.all_settings())
        |> assign(:registration_enabled, AdminSettings.registration_enabled?())
        |> assign(:email_verification_required, AdminSettings.email_verification_required?())

      {:ok, socket, layout: {FuzzyCatalogWeb.Layouts, :live}}
    else
      socket =
        socket
        |> put_flash(:error, "Access denied. Admin privileges required.")
        |> push_navigate(to: ~p"/")

      {:ok, socket}
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

  @impl true
  def handle_event("toggle_registration", _params, socket) do
    current_enabled = socket.assigns.registration_enabled

    case AdminSettings.set_registration_enabled(!current_enabled) do
      {:ok, _setting} ->
        socket =
          socket
          |> assign(:registration_enabled, !current_enabled)
          |> put_flash(
            :info,
            "Registration #{if !current_enabled, do: "enabled", else: "disabled"}"
          )

        {:noreply, socket}

      {:error, _changeset} ->
        socket = put_flash(socket, :error, "Failed to update registration setting")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_email_verification", _params, socket) do
    current_required = socket.assigns.email_verification_required

    case AdminSettings.set_email_verification_required(!current_required) do
      {:ok, _setting} ->
        socket =
          socket
          |> assign(:email_verification_required, !current_required)
          |> put_flash(
            :info,
            "Email verification #{if !current_required, do: "required", else: "optional"}"
          )

        {:noreply, socket}

      {:error, _changeset} ->
        socket = put_flash(socket, :error, "Failed to update email verification setting")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_create_form", _params, socket) do
    socket =
      socket
      |> assign(:show_create_form, true)
      |> assign(:create_changeset, User.registration_changeset(%User{}, %{}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_create_form", _params, socket) do
    socket =
      socket
      |> assign(:show_create_form, false)
      |> assign(:creating_user, false)

    {:noreply, socket}
  end

  @impl true
  def handle_event("create_user", %{"user" => user_params}, socket) do
    socket = assign(socket, :creating_user, true)

    case Accounts.create_user_by_admin(user_params) do
      {:ok, _user} ->
        socket =
          socket
          |> assign(:users, Accounts.list_users())
          |> assign(:show_create_form, false)
          |> assign(:creating_user, false)
          |> assign(:create_changeset, User.registration_changeset(%User{}, %{}))
          |> put_flash(:info, "User created successfully")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:create_changeset, changeset)
          |> assign(:creating_user, false)

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit_user", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)
    changeset = Accounts.change_user_admin(user)

    socket =
      socket
      |> assign(:editing_user, user)
      |> assign(:edit_changeset, changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    socket = assign(socket, :editing_user, nil)
    {:noreply, socket}
  end

  @impl true
  def handle_event("update_user", %{"user" => user_params}, socket) do
    user = socket.assigns.editing_user

    case Accounts.update_user_by_admin(user, user_params) do
      {:ok, _user} ->
        socket =
          socket
          |> assign(:users, Accounts.list_users())
          |> assign(:editing_user, nil)
          |> put_flash(:info, "User updated successfully")

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket = assign(socket, :edit_changeset, changeset)
        {:noreply, socket}
    end
  end
end
