defmodule FuzzyCatalogWeb.BookHTML do
  use FuzzyCatalogWeb, :html

  embed_templates "book_html/*"

  @doc """
  Extracts the search value from Flop metadata filters.
  """
  def get_search_value(%Flop.Meta{flop: %Flop{filters: filters}}) do
    case Enum.find(filters, &(&1.field == :search)) do
      %Flop.Filter{value: value} when is_binary(value) -> value
      _ -> ""
    end
  end

  def get_search_value(_), do: ""

  @doc """
  Checks if there are any active search filters.
  """
  def has_search_filter?(%Flop.Meta{flop: %Flop{filters: filters}}) do
    Enum.any?(filters, fn
      %Flop.Filter{field: :search, value: value} when is_binary(value) and value != "" -> true
      _ -> false
    end)
  end

  def has_search_filter?(_), do: false

  @doc """
  Returns the current view mode, defaulting to 'list' if not specified.
  """
  def current_view_mode(assigns) do
    assigns[:view_mode] || "list"
  end

  @doc """
  Generates a URL for toggling between views while preserving current search/filter parameters.
  """
  def toggle_view_url(conn, meta, current_view) do
    target_view = if current_view == "grid", do: "list", else: "grid"
    build_view_url(conn, meta, target_view)
  end

  @doc """
  Builds a URL with the specified view mode while preserving search/filter parameters.
  """
  def build_view_url(conn, _meta, view_mode) do
    # Extract search value if it exists in the nested filters structure
    search_value =
      case conn.query_params do
        %{"filters" => %{"search" => search}} when is_binary(search) and search != "" -> search
        _ -> nil
      end

    # Build clean query parameters
    query_params = %{"view" => view_mode}

    query_params =
      if search_value do
        Map.put(query_params, "filters[search]", search_value)
      else
        query_params
      end

    encoded_params = URI.encode_query(query_params)

    case encoded_params do
      "" -> conn.request_path
      params -> "#{conn.request_path}?#{params}"
    end
  end

  @doc """
  Returns the icon name for the current view toggle button.
  """
  def view_toggle_icon("grid"), do: "hero-list-bullet"
  def view_toggle_icon(_), do: "hero-squares-2x2"

  @doc """
  Returns the label for the view toggle button.
  """
  def view_toggle_label("grid"), do: "List View"
  def view_toggle_label(_), do: "Grid View"
end
