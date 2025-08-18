defmodule FuzzyCatalog.Catalog.Book do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {
    Flop.Schema,
    filterable: [:title, :author, :genre, :publisher, :series],
    sortable: [:title, :author, :publisher, :publication_date, :inserted_at],
    default_order: %{order_by: [:title], order_directions: [:asc]},
    default_limit: 20,
    max_limit: 100
  }

  schema "books" do
    field :title, :string
    field :author, :string
    field :upc, :string
    field :isbn10, :string
    field :isbn13, :string
    field :amazon_asin, :string
    field :cover_image_key, :string

    # Publishing Information
    field :publisher, :string
    field :publication_date, :string
    field :pages, :integer
    field :genre, :string

    # Content Details
    field :subtitle, :string
    field :description, :string
    field :series, :string
    field :series_number, :decimal
    field :original_title, :string

    has_many :collection_items, FuzzyCatalog.Collections.CollectionItem

    timestamps()
  end

  @doc false
  def changeset(book, attrs) do
    book
    |> cast(attrs, [
      :title,
      :author,
      :upc,
      :isbn10,
      :isbn13,
      :amazon_asin,
      :cover_image_key,
      :publisher,
      :publication_date,
      :pages,
      :genre,
      :subtitle,
      :description,
      :series,
      :series_number,
      :original_title
    ])
    |> validate_required([:title, :author])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:author, min: 1, max: 255)
    |> validate_number(:pages, greater_than: 0)
    |> validate_series_number()
    |> validate_publication_date()
  end

  defp validate_series_number(changeset) do
    validate_change(changeset, :series_number, fn :series_number, series_number ->
      cond do
        is_nil(series_number) -> []
        Decimal.compare(series_number, 0) in [:gt, :eq] -> []
        true -> [series_number: "must be greater than or equal to 0, got #{series_number}"]
      end
    end)
  end

  defp validate_publication_date(changeset) do
    validate_change(changeset, :publication_date, fn :publication_date, publication_date ->
      case parse_and_validate_iso_date(publication_date) do
        {:ok, _} ->
          []

        :error ->
          [
            publication_date:
              "must be a valid partial date (e.g., '2023', '2023-05', '2023-05-15')"
          ]
      end
    end)
  end

  # Parse and validate ISO 8601 partial date strings
  defp parse_and_validate_iso_date(nil), do: {:ok, nil}
  defp parse_and_validate_iso_date(""), do: {:ok, nil}

  defp parse_and_validate_iso_date(date_string) when is_binary(date_string) do
    trimmed = String.trim(date_string)
    current_year = Date.utc_today().year

    case String.split(trimmed, "-") do
      # Year only: "2023"
      [year_str] when byte_size(year_str) == 4 ->
        case Integer.parse(year_str) do
          {year, ""} when year >= 1000 and year <= current_year + 10 -> {:ok, trimmed}
          _ -> :error
        end

      # Year-month: "2023-05"
      [year_str, month_str] when byte_size(year_str) == 4 and byte_size(month_str) == 2 ->
        with {year, ""} <- Integer.parse(year_str),
             {month, ""} <- Integer.parse(month_str),
             true <- year >= 1000 and year <= current_year + 10,
             true <- month >= 1 and month <= 12 do
          {:ok, trimmed}
        else
          _ -> :error
        end

      # Full date: "2023-05-15"
      [year_str, month_str, day_str]
      when byte_size(year_str) == 4 and byte_size(month_str) == 2 and byte_size(day_str) == 2 ->
        case Date.from_iso8601(trimmed) do
          {:ok, %Date{year: year}} when year >= 1000 and year <= current_year + 10 ->
            {:ok, trimmed}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp parse_and_validate_iso_date(_), do: :error
end
