defmodule FuzzyCatalog.Collections.Collection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "collections" do
    field :added_at, :utc_datetime
    field :notes, :string

    belongs_to :book, FuzzyCatalog.Catalog.Book

    timestamps()
  end

  @doc false
  def changeset(collection, attrs) do
    collection
    |> cast(attrs, [:book_id, :added_at, :notes])
    |> validate_required([:book_id])
    |> foreign_key_constraint(:book_id)
    |> unique_constraint([:book_id])
  end
end
