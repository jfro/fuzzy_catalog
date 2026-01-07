# Phase 2: Ebook Schema and Context

Create the core data model for ebook file management with comprehensive test coverage.

## Overview

The Ebook schema represents a physical ebook file on disk. It's an independent entity that optionally links to Books (metadata) but can exist standalone.

**Key Design Decisions:**
- Ebooks belong to users (user_id required)
- Ebooks optionally link to books (book_id optional)
- File path is unique per user
- Processing status tracks workflow state

## Step 2.1: Write Ebook Schema Tests

### Create Test File

**File:** `test/fuzzy_catalog/ebooks/ebook_test.exs`

```elixir
defmodule FuzzyCatalog.Ebooks.EbookTest do
  use FuzzyCatalog.DataCase, async: true

  alias FuzzyCatalog.Ebooks.Ebook
  import FuzzyCatalog.EbooksFixtures

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024000,
        file_hash: "abc123def456",
        user_id: user.id
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
    end

    test "requires file_path" do
      user = user_fixture()
      attrs = %{file_format: "epub", file_size: 1024, user_id: user.id}
      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires file_format" do
      user = user_fixture()
      attrs = %{file_path: "/path/to/book.epub", file_size: 1024, user_id: user.id}
      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_format: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires user_id" do
      attrs = %{file_path: "/path/to/book.epub", file_format: "epub", file_size: 1024}
      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates file_format is in allowed list" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.txt",
        file_format: "txt",
        file_size: 1024,
        user_id: user.id
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_format: ["is invalid"]} = errors_on(changeset)
    end

    test "validates file_size is positive" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: -100,
        user_id: user.id
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{file_size: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "accepts optional book_id for linking to existing book" do
      user = user_fixture()
      book = book_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        book_id: book.id,
        user_id: user.id
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :book_id) == book.id
    end

    test "accepts extracted metadata fields" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        user_id: user.id,
        extracted_title: "The Great Gatsby",
        extracted_author: "F. Scott Fitzgerald",
        extracted_isbn: "9780743273565",
        extracted_publisher: "Scribner"
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
    end

    test "accepts processing status fields" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        user_id: user.id,
        processing_status: "completed",
        last_processed_at: DateTime.utc_now()
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert changeset.valid?
    end

    test "validates processing_status is in allowed list" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024,
        user_id: user.id,
        processing_status: "invalid_status"
      }

      changeset = Ebook.changeset(%Ebook{}, attrs)
      assert %{processing_status: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "associations" do
    test "belongs_to book (optional)" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)
      assert %Ecto.Association.NotLoaded{} = ebook.book

      ebook_with_book = ebook |> Repo.preload(:book)
      assert is_nil(ebook_with_book.book)
    end

    test "can link to existing book" do
      user = user_fixture()
      book = book_fixture()
      ebook = ebook_fixture(user_id: user.id, book_id: book.id)
      ebook_with_book = ebook |> Repo.preload(:book)

      assert ebook_with_book.book.id == book.id
    end

    test "belongs_to user (required)" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)
      ebook_with_user = ebook |> Repo.preload(:user)

      assert ebook_with_user.user.id == user.id
    end
  end
end
```

---

## Step 2.2: Create Ebook Schema

**File:** `lib/fuzzy_catalog/ebooks/ebook.ex`

