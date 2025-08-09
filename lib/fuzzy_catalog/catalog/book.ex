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
    field :cover_url, :string

    timestamps()
  end

  @doc false
  def changeset(book, attrs) do
    book
    |> cast(attrs, [:title, :author, :upc, :isbn10, :isbn13, :amazon_asin, :cover_url])
    |> validate_required([:title, :author])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:author, min: 1, max: 255)
  end
end
