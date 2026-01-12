defmodule FuzzyCatalogWeb.DirectoryTreeTest do
  use FuzzyCatalogWeb.ConnCase

  import Phoenix.LiveViewTest

  alias FuzzyCatalogWeb.DirectoryTree

  setup do
    # Create a temporary directory structure for testing
    tmp_dir = System.tmp_dir!()
    test_root = Path.join(tmp_dir, "tree_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(test_root)

    # Create some subdirectories
    File.mkdir_p!(Path.join(test_root, "books"))
    File.mkdir_p!(Path.join(test_root, "books/fiction"))
    File.mkdir_p!(Path.join(test_root, "books/non-fiction"))
    File.mkdir_p!(Path.join(test_root, "media"))

    on_exit(fn ->
      File.rm_rf!(test_root)
    end)

    %{test_root: test_root}
  end

  describe "directory tree component" do
    test "renders root directory", %{test_root: test_root} do
      assigns = %{
        id: "dir-tree",
        selected_path: nil,
        current_path: test_root,
        expanded_paths: MapSet.new()
      }

      html = render_component(&DirectoryTree.tree/1, assigns)

      assert html =~ test_root
    end

    test "shows subdirectories when path is valid directory", %{test_root: test_root} do
      assigns = %{
        id: "dir-tree",
        selected_path: nil,
        current_path: test_root,
        expanded_paths: MapSet.new([test_root])
      }

      html = render_component(&DirectoryTree.tree/1, assigns)

      assert html =~ "books"
      assert html =~ "media"
    end

    test "does not show files, only directories", %{test_root: test_root} do
      # Create a file
      File.write!(Path.join(test_root, "file.txt"), "content")

      assigns = %{
        id: "dir-tree",
        selected_path: nil,
        current_path: test_root,
        expanded_paths: MapSet.new([test_root])
      }

      html = render_component(&DirectoryTree.tree/1, assigns)

      refute html =~ "file.txt"
    end

    test "rejects path traversal attempts", %{test_root: test_root} do
      malicious_path = Path.join(test_root, "../../../etc")

      assert DirectoryTree.validate_path(malicious_path) ==
               {:error, "Invalid path: path traversal detected"}
    end

    test "handles non-existent directories", %{test_root: test_root} do
      non_existent = Path.join(test_root, "does_not_exist")

      assert DirectoryTree.validate_path(non_existent) == {:error, "Directory does not exist"}
    end

    test "nested directories expand correctly", %{test_root: test_root} do
      books_path = Path.join(test_root, "books")

      assigns = %{
        id: "dir-tree",
        selected_path: nil,
        current_path: test_root,
        expanded_paths: MapSet.new([test_root, books_path])
      }

      html = render_component(&DirectoryTree.tree/1, assigns)

      assert html =~ "fiction"
      assert html =~ "non-fiction"
    end
  end
end
