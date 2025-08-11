defmodule Mix.Tasks.TestAudiobookshelf do
  @moduledoc """
  Tests the Audiobookshelf API client without syncing to the database.

  ## Examples

      # Test connection and fetch books
      mix test_audiobookshelf

  ## Configuration

  Requires environment variables:
  - AUDIOBOOKSHELF_URL: Base URL for Audiobookshelf instance
  - AUDIOBOOKSHELF_API_KEY: API key for authentication
  - AUDIOBOOKSHELF_LIBRARIES: (optional) Comma-separated list of library names/IDs to sync

  """

  use Mix.Task

  alias FuzzyCatalog.Catalog.Providers.AudiobookshelfProvider

  @shortdoc "Tests Audiobookshelf API connection and fetches books"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Testing Audiobookshelf API connection...")
    IO.puts("Provider: #{AudiobookshelfProvider.provider_name()}")

    # Check if provider is available (configured)
    if AudiobookshelfProvider.available?() do
      IO.puts("✓ Configuration found")

      # Test fetching books
      IO.puts("\nFetching books from Audiobookshelf...")

      case AudiobookshelfProvider.fetch_books() do
        {:ok, books} ->
          IO.puts("✓ Successfully fetched #{length(books)} books")

          if length(books) > 0 do
            IO.puts("\nFirst few books:")

            books
            |> Enum.take(5)
            |> Enum.with_index(1)
            |> Enum.each(fn {book, index} ->
              IO.puts("  #{index}. \"#{book.title}\" by #{book.author}")
              IO.puts("     Media Type: #{book.media_type}")
              if book.isbn13, do: IO.puts("     ISBN13: #{book.isbn13}")
              if book.isbn10, do: IO.puts("     ISBN10: #{book.isbn10}")
              if book.series, do: IO.puts("     Series: #{book.series}")
              if book.publisher, do: IO.puts("     Publisher: #{book.publisher}")
              IO.puts("")
            end)

            if length(books) > 5 do
              IO.puts("  ... and #{length(books) - 5} more books")
            end
          else
            IO.puts("No books found in Audiobookshelf libraries")
          end

        {:error, reason} ->
          IO.puts("✗ Failed to fetch books: #{reason}")
          System.halt(1)
      end
    else
      IO.puts("✗ Configuration missing")
      IO.puts("\nPlease set environment variables:")
      IO.puts("  export AUDIOBOOKSHELF_URL=\"https://your-audiobookshelf-instance.com\"")
      IO.puts("  export AUDIOBOOKSHELF_API_KEY=\"your_api_key\"")
      System.halt(1)
    end
  end
end
