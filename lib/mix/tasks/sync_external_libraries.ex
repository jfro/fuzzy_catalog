defmodule Mix.Tasks.SyncExternalLibraries do
  @moduledoc """
  Synchronizes books from external library providers.

  ## Examples

      # Sync from all available providers
      mix sync_external_libraries

  ## Configuration

  Audiobookshelf provider requires:
  - AUDIOBOOKSHELF_URL: Base URL for Audiobookshelf instance
  - AUDIOBOOKSHELF_API_KEY: API key for authentication
  - AUDIOBOOKSHELF_LIBRARIES: (optional) Comma-separated list of library names/IDs to sync

  Calibre provider requires:
  - CALIBRE_LIBRARY_PATH: Path to the Calibre library directory containing metadata.db

  """

  use Mix.Task

  alias FuzzyCatalog.Catalog.ExternalLibrarySync

  @shortdoc "Synchronizes books from external library providers"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Starting external library synchronization...")

    case ExternalLibrarySync.sync_all_providers() do
      {:ok, summary} ->
        IO.puts("\nSynchronization completed successfully!")
        IO.puts("Providers: #{Enum.join(summary.providers, ", ")}")
        IO.puts("Total books processed: #{summary.total_books}")
        IO.puts("New books added: #{summary.new_books}")

        if length(summary.errors) > 0 do
          IO.puts("\nErrors encountered:")
          Enum.each(summary.errors, &IO.puts("  - #{&1}"))
          System.halt(1)
        end
    end
  end
end
