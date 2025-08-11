defmodule Mix.Tasks.ListAudiobookshelfLibraries do
  @moduledoc """
  Lists available libraries from Audiobookshelf without fetching books.

  ## Examples

      # List all libraries
      mix list_audiobookshelf_libraries

  ## Configuration

  Requires environment variables:
  - AUDIOBOOKSHELF_URL: Base URL for Audiobookshelf instance
  - AUDIOBOOKSHELF_API_KEY: API key for authentication

  """

  use Mix.Task

  require Logger

  @shortdoc "Lists available Audiobookshelf libraries"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Fetching Audiobookshelf libraries...")

    config = Application.get_env(:fuzzy_catalog, :audiobookshelf, [])

    case {Keyword.get(config, :url), Keyword.get(config, :api_key)} do
      {url, api_key} when is_binary(url) and is_binary(api_key) and url != "" and api_key != "" ->
        base_url = String.trim_trailing(url, "/")

        case fetch_libraries(base_url, api_key) do
          {:ok, libraries} ->
            IO.puts("✓ Found #{length(libraries)} libraries:")
            IO.puts("")

            Enum.each(libraries, fn library ->
              IO.puts("  📚 #{library["name"]}")
              IO.puts("     ID: #{library["id"]}")
              IO.puts("     Media Type: #{library["mediaType"]}")

              if library["settings"] && library["settings"]["coverAspectRatio"] do
                IO.puts("     Cover Ratio: #{library["settings"]["coverAspectRatio"]}")
              end

              IO.puts("")
            end)

            IO.puts("To sync specific libraries, set:")
            library_names = Enum.map(libraries, & &1["name"])
            example_libs = Enum.take(library_names, 2) |> Enum.join(",")
            IO.puts("  export AUDIOBOOKSHELF_LIBRARIES=\"#{example_libs}\"")

          {:error, reason} ->
            IO.puts("✗ Failed to fetch libraries: #{reason}")
            System.halt(1)
        end

      _ ->
        IO.puts("✗ Configuration missing")
        IO.puts("\nPlease set environment variables:")
        IO.puts("  export AUDIOBOOKSHELF_URL=\"https://your-audiobookshelf-instance.com\"")
        IO.puts("  export AUDIOBOOKSHELF_API_KEY=\"your_api_key\"")
        System.halt(1)
    end
  end

  defp fetch_libraries(base_url, api_key) do
    url = "#{base_url}/api/libraries"
    headers = [{"Authorization", "Bearer #{api_key}"}]

    Logger.debug("Fetching Audiobookshelf libraries from #{url}")

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: %{"libraries" => libraries}}} ->
        {:ok, libraries}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Failed to fetch libraries: HTTP #{status} - #{inspect(body)}")
        {:error, "Failed to fetch libraries: HTTP #{status}"}

      {:error, exception} ->
        Logger.error("Request failed: #{inspect(exception)}")
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end
end
