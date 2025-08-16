defmodule FuzzyCatalogWeb.UserRegistrationController do
  use FuzzyCatalogWeb, :controller

  alias FuzzyCatalog.Accounts
  alias FuzzyCatalog.Accounts.User
  alias FuzzyCatalog.AdminSettings

  def new(conn, _params) do
    # Check if registration is enabled
    unless AdminSettings.registration_enabled?() do
      conn
      |> put_flash(:error, "Registration is currently disabled.")
      |> redirect(to: ~p"/users/log-in")
    else
      email_required = AdminSettings.email_verification_required?()

      changeset =
        if email_required do
          Accounts.change_user_email(%User{})
        else
          User.registration_changeset(%User{}, %{})
        end

      render(conn, :new, changeset: changeset, email_required: email_required)
    end
  end

  def create(conn, %{"user" => user_params}) do
    # Check if registration is enabled
    unless AdminSettings.registration_enabled?() do
      conn
      |> put_flash(:error, "Registration is currently disabled.")
      |> redirect(to: ~p"/users/log-in")
    else
      email_required = AdminSettings.email_verification_required?()

      result =
        if email_required do
          # Email-only registration with magic link
          case Accounts.register_user(user_params) do
            {:ok, user} ->
              # Ensure first user gets admin role (even for email registration)
              Accounts.ensure_first_user_is_admin()

              {:ok, _} =
                Accounts.deliver_login_instructions(
                  user,
                  &url(~p"/users/log-in/#{&1}")
                )

              {:ok, user,
               "An email was sent to #{user.email}, please access it to confirm your account."}

            {:error, changeset} ->
              {:error, changeset}
          end
        else
          # Password-based registration
          case Accounts.register_user_with_password(user_params) do
            {:ok, user} ->
              # Ensure first user gets admin role
              Accounts.ensure_first_user_is_admin()
              {:ok, user, "Account created successfully. You can now log in."}

            {:error, changeset} ->
              {:error, changeset}
          end
        end

      case result do
        {:ok, _user, message} ->
          conn
          |> put_flash(:info, message)
          |> redirect(to: ~p"/users/log-in")

        {:error, %Ecto.Changeset{} = changeset} ->
          render(conn, :new, changeset: changeset, email_required: email_required)
      end
    end
  end
end