```elixir
defmodule FuzzyCatalog.Ebooks.Ebook do
  use Ecto.Schema
  import Ecto.Changeset

  @file_formats ~w(epub pdf)
  @processing_statuses ~w(pending processing completed failed)

  schema "ebooks" do
    # File Information (required)
    field :file_path, :string
    field :file_format, :string
    field :file_size, :integer
    field :file_hash, :string
    field :last_modified_at, :utc_datetime

    # Extracted Metadata (optional)
    field :extracted_title, :string
    field :extracted_author, :string
    field :extracted_isbn, :string
    field :extracted_publisher, :string
    field :extracted_language, :string
    field :extracted_description, :string

    # Processing Information
    field :processing_status, :string, default: "pending"
    field :processing_error, :string
    field :last_processed_at, :utc_datetime

    # Cover thumbnail (stored via Storage backend)
    field :cover_thumbnail_key, :string

    # Optional relationship to Book
    belongs_to :book, FuzzyCatalog.Catalog.Book

    # User ownership (ebooks belong to users)
    belongs_to :user, FuzzyCatalog.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(ebook, attrs) do
    ebook
    |> cast(attrs, [
      :file_path,
      :file_format,
      :file_size,
      :file_hash,
      :last_modified_at,
      :extracted_title,
      :extracted_author,
      :extracted_isbn,
      :extracted_publisher,
      :extracted_language,
      :extracted_description,
      :processing_status,
      :processing_error,
      :last_processed_at,
      :cover_thumbnail_key,
      :book_id,
      :user_id
    ])
    |> validate_required([:file_path, :file_format, :user_id])
    |> validate_inclusion(:file_format, @file_formats)
    |> validate_inclusion(:processing_status, @processing_statuses)
    |> validate_number(:file_size, greater_than: 0)
    |> foreign_key_constraint(:book_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:file_path, :user_id])
  end

  def file_formats, do: @file_formats
  def processing_statuses, do: @processing_statuses
end
```

---

## Step 2.3: Create Ebooks Migration

### Generate Migration

```bash
mix ecto.gen.migration create_ebooks
```

### Edit Migration

**File:** `priv/repo/migrations/YYYYMMDDHHMMSS_create_ebooks.exs`

```elixir
defmodule FuzzyCatalog.Repo.Migrations.CreateEbooks do
  use Ecto.Migration

  def change do
    create table(:ebooks) do
      # File Information
      add :file_path, :string, null: false
      add :file_format, :string, null: false
      add :file_size, :bigint
      add :file_hash, :string
      add :last_modified_at, :utc_datetime

      # Extracted Metadata
      add :extracted_title, :string
      add :extracted_author, :string
      add :extracted_isbn, :string
      add :extracted_publisher, :string
      add :extracted_language, :string
      add :extracted_description, :text

      # Processing Information
      add :processing_status, :string, default: "pending", null: false
      add :processing_error, :text
      add :last_processed_at, :utc_datetime

      # Cover thumbnail
      add :cover_thumbnail_key, :string

      # Relationships
      add :book_id, references(:books, on_delete: :nilify_all)
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:ebooks, [:user_id])
    create index(:ebooks, [:book_id])
    create index(:ebooks, [:file_hash])
    create index(:ebooks, [:processing_status])
    create unique_index(:ebooks, [:file_path, :user_id])
  end
end
```

### Run Migration

```bash
mix ecto.migrate
```

---

## Step 2.4: Write Ebooks Context Tests

**File:** `test/fuzzy_catalog/ebooks_test.exs`

```elixir
defmodule FuzzyCatalog.EbooksTest do
  use FuzzyCatalog.DataCase, async: true

  alias FuzzyCatalog.Ebooks
  import FuzzyCatalog.EbooksFixtures
  import FuzzyCatalog.AccountsFixtures

  describe "list_ebooks/1" do
    test "returns all ebooks for a user" do
      user = user_fixture()
      ebook1 = ebook_fixture(user_id: user.id)
      ebook2 = ebook_fixture(user_id: user.id)
      other_user = user_fixture()
      _other_user_ebook = ebook_fixture(user_id: other_user.id)

      ebooks = Ebooks.list_ebooks(user.id)

      assert length(ebooks) == 2
      assert Enum.any?(ebooks, &(&1.id == ebook1.id))
      assert Enum.any?(ebooks, &(&1.id == ebook2.id))
    end
  end

  describe "get_ebook!/2" do
    test "returns the ebook with given id for user" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)

      assert Ebooks.get_ebook!(ebook.id, user.id).id == ebook.id
    end

    test "raises if ebook doesn't belong to user" do
      user = user_fixture()
      other_user = user_fixture()
      ebook = ebook_fixture(user_id: other_user.id)

      assert_raise Ecto.NoResultsError, fn ->
        Ebooks.get_ebook!(ebook.id, user.id)
      end
    end
  end

  describe "create_ebook/1" do
    test "creates ebook with valid data" do
      user = user_fixture()
      attrs = %{
        file_path: "/path/to/book.epub",
        file_format: "epub",
        file_size: 1024000,
        user_id: user.id
      }

      assert {:ok, ebook} = Ebooks.create_ebook(attrs)
      assert ebook.file_path == "/path/to/book.epub"
      assert ebook.user_id == user.id
    end

    test "returns error with invalid data" do
      assert {:error, changeset} = Ebooks.create_ebook(%{})
      assert %{file_path: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_ebook/2" do
    test "updates ebook with valid data" do
      user = user_fixture()
      ebook = ebook_fixture(user_id: user.id)

      assert {:ok, updated} = Ebooks.update_ebook(ebook, %{
        extracted_title: "New Title",
        processing_status: "completed"
      })

      assert updated.extracted_title == "New Title"
      assert updated.processing_status == "completed"
    end
  end

  describe "get_ebook_by_path/2" do
    test "returns ebook by file path for user" do
      user = user_fixture()
      ebook = ebook_fixture(
        user_id: user.id,
        file_path: "/unique/path/book.epub"
      )

      assert found = Ebooks.get_ebook_by_path("/unique/path/book.epub", user.id)
      assert found.id == ebook.id
    end

    test "returns nil if path doesn't exist" do
      user = user_fixture()
      assert is_nil(Ebooks.get_ebook_by_path("/nonexistent.epub", user.id))
    end
  end
end
```

