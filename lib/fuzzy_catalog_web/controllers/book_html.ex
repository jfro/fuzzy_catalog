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
  Builds a URL with the specified view mode without any search/filter parameters.
  Used for the clear button functionality.
  """
  def build_clear_url(conn, _meta, view_mode) do
    # Only preserve view mode, clear all search/filter parameters
    query_params = %{"view" => view_mode}
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

  @doc """
  Returns the current sort field and direction from Flop metadata.
  """
  def current_sort(%Flop.Meta{
        flop: %Flop{order_by: order_by, order_directions: order_directions}
      })
      when is_list(order_by) and is_list(order_directions) do
    case {order_by, order_directions} do
      {[field], [direction]} when is_atom(field) and is_atom(direction) ->
        {field, direction}

      {[field], [direction]} when is_binary(field) and is_binary(direction) ->
        {String.to_existing_atom(field), String.to_existing_atom(direction)}

      # default
      _ ->
        {:title, :asc}
    end
  rescue
    # fallback if atom conversion fails
    ArgumentError -> {:title, :asc}
  end

  def current_sort(_), do: {:title, :asc}

  @doc """
  Returns available sort options as a list of {label, field, direction} tuples.
  """
  def sort_options do
    [
      {"Recently Added", :inserted_at, :desc},
      {"Title A-Z", :title, :asc},
      {"Title Z-A", :title, :desc},
      {"Author A-Z", :author, :asc},
      {"Author Z-A", :author, :desc},
      {"Publication Date (Newest)", :publication_date, :desc},
      {"Publication Date (Oldest)", :publication_date, :asc}
    ]
  end

  @doc """
  Returns the label for the current sort option.
  """
  def current_sort_label(meta) do
    {field, direction} = current_sort(meta)

    case {field, direction} do
      {:inserted_at, :desc} -> "Recently Added"
      {:title, :asc} -> "Title A-Z"
      {:title, :desc} -> "Title Z-A"
      {:author, :asc} -> "Author A-Z"
      {:author, :desc} -> "Author Z-A"
      {:publication_date, :desc} -> "Publication Date (Newest)"
      {:publication_date, :asc} -> "Publication Date (Oldest)"
      # fallback
      _ -> "Title A-Z"
    end
  end

  @doc """
  Builds a URL with the specified sort parameters while preserving search and view parameters.
  """
  def build_sort_url(conn, _meta, field, direction) do
    # Extract current parameters
    search_value =
      case conn.query_params do
        %{"filters" => %{"search" => search}} when is_binary(search) and search != "" -> search
        _ -> nil
      end

    view_mode = conn.query_params["view"] || "list"

    # Build query parameters with sort - Flop expects arrays for order_by and order_directions
    query_params = %{
      "order_by[]" => to_string(field),
      "order_directions[]" => to_string(direction),
      "view" => view_mode
    }

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
  Builds the pagination path preserving current view mode and search parameters.
  """
  def pagination_path(conn) do
    view_mode = conn.query_params["view"]

    search_value =
      case conn.query_params do
        %{"filters" => %{"search" => search}} when is_binary(search) and search != "" -> search
        _ -> nil
      end

    query_params = %{}

    query_params =
      if view_mode do
        Map.put(query_params, "view", view_mode)
      else
        query_params
      end

    query_params =
      if search_value do
        Map.put(query_params, "filters[search]", search_value)
      else
        query_params
      end

    case URI.encode_query(query_params) do
      "" -> ~p"/books"
      params -> "/books?#{params}"
    end
  end

  @doc """
  Parses flexible date input into ISO 8601 partial date string.
  Delegates to the centralized DateUtils module.
  """
  def parse_flexible_date_input(input) do
    FuzzyCatalog.DateUtils.parse_flexible_date_input(input)
  end

  @doc """
  Formats an ISO 8601 partial date string for display.
  Since we're storing ISO strings directly, this is mostly a pass-through.
  """
  def format_publication_date(nil), do: ""
  def format_publication_date(""), do: ""
  def format_publication_date(iso_string) when is_binary(iso_string), do: iso_string
  def format_publication_date(_), do: ""

  @doc """
  Builds an Audiobookshelf URL for a given external_id.

  Returns nil if Audiobookshelf is not configured or external_id is nil.

  ## Examples

      iex> audiobookshelf_url("abc123")
      "https://myserver.com/item/abc123"

      iex> audiobookshelf_url(nil)
      nil
  """
  def audiobookshelf_url(nil), do: nil
  def audiobookshelf_url(""), do: nil

  def audiobookshelf_url(external_id) when is_binary(external_id) do
    config = Application.get_env(:fuzzy_catalog, :audiobookshelf, [])

    case Keyword.get(config, :url) do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(url, "/")
        "#{base_url}/item/#{external_id}"

      _ ->
        nil
    end
  end

  def audiobookshelf_url(_), do: nil

  @doc """
  Builds a BookLore URL for a given external_id.

  Returns nil if BookLore is not configured or external_id is nil.

  ## Examples

      iex> booklore_url("123")
      "https://myserver.com/book/123"

      iex> booklore_url(nil)
      nil
  """
  def booklore_url(nil), do: nil
  def booklore_url(""), do: nil

  def booklore_url(external_id) when is_binary(external_id) do
    config = Application.get_env(:fuzzy_catalog, :booklore, [])

    case Keyword.get(config, :url) do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(url, "/")
        "#{base_url}/book/#{external_id}"

      _ ->
        nil
    end
  end

  def booklore_url(_), do: nil

  @doc """
  Builds a Calibre URL for a given external_id.

  Returns nil if Calibre is not configured or external_id is nil.

  ## Examples

      iex> calibre_url("123")
      "https://myserver.com/book/123"

      iex> calibre_url(nil)
      nil
  """
  def calibre_url(nil), do: nil
  def calibre_url(""), do: nil

  def calibre_url(external_id) when is_binary(external_id) do
    config = Application.get_env(:fuzzy_catalog, :calibre, [])

    case Keyword.get(config, :url) do
      url when is_binary(url) and url != "" ->
        base_url = String.trim_trailing(url, "/")
        "#{base_url}/book/#{external_id}"

      _ ->
        nil
    end
  end

  def calibre_url(_), do: nil
end
