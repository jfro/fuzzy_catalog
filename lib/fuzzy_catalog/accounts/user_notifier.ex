defmodule FuzzyCatalog.Accounts.UserNotifier do
  import Swoosh.Email

  alias FuzzyCatalog.Mailer
  alias FuzzyCatalog.Accounts.User

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    from_name = Application.get_env(:fuzzy_catalog, :email)[:from_name]
    from_address = Application.get_env(:fuzzy_catalog, :email)[:from_address]
    
    email =
      new()
      |> to(recipient)
      |> from({from_name, from_address})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  @doc """
  Deliver account confirmation instructions to a logged-in user.
  """
  def deliver_user_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your account", """

    ==============================

    Hi #{user.email},

    Please confirm your account by visiting the URL below:

    #{url}

    If you didn't create this account, please ignore this email.

    ==============================
    """)
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end
end