---

## Step 2.5: Implement Ebooks Context

**File:** `lib/fuzzy_catalog/ebooks.ex`

```elixir
defmodule FuzzyCatalog.Ebooks do
  @moduledoc """
  The Ebooks context for managing ebook files.
  """

  import Ecto.Query, warn: false
  alias FuzzyCatalog.Repo
  alias FuzzyCatalog.Ebooks.Ebook

  @doc """
  Returns the list of ebooks for a user.
  """
  def list_ebooks(user_id) do
    Ebook
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single ebook for a user.
  Raises `Ecto.NoResultsError` if the Ebook does not exist or doesn't belong to user.
  """
  def get_ebook!(id, user_id) do
    Ebook
    |> where([e], e.id == ^id and e.user_id == ^user_id)
    |> Repo.one!()
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
  Gets an ebook by file path for a user.
  """
  def get_ebook_by_path(file_path, user_id) do
    Ebook
    |> where([e], e.file_path == ^file_path and e.user_id == ^user_id)
    |> Repo.one()
  end
end
```

---

## Step 2.6: Create Test Fixtures

**File:** `test/support/fixtures/ebooks_fixtures.ex`

```elixir
defmodule FuzzyCatalog.EbooksFixtures do
  @moduledoc """
  Test helpers for creating ebook entities.
  """

  import FuzzyCatalog.AccountsFixtures
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Catalog

  def unique_file_path do
    "/test/ebooks/book_#{System.unique_integer([:positive])}.epub"
  end

  def valid_ebook_attributes(attrs \\ %{}) do
    user_id = Map.get_lazy(attrs, :user_id, fn ->
      user_fixture().id
    end)

    Enum.into(attrs, %{
      file_path: unique_file_path(),
      file_format: "epub",
      file_size: 1024000,
      file_hash: "abc123def456",
      user_id: user_id
    })
  end

  def ebook_fixture(attrs \\ %{}) do
    {:ok, ebook} =
      attrs
      |> valid_ebook_attributes()
      |> Ebooks.create_ebook()

    ebook
  end

  def book_fixture(attrs \\ %{}) do
    default_attrs = %{
      title: "Test Book #{System.unique_integer([:positive])}",
      author: "Test Author"
    }

    {:ok, book} =
      default_attrs
      |> Map.merge(attrs)
      |> Catalog.create_book_without_collection()

    book
  end
end
```

---

## Verification

Run all tests:

```bash
mix test test/fuzzy_catalog/ebooks/
mix test test/fuzzy_catalog/ebooks_test.exs
```

All tests should pass ✅

---

## Next Steps

Continue to [Phase 3: Metadata Extraction](./03-metadata-extraction.md) to implement EPUB and PDF parsing.
