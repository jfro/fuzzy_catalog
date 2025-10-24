defmodule FuzzyCatalogWeb.BookControllerTest do
  use FuzzyCatalogWeb.ConnCase, async: true

  describe "determine_media_type/1" do
    test "returns first suggested media type when available" do
      book_params = %{"suggested_media_types" => ["hardcover", "ebook"]}

      # Access the private function through the module
      media_type = FuzzyCatalogWeb.BookController.__determine_media_type_test__(book_params)

      assert media_type == "hardcover"
    end

    test "returns unspecified when suggested_media_types is empty list" do
      book_params = %{"suggested_media_types" => []}

      media_type = FuzzyCatalogWeb.BookController.__determine_media_type_test__(book_params)

      assert media_type == "unspecified"
    end

    test "returns unspecified when suggested_media_types is nil" do
      book_params = %{"suggested_media_types" => nil}

      media_type = FuzzyCatalogWeb.BookController.__determine_media_type_test__(book_params)

      assert media_type == "unspecified"
    end

    test "returns unspecified when suggested_media_types is missing" do
      book_params = %{}

      media_type = FuzzyCatalogWeb.BookController.__determine_media_type_test__(book_params)

      assert media_type == "unspecified"
    end

    test "returns first type when multiple types provided" do
      book_params = %{"suggested_media_types" => ["paperback", "hardcover", "ebook"]}

      media_type = FuzzyCatalogWeb.BookController.__determine_media_type_test__(book_params)

      assert media_type == "paperback"
    end
  end
end
