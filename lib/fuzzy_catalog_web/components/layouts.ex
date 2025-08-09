defmodule FuzzyCatalogWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FuzzyCatalogWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="navbar bg-base-100 shadow-lg">
      <div class="flex-1">
        <.link navigate={~p"/"} class="btn btn-ghost normal-case text-xl">
          <.icon name="hero-book-open" class="h-6 w-6 mr-2" /> FuzzyCatalog
        </.link>
      </div>
      <div class="flex-none">
        <ul class="menu menu-horizontal px-1">
          <li>
            <.link navigate={~p"/"} class="btn btn-ghost">
              <.icon name="hero-home" class="h-4 w-4 mr-1" /> Home
            </.link>
          </li>
          <li>
            <.link navigate={~p"/books"} class="btn btn-ghost">
              <.icon name="hero-book-open" class="h-4 w-4 mr-1" /> Books
            </.link>
          </li>
          <li>
            <.link navigate={~p"/books/new"} class="btn btn-ghost">
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> Add Book
            </.link>
          </li>
          <%= if @current_scope do %>
            <li>
              <.link navigate={~p"/collections"} class="btn btn-ghost">
                <.icon name="hero-heart" class="h-4 w-4 mr-1" /> My Collection
              </.link>
            </li>
          <% end %>
          <%= if @current_scope do %>
            <li>
              <details>
                <summary class="btn btn-ghost">
                  <.icon name="hero-user-circle" class="h-4 w-4 mr-1" />
                  {@current_scope.user.email}
                </summary>
                <ul class="p-2 bg-base-100 rounded-t-none z-50">
                  <li>
                    <.link href={~p"/users/settings"} class="btn btn-ghost btn-sm">
                      <.icon name="hero-cog-6-tooth" class="h-4 w-4 mr-1" /> Account Settings
                    </.link>
                  </li>
                  <li class="mb-2">
                    <span class="text-xs text-base-content/60 px-3">Theme</span>
                  </li>
                  <li>
                    <div class="px-2">
                      <.theme_toggle />
                    </div>
                  </li>
                  <li>
                    <.link href={~p"/users/log-out"} method="delete" class="btn btn-ghost btn-sm">
                      <.icon name="hero-arrow-right-on-rectangle" class="h-4 w-4 mr-1" /> Log out
                    </.link>
                  </li>
                </ul>
              </details>
            </li>
          <% else %>
            <li>
              <.link href={~p"/users/log-in"} class="btn btn-ghost">
                <.icon name="hero-arrow-right-on-rectangle" class="h-4 w-4 mr-1" /> Log in
              </.link>
            </li>
            <li>
              <.link href={~p"/users/register"} class="btn btn-primary">
                <.icon name="hero-user-plus" class="h-4 w-4 mr-1" /> Register
              </.link>
            </li>
          <% end %>
        </ul>
      </div>
    </div>

    <main class="container mx-auto px-4 py-8">
      <div class="max-w-7xl mx-auto space-y-6">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
