defmodule FuzzyCatalog.Ebooks do
  @moduledoc """
  The Ebooks context for managing ebook files.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Ebooks.Ebook

  @doc """
  Returns the list of ebooks.
  """
  def list_ebooks do
    Ebook
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single ebook.
  Raises `Ecto.NoResultsError` if the Ebook does not exist.
  """
  def get_ebook!(id) do
    Repo.get!(Ebook, id)
  end

  @doc """
  Creates an ebook.
  """
  def create_ebook(attrs \\ %{}) do
    %Ebook{}
    |> Ebook.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an ebook.
  """
  def update_ebook(%Ebook{} = ebook, attrs) do
    ebook
    |> Ebook.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Gets an ebook by file path.
  """
  def get_ebook_by_path(file_path) do
    Ebook
    |> where([e], e.file_path == ^file_path)
    |> Repo.one()
  end
end
