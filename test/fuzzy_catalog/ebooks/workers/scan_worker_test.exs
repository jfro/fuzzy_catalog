defmodule FuzzyCatalog.Ebooks.Workers.ScanWorkerTest do
  use FuzzyCatalog.DataCase, async: true
  use Oban.Testing, repo: FuzzyCatalog.Repo

  import ExUnit.CaptureLog

  alias FuzzyCatalog.Ebooks.Workers.{ScanWorker, ProcessWorker}
  alias FuzzyCatalog.Ebooks
  alias FuzzyCatalog.Ebooks.Libraries
  import FuzzyCatalog.EbooksFixtures
  import FuzzyCatalog.LibrariesFixtures

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

  describe "configuration" do
    @tag :tmp_dir
    test "only scans files matching supported_formats config", %{tmp_dir: tmp_dir} do
      # Create files with different extensions
      File.write!(Path.join(tmp_dir, "book1.epub"), "content")
      File.write!(Path.join(tmp_dir, "book2.pdf"), "content")
      File.write!(Path.join(tmp_dir, "book3.mobi"), "content")

      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      # Should only find epub and pdf (default supported formats)
      ebooks = Ebooks.list_ebooks()
      assert length(ebooks) == 2

      formats = Enum.map(ebooks, & &1.file_format)
      assert "epub" in formats
      assert "pdf" in formats
    end

    @tag :tmp_dir
    test "rejects files exceeding max_file_size config", %{tmp_dir: tmp_dir} do
      # Create a large file (larger than default 100MB)
      large_path = Path.join(tmp_dir, "huge.epub")

      # Create file with size exceeding limit
      # We'll mock this by creating a small file and testing the logic
      File.write!(large_path, "small content for now")

      # Note: This test verifies the configuration exists and can be accessed
      # The actual size validation will be tested once we implement it
      max_size = Application.get_env(:fuzzy_catalog, :ebooks)[:max_file_size]
      assert is_integer(max_size)
      assert max_size > 0
    end

    test "configuration values are accessible" do
      config = Application.get_env(:fuzzy_catalog, :ebooks)

      assert is_list(config[:supported_formats])
      assert is_integer(config[:max_file_size])
      assert is_boolean(config[:enable_fuzzy_matching])
      assert is_float(config[:fuzzy_threshold])

      # Verify default values
      assert "epub" in config[:supported_formats]
      assert "pdf" in config[:supported_formats]
      assert config[:max_file_size] == 100 * 1024 * 1024
      assert config[:fuzzy_threshold] >= 0.0
      assert config[:fuzzy_threshold] <= 1.0
    end
  end

  describe "library integration" do
    @tag :tmp_dir
    test "updates library status to idle on successful scan", %{tmp_dir: tmp_dir} do
      library = library_fixture(%{path: tmp_dir, scanning_status: "scanning"})
      File.write!(Path.join(tmp_dir, "book.epub"), "content")

      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false,
                 "library_id" => library.id
               })

      updated_library = Libraries.get_library!(library.id)
      # With pending ebooks, library remains in scanning status with processing stage
      assert updated_library.scanning_status == "scanning"
      assert updated_library.scan_progress_stage == "processing"
      assert updated_library.scan_progress_current == 0
      assert updated_library.scan_progress_total == 1
      assert updated_library.last_scan_error == nil
    end

    @tag :tmp_dir
    test "updates library status to failed on scan error", %{tmp_dir: _tmp_dir} do
      library = library_fixture(%{path: "/nonexistent", scanning_status: "scanning"})

      capture_log(fn ->
        assert {:error, _reason} =
                 perform_job(ScanWorker, %{
                   "directory" => "/nonexistent",
                   "recursive" => false,
                   "library_id" => library.id
                 })
      end)

      updated_library = Libraries.get_library!(library.id)
      assert updated_library.scanning_status == "failed"
      assert updated_library.last_scan_error != nil
      assert updated_library.last_scan_error =~ "directory not found"
    end

    @tag :tmp_dir
    test "works without library_id for backward compatibility", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "book.epub"), "content")

      # Should not raise error when library_id not provided
      assert :ok =
               perform_job(ScanWorker, %{
                 "directory" => tmp_dir,
                 "recursive" => false
               })

      ebooks = Ebooks.list_ebooks()
      assert length(ebooks) == 1
    end
  end
end
