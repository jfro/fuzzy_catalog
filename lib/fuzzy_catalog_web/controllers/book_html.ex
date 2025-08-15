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
end
