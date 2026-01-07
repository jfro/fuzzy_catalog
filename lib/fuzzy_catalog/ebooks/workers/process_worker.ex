defmodule FuzzyCatalog.Ebooks.Workers.ProcessWorker do
  @moduledoc """
  Oban worker that processes ebook files and extracts metadata.

  This is a stub - implementation will be added in Phase 5.
  """

  use Oban.Worker,
    queue: :ebook_process,
    max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"ebook_id" => _ebook_id}}) do
    # Stub implementation - will be filled in during Phase 5
    :ok
  end
end
