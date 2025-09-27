defmodule FuzzyCatalog.Catalog.ExternalLibraryLink do
  use Ecto.Schema
  import Ecto.Changeset

  @media_types ~w(hardcover paperback audiobook ebook unspecified)
  @providers ~w(audiobookshelf calibre booklore)

  schema "external_library_links" do
    field :media_type, :string
    field :provider, :string
    field :external_id, :string

    belongs_to :book, FuzzyCatalog.Catalog.Book

    timestamps()
  end

  @doc """
  Returns the list of supported media types.
  """
  def media_types, do: @media_types

  @doc """
  Returns the list of supported providers.
  """
  def providers, do: @providers

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:book_id, :media_type, :provider, :external_id])
    |> validate_required([:book_id, :media_type, :provider, :external_id])
    |> validate_inclusion(:media_type, @media_types)
    |> validate_inclusion(:provider, @providers)
    |> foreign_key_constraint(:book_id)
    |> unique_constraint([:book_id, :media_type, :provider])
  end
end
