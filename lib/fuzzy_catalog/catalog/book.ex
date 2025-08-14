defmodule FuzzyCatalog.Catalog.Book do
  use Ecto.Schema
  import Ecto.Changeset

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
    field :series_number, :integer
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
    |> validate_number(:series_number, greater_than: 0)
  end
end
