defmodule FuzzyCatalog.Catalog.ExternalLibrarySync do
  @moduledoc """
  Service for synchronizing books from external libraries.

  Handles the coordination between external library providers and the local database,
  ensuring books are properly imported and added to the collection.
  """

  require Logger
  alias FuzzyCatalog.{Catalog, Collections}

  @doc """
  Synchronize books from all available external library providers.

  Returns a summary of the synchronization results.
  """
  def sync_all_providers do
    providers = get_available_providers()

    if Enum.empty?(providers) do
      Logger.info("No external library providers are available")
      {:ok, %{providers: [], total_books: 0, new_books: 0, errors: []}}
    else
      Logger.info(
        "Starting sync with #{length(providers)} provider(s): #{Enum.join(Enum.map(providers, & &1.provider_name()), ", ")}"
      )

      results = Enum.map(providers, &sync_provider/1)

      summary = %{
        providers: Enum.map(providers, & &1.provider_name()),
        total_books: Enum.sum(Enum.map(results, fn {_, stats} -> stats.total_books end)),
        new_books: Enum.sum(Enum.map(results, fn {_, stats} -> stats.new_books end)),
        errors: Enum.flat_map(results, fn {_, stats} -> stats.errors end)
      }

      Logger.info("Sync completed: #{summary.new_books}/#{summary.total_books} new books added")
      {:ok, summary}
    end
  end

  @doc """
  Synchronize books from a specific provider using streaming for efficient memory usage.
  """
  def sync_provider(provider_module) do
    Logger.info("Syncing books from #{provider_module.provider_name()}")

    case get_books_stream(provider_module) do
      {:ok, books_stream} ->
        Logger.info("Starting streaming sync from #{provider_module.provider_name()}")

        stats = %{
          provider: provider_module.provider_name(),
          total_books: 0,
          new_books: 0,
          errors: []
        }

        final_stats =
          books_stream
          |> Stream.with_index(1)
          |> Enum.reduce(stats, fn {book_data, index}, acc_stats ->
            # Log progress every 100 books
            if rem(index, 100) == 0 do
              Logger.info(
                "Processed #{index} books from #{provider_module.provider_name()} " <>
                  "(#{acc_stats.new_books} new, #{length(acc_stats.errors)} errors)"
              )
            end

            case sync_book(book_data) do
              {:ok, :new} ->
                %{
                  acc_stats
                  | total_books: acc_stats.total_books + 1,
                    new_books: acc_stats.new_books + 1
                }

              {:ok, :existing} ->
                %{acc_stats | total_books: acc_stats.total_books + 1}

              {:error, reason} ->
                error_msg = "Failed to sync book '#{book_data.title}': #{reason}"
                Logger.error(error_msg)

                %{
                  acc_stats
                  | total_books: acc_stats.total_books + 1,
                    errors: [error_msg | acc_stats.errors]
                }
            end
          end)

        Logger.info(
          "Completed sync from #{provider_module.provider_name()}: " <>
            "#{final_stats.new_books}/#{final_stats.total_books} new books added"
        )

        {provider_module, final_stats}

      {:error, reason} ->
        error_msg =
          "Failed to get books stream from #{provider_module.provider_name()}: #{reason}"

        Logger.error(error_msg)

        stats = %{
          provider: provider_module.provider_name(),
          total_books: 0,
          new_books: 0,
          errors: [error_msg]
        }

        {provider_module, stats}
    end
  end

  defp get_books_stream(provider_module) do
    if function_exported?(provider_module, :stream_books, 0) do
      Logger.debug("Using streaming API for #{provider_module.provider_name()}")
      provider_module.stream_books()
    else
      Logger.debug("Falling back to fetch_books for #{provider_module.provider_name()}")

      case provider_module.fetch_books() do
        {:ok, books} -> {:ok, Stream.map(books, & &1)}
        error -> error
      end
    end
  end

  defp sync_book(book_data) do
    # Try to find existing book by ISBN or title/author
    existing_book = find_existing_book(book_data)

    case existing_book do
      nil ->
        # Create new book
        case create_book_from_sync_data(book_data) do
          {:ok, book} ->
            # Add to collection with the media type from sync data
            case Collections.add_to_collection(book, book_data.media_type) do
              {:ok, _collection_item} ->
                Logger.debug(
                  "Added new book '#{book.title}' to collection as #{book_data.media_type}"
                )

                {:ok, :new}

              {:error, changeset} ->
                Logger.warning(
                  "Book '#{book.title}' created but failed to add to collection: #{inspect(changeset.errors)}"
                )

                {:ok, :new}
            end

          {:error, changeset} ->
            {:error, format_changeset_errors(changeset)}
        end

      book ->
        # Book exists, maybe update cover if we don't have one
        updated_book = maybe_update_cover(book, book_data)

        # Ensure it's in the collection with the correct media type
        if Collections.book_media_type_in_collection?(updated_book, book_data.media_type) do
          {:ok, :existing}
        else
          case Collections.add_to_collection(updated_book, book_data.media_type) do
            {:ok, _collection_item} ->
              Logger.debug(
                "Added existing book '#{updated_book.title}' to collection as #{book_data.media_type}"
              )

              {:ok, :existing}

            {:error, changeset} ->
              Logger.warning(
                "Failed to add existing book '#{updated_book.title}' to collection: #{inspect(changeset.errors)}"
              )

              {:ok, :existing}
          end
        end
    end
  end

  defp find_existing_book(book_data) do
    # First try by ISBN
    isbn_book =
      cond do
        book_data.isbn13 && book_data.isbn13 != "" ->
          Catalog.get_book_by_isbn(book_data.isbn13)

        book_data.isbn10 && book_data.isbn10 != "" ->
          Catalog.get_book_by_isbn(book_data.isbn10)

        true ->
          nil
      end

    case isbn_book do
      nil ->
        # Fallback to title and author match
        Catalog.find_book_by_title_and_author(book_data.title, book_data.author)

      book ->
        book
    end
  end

  defp create_book_from_sync_data(book_data) do
    attrs = %{
      title: book_data.title,
      author: book_data.author,
      isbn10: book_data.isbn10,
      isbn13: book_data.isbn13,
      publisher: book_data.publisher,
      publication_date: book_data.publication_date,
      pages: book_data.pages,
      cover_url: book_data.cover_url,
      subtitle: book_data.subtitle,
      description: book_data.description,
      genre: book_data.genre,
      series: book_data.series,
      series_number: book_data.series_number,
      original_title: book_data.original_title
    }

    Catalog.create_book(attrs)
  end

  defp get_available_providers do
    [
      FuzzyCatalog.Catalog.Providers.AudiobookshelfProvider
    ]
    |> Enum.filter(& &1.available?())
  end

  defp maybe_update_cover(book, book_data) do
    # Only update cover if book doesn't have one and sync data provides one
    if (is_nil(book.cover_url) or book.cover_url == "") and
         not is_nil(book_data.cover_url) and book_data.cover_url != "" do
      case Catalog.update_book(book, %{cover_url: book_data.cover_url}) do
        {:ok, updated_book} ->
          Logger.debug("Updated cover for existing book '#{book.title}'")
          updated_book

        {:error, _changeset} ->
          Logger.warning("Failed to update cover for book '#{book.title}'")
          book
      end
    else
      book
    end
  end

  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
