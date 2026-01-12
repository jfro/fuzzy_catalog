defmodule FuzzyCatalog.LibrariesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FuzzyCatalog.Ebooks.Libraries` context.
  """

  @doc """
  Generate a library.
  """
  def library_fixture(attrs \\ %{}) do
    {:ok, library} =
      attrs
      |> valid_library_attributes()
      |> FuzzyCatalog.Ebooks.Libraries.create_library()

    library
  end

  @doc """
  Generate valid library attributes with scan_mode variations.
  """
  def valid_library_attributes(attrs \\ %{}) do
    scan_mode = Map.get(attrs, :scan_mode, "manual")

    base_attrs = %{
      name: "Test Library #{System.unique_integer([:positive])}",
      path: "/tmp/test_library_#{System.unique_integer([:positive])}",
      scan_mode: scan_mode
    }

    # Add schedule if scan_mode is "scheduled"
    attrs_with_schedule =
      if scan_mode == "scheduled" do
        Map.put(base_attrs, :schedule, "0 */6 * * *")
      else
        base_attrs
      end

    Map.merge(attrs_with_schedule, attrs)
  end
end
