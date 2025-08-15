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
    field :publication_date, :date
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
end
