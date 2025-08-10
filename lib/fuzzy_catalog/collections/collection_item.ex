defmodule FuzzyCatalog.Collections.CollectionItem do
  use Ecto.Schema
  import Ecto.Changeset

  @media_types ~w(hardcover paperback audiobook ebook unspecified)

  schema "collection_items" do
    field :added_at, :utc_datetime
    field :notes, :string
    field :media_type, :string, default: "unspecified"

    belongs_to :user, FuzzyCatalog.Accounts.User
    belongs_to :book, FuzzyCatalog.Catalog.Book

    timestamps()
  end

  @doc """
  Returns the list of supported media types.
  
  Future enhancement: Could be populated from OpenLibrary API format hints.
  """
  def media_types, do: @media_types

  @doc false
  def changeset(collection_item, attrs) do
    collection_item
    |> cast(attrs, [:user_id, :book_id, :media_type, :added_at, :notes])
    |> validate_required([:user_id, :book_id, :media_type])
    |> validate_inclusion(:media_type, @media_types)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:book_id)
    |> unique_constraint([:user_id, :book_id, :media_type])
  end
end