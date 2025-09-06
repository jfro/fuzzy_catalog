defmodule FuzzyCatalogWeb.AdminSettingsLive do
  use FuzzyCatalogWeb, :live_view

  require Logger
  alias FuzzyCatalog.{AdminSettings, Accounts, ProviderScheduler}

  defmodule SettingsForm do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :provider_refresh_interval, :string, default: "disabled"
      field :custom_interval, :string, default: ""
    end

    def changeset(form, attrs) do
      form
      |> cast(attrs, [:provider_refresh_interval, :custom_interval])
      |> validate_required([:provider_refresh_interval])
    end
  end

  @preset_intervals [
    {"Disabled", "disabled"},
    {"15 minutes", "15m"},
    {"30 minutes", "30m"},
    {"1 hour", "1h"},
    {"2 hours", "2h"},
    {"6 hours", "6h"},
    {"12 hours", "12h"},
    {"24 hours", "24h"},
    {"Custom", "custom"}
  ]

  @impl true
  def mount(_params, session, socket) do
    Logger.info("AdminSettingsLive mount called - connected: #{connected?(socket)}")

    # Get current scope from session like the auth plug does
    current_scope = get_current_scope_from_session(session)
    Logger.info("AdminSettingsLive current_scope: #{inspect(current_scope)}")

    # Verify user is admin
    if current_scope.user && Accounts.admin?(current_scope.user) &&
         Accounts.active?(current_scope.user) do
      # Get current settings
      current_interval = AdminSettings.get_provider_refresh_interval()
      is_custom = not Enum.any?(@preset_intervals, fn {_, value} -> value == current_interval end)

      socket =
        socket
        |> assign(:current_scope, current_scope)
        |> assign(:page_title, "Admin - Settings")
        |> assign(:preset_intervals, @preset_intervals)
        |> assign(:current_interval, current_interval)
        |> assign(:selected_preset, if(is_custom, do: "custom", else: current_interval))
        |> assign(:custom_interval, if(is_custom, do: current_interval, else: ""))
        |> assign(:changeset, build_changeset(current_interval, ""))
        |> assign(:saving, false)

      Logger.info("AdminSettingsLive mount completed successfully")
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
  def handle_event("validate_settings", %{"settings_form" => params}, socket) do
    Logger.debug("AdminSettingsLive: validate_settings params: #{inspect(params)}")
    
    changeset = build_changeset_from_params(params)
    selected_preset = Map.get(params, "provider_refresh_interval", "disabled")
    custom_interval = Map.get(params, "custom_interval", "")
    
    Logger.debug("AdminSettingsLive: selected_preset=#{selected_preset}, custom_interval=#{custom_interval}")

    socket =
      socket
      |> assign(:changeset, Map.put(changeset, :action, :validate))
      |> assign(:selected_preset, selected_preset)
      |> assign(:custom_interval, custom_interval)

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_settings", %{"settings_form" => params}, socket) do
    Logger.info("AdminSettingsLive: Saving settings - #{inspect(params)}")

    socket = assign(socket, :saving, true)

    changeset = build_changeset_from_params(params)

    if changeset.valid? do
      # Determine final interval value
      selected_preset = Map.get(params, "provider_refresh_interval", "disabled")

      final_interval =
        if selected_preset == "custom" do
          Map.get(params, "custom_interval", "")
        else
          selected_preset
        end

      Logger.info("AdminSettingsLive: Final interval value: #{final_interval}")

      # Validate the interval format
      case ProviderScheduler.validate_interval(final_interval) do
        {:ok, validated_interval} ->
          # Save to database
          case AdminSettings.set_provider_refresh_interval(validated_interval) do
            {:ok, _setting} ->
              Logger.info("AdminSettingsLive: Setting saved to database")

              # Update the scheduler immediately
              case ProviderScheduler.update_interval(validated_interval) do
                :ok ->
                  Logger.info("AdminSettingsLive: Scheduler updated successfully")

                  socket =
                    socket
                    |> put_flash(
                      :info,
                      "Settings saved successfully. Provider refresh interval updated to: #{validated_interval}"
                    )
                    |> assign(:current_interval, validated_interval)
                    |> assign(:saving, false)

                  {:noreply, socket}

                error ->
                  Logger.error("AdminSettingsLive: Failed to update scheduler: #{inspect(error)}")

                  socket =
                    socket
                    |> put_flash(
                      :error,
                      "Settings saved but failed to update scheduler. Please restart the application."
                    )
                    |> assign(:saving, false)

                  {:noreply, socket}
              end

            {:error, changeset} ->
              Logger.error(
                "AdminSettingsLive: Failed to save setting: #{inspect(changeset.errors)}"
              )

              socket =
                socket
                |> put_flash(
                  :error,
                  "Failed to save settings: #{format_changeset_errors(changeset)}"
                )
                |> assign(:saving, false)

              {:noreply, socket}
          end

        {:error, reason} ->
          Logger.error("AdminSettingsLive: Invalid interval: #{reason}")

          socket =
            socket
            |> put_flash(:error, "Invalid interval format: #{reason}")
            |> assign(:saving, false)

          {:noreply, socket}
      end
    else
      Logger.error("AdminSettingsLive: Form validation failed: #{inspect(changeset.errors)}")

      socket =
        socket
        |> assign(:changeset, Map.put(changeset, :action, :validate))
        |> put_flash(:error, "Please correct the errors below")
        |> assign(:saving, false)

      {:noreply, socket}
    end
  end

  defp build_changeset(provider_interval, custom_interval) do
    %SettingsForm{
      provider_refresh_interval: provider_interval,
      custom_interval: custom_interval
    }
    |> SettingsForm.changeset(%{})
    |> validate_provider_refresh_interval()
  end

  defp build_changeset_from_params(params) do
    %SettingsForm{}
    |> SettingsForm.changeset(params)
    |> validate_provider_refresh_interval()
  end

  defp validate_provider_refresh_interval(changeset) do
    selected_preset = Ecto.Changeset.get_field(changeset, :provider_refresh_interval)
    custom_interval = Ecto.Changeset.get_field(changeset, :custom_interval)

    final_interval =
      if selected_preset == "custom" do
        custom_interval || ""
      else
        selected_preset || "disabled"
      end

    case ProviderScheduler.validate_interval(final_interval) do
      {:ok, _} ->
        changeset

      {:error, reason} ->
        if selected_preset == "custom" do
          Ecto.Changeset.add_error(changeset, :custom_interval, reason)
        else
          Ecto.Changeset.add_error(changeset, :provider_refresh_interval, reason)
        end
    end
  end

  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
