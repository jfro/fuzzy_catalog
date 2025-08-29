defmodule FuzzyCatalogWeb.OIDCController do
  use FuzzyCatalogWeb, :controller
  require Logger

  alias FuzzyCatalog.Accounts
  alias FuzzyCatalog.Accounts.User
  alias FuzzyCatalogWeb.UserAuth

  def authorize(conn, _params) do
    config = Application.get_env(:fuzzy_catalog, :oidc)
    
    Logger.info("OIDC authorize initiated with config: #{inspect(config, pretty: true)}")
    
    case Assent.Strategy.OIDC.authorize_url(config) do
      {:ok, %{url: url, session_params: session_params}} ->
        Logger.info("OIDC authorize successful, redirecting to: #{url}")
        Logger.info("Session params to store: #{inspect(session_params, pretty: true)}")
        
        conn
        |> put_session(:oidc_state, session_params["state"])
        |> put_session(:oidc_nonce, session_params["nonce"])
        |> put_session(:oidc_session_params, session_params)  # Store full session params as backup
        |> redirect(external: url)

      {:error, error} ->
        Logger.error("OIDC authorize failed: #{inspect(error, pretty: true)}")
        conn
        |> put_flash(:error, "Authentication service is currently unavailable. Please try again later or contact support.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def callback(conn, params) do
    config = Application.get_env(:fuzzy_catalog, :oidc)
    
    # Try to get session params from different sources
    state = get_session(conn, :oidc_state)
    nonce = get_session(conn, :oidc_nonce)
    stored_session_params = get_session(conn, :oidc_session_params)
    
    Logger.info("OIDC callback received with params: #{inspect(Map.drop(params, ["code"]), pretty: true)}")
    Logger.info("Retrieved session state: #{inspect(state)}")
    Logger.info("Retrieved session nonce: #{inspect(nonce)}")
    Logger.info("Stored session params: #{inspect(stored_session_params, pretty: true)}")
    
    # Use stored session params if individual values are missing, or fallback to params
    session_params = cond do
      state && nonce ->
        %{
          "state" => state,
          "nonce" => nonce
        }
      stored_session_params ->
        # Convert atom keys to string keys if needed
        stored_session_params
        |> Enum.map(fn 
          {k, v} when is_atom(k) -> {Atom.to_string(k), v}
          {k, v} -> {k, v}
        end)
        |> Enum.into(%{})
      params["state"] ->
        # Fallback: use state from callback params if session is lost
        Logger.warning("Using state from callback params as fallback - session may have been lost")
        %{
          "state" => params["state"],
          "nonce" => nil
        }
      true ->
        %{}
    end
    
    Logger.info("Final session params for callback: #{inspect(session_params, pretty: true)}")
    
    # Check if we have required state parameter
    state_value = session_params["state"]
    if is_nil(state_value) do
      Logger.error("OIDC callback missing state parameter - possible session issue")
      conn
      |> put_flash(:error, "Authentication session expired. Please try signing in again.")
      |> redirect(to: ~p"/users/log-in")
    else
      # Convert session_params to atom keys for Assent compatibility
      session_params_atoms = session_params
      |> Enum.map(fn 
        {"state", v} -> {:state, v}
        {"nonce", v} -> {:nonce, v}
        {k, v} -> {String.to_atom(k), v}
      end)
      |> Enum.into(%{})
      
      # Merge session_params into config for Assent
      config_with_session = Keyword.put(config, :session_params, session_params_atoms)
      Logger.info("Config with session params (atom keys): #{inspect(config_with_session, pretty: true)}")
      
      case Assent.Strategy.OIDC.callback(config_with_session, params) do
        {:ok, %{user: user_info, token: token}} ->
          Logger.info("OIDC callback successful for user: #{inspect(user_info["email"])}")
          handle_successful_auth(conn, user_info, token)

        {:error, error} ->
          Logger.error("OIDC callback failed: #{inspect(error, pretty: true)}")
          
          error_message = case error do
            %Assent.MissingConfigError{key: :session_params} ->
              "Authentication session expired. Please try signing in again."
            %{error: "invalid_grant"} -> 
              "Authentication expired or invalid. Please try signing in again."
            %{error: "access_denied"} -> 
              "Access was denied. Please try again or contact support."
            %{error: error_type} when is_binary(error_type) -> 
              "Authentication failed: #{String.replace(error_type, "_", " ")}. Please try again."
            _ -> 
              "Authentication failed. Please try again or contact support if the problem persists."
          end
          
          conn
          |> put_flash(:error, error_message)
          |> redirect(to: ~p"/users/log-in")
      end
    end
  end

  defp handle_successful_auth(conn, user_info, token) do
    email = user_info["email"]
    provider_uid = user_info["sub"]
    provider = "oidc"
    
    Logger.info("Handling successful OIDC auth for email: #{email}, provider_uid: #{provider_uid}")
    
    case find_or_create_user(email, provider, provider_uid, token) do
      {:ok, user} ->
        Logger.info("OIDC user login successful for user ID: #{user.id}")
        conn
        |> delete_session(:oidc_state)
        |> delete_session(:oidc_nonce)
        |> delete_session(:oidc_session_params)
        |> UserAuth.log_in_user(user)

      {:error, :email_taken} ->
        Logger.warning("OIDC login blocked - email #{email} already exists with different provider")
        conn
        |> put_flash(:error, "An account with this email already exists. Please log in with your existing account.")
        |> redirect(to: ~p"/users/log-in")

      {:error, changeset} ->
        Logger.error("OIDC user creation failed: #{inspect(changeset.errors, pretty: true)}")
        conn
        |> put_flash(:error, "Failed to create your account. Please try again or contact support.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  defp find_or_create_user(email, provider, provider_uid, token) do
    Logger.debug("Finding or creating user for email: #{email}, provider: #{provider}, provider_uid: #{provider_uid}")
    
    case Accounts.get_user_by_provider(provider, provider_uid) do
      %User{} = user ->
        Logger.debug("Found existing OIDC user: #{user.id}")
        {:ok, user}

      nil ->
        Logger.debug("No existing OIDC user found, checking for email conflicts")
        case Accounts.get_user_by_email(email) do
          %User{provider: nil} ->
            Logger.debug("Email exists with local account, blocking OIDC registration")
            {:error, :email_taken}

          %User{} = user ->
            Logger.debug("Email exists with OIDC account, using existing user: #{user.id}")
            {:ok, user}

          nil ->
            Logger.debug("Creating new OIDC user")
            create_oidc_user(email, provider, provider_uid, token)
        end
    end
  end

  defp create_oidc_user(email, provider, provider_uid, token) do
    # Check if this is the first user (should be admin)
    is_first_user = Accounts.first_user?()
    role = if is_first_user, do: "admin", else: "user"
    
    Logger.info("Creating OIDC user - first user: #{is_first_user}, role: #{role}")
    
    attrs = %{
      email: email,
      provider: provider,
      provider_uid: provider_uid,
      provider_token: token["access_token"],
      role: role,
      status: "active",
      confirmed_at: DateTime.utc_now(:second)
    }

    Logger.debug("Creating OIDC user with attrs: #{inspect(Map.drop(attrs, [:provider_token]), pretty: true)}")

    result = %User{}
    |> User.oidc_registration_changeset(attrs)
    |> Accounts.create_user_from_changeset()

    case result do
      {:ok, user} ->
        Logger.info("Successfully created OIDC user: #{user.id}")
        {:ok, user}
      {:error, changeset} ->
        Logger.error("Failed to create OIDC user: #{inspect(changeset.errors, pretty: true)}")
        {:error, changeset}
    end
  end
end