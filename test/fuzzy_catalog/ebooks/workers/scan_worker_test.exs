defmodule FuzzyCatalog.Ebooks.Workers.ScanWorkerTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  import ExUnit.CaptureLog

  alias FuzzyCatalog.Ebooks.Workers.{ScanWorker, ProcessWorker}
  alias FuzzyCatalog.Ebooks
  import FuzzyCatalog.EbooksFixtures

  describe "perform/1" do
    @tag :tmp_dir
    test "discovers ebook files in directory", %{tmp_dir: tmp_dir} do
      # Create test files
      epub_path = Path.join(tmp_dir, "book1.epub")
      pdf_path = Path.join(tmp_dir, "book2.pdf")
      File.write!(epub_path, "fake epub content")
      File.write!(pdf_path, "fake pdf content")

      # Enqueue job
      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      # Verify ebooks were created
      ebooks = Ebooks.list_ebooks()
      assert length(ebooks) == 2

      paths = Enum.map(ebooks, & &1.file_path)
      assert epub_path in paths
      assert pdf_path in paths
    end

    @tag :tmp_dir
    test "scans recursively when enabled", %{tmp_dir: tmp_dir} do
      # Create nested structure
      subdir = Path.join(tmp_dir, "subfolder")
      File.mkdir_p!(subdir)

      File.write!(Path.join(tmp_dir, "root.epub"), "content")
      File.write!(Path.join(subdir, "nested.epub"), "content")

      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => true
               })

      ebooks = Ebooks.list_ebooks()
      assert length(ebooks) == 2
    end

    @tag :tmp_dir
    test "scans only top level when recursive is false", %{tmp_dir: tmp_dir} do
      # Create nested structure
      subdir = Path.join(tmp_dir, "subfolder")
      File.mkdir_p!(subdir)

      File.write!(Path.join(tmp_dir, "root.epub"), "content")
      File.write!(Path.join(subdir, "nested.epub"), "content")

      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      ebooks = Ebooks.list_ebooks()
      assert length(ebooks) == 1
    end

    @tag :tmp_dir
    test "skips already-scanned files", %{tmp_dir: tmp_dir} do
      # Create file
      epub_path = Path.join(tmp_dir, "existing.epub")
      File.write!(epub_path, "content")

      # Create existing ebook record
      _existing = ebook_fixture(file_path: epub_path)

      # Scan again
      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      # Should still only have 1 ebook
      assert length(Ebooks.list_ebooks()) == 1
    end

    @tag :tmp_dir
    test "enqueues ProcessWorker jobs for new ebooks", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "book.epub"), "content")

      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      # Check that ProcessWorker job was enqueued
      assert_enqueued(worker: ProcessWorker)
    end

    test "handles directory not found" do
      # Capture expected error log
      capture_log(fn ->
        assert {:error, reason} =
                 perform_job(ScanWorker, %{
                   "directory" => "/nonexistent/path",
                   "recursive" => false
                 })

        assert reason =~ "directory not found"
      end)
    end

    @tag :tmp_dir
    test "ignores non-ebook files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "readme.txt"), "content")
      File.write!(Path.join(tmp_dir, "image.jpg"), "content")

      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      assert length(Ebooks.list_ebooks()) == 0
    end
  end

  describe "calculate_file_hash/1" do
    @tag :tmp_dir
    test "calculates consistent hash for file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.epub")
      File.write!(path, "test content")

      hash1 = ScanWorker.calculate_file_hash(path)
      hash2 = ScanWorker.calculate_file_hash(path)

      assert hash1 == hash2
      assert is_binary(hash1)
      assert String.length(hash1) > 0
    end
  end
end
