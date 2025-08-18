defmodule FuzzyCatalog.Repo.Migrations.ConvertPublicationDateToIsoStrings do
  use Ecto.Migration

  import Ecto.Query
  alias FuzzyCatalog.Repo

  def up do
    # Add new string column for ISO 8601 partial dates
    alter table(:books) do
      add :publication_date_new, :string
    end

    flush()

    # Convert existing Date values to ISO 8601 strings
    from(b in "books",
      where: not is_nil(b.publication_date),
      select: %{id: b.id, publication_date: b.publication_date}
    )
    |> Repo.all()
    |> Enum.each(fn %{id: id, publication_date: date} ->
      iso_string = convert_date_to_iso_string(date)

      if iso_string do
        from(b in "books", where: b.id == ^id)
        |> Repo.update_all(set: [publication_date_new: iso_string])
      end
    end)

    # Remove old date column and rename new column
    alter table(:books) do
      remove :publication_date
    end

    flush()

    rename table(:books), :publication_date_new, to: :publication_date
  end

  def down do
    # Add back the date column
    alter table(:books) do
      add :publication_date_old, :date
    end

    flush()

    # Convert ISO strings back to Date format (only for full dates)
    from(b in "books",
      where: not is_nil(b.publication_date),
      select: %{id: b.id, publication_date: b.publication_date}
    )
    |> Repo.all()
    |> Enum.each(fn %{id: id, publication_date: iso_string} ->
      date = convert_iso_string_to_date(iso_string)

      if date do
        from(b in "books", where: b.id == ^id)
        |> Repo.update_all(set: [publication_date_old: date])
      end
    end)

    # Remove string column and rename date column back
    alter table(:books) do
      remove :publication_date
    end

    flush()

    rename table(:books), :publication_date_old, to: :publication_date
  end

  # Helper functions for data conversion
  defp convert_date_to_iso_string(%Date{year: year, month: month, day: day}) do
    # Convert Date struct to ISO 8601 string
    year_str = String.pad_leading(to_string(year), 4, "0")
    month_str = String.pad_leading(to_string(month), 2, "0")
    day_str = String.pad_leading(to_string(day), 2, "0")
    "#{year_str}-#{month_str}-#{day_str}"
  end

  defp convert_date_to_iso_string(_), do: nil

  defp convert_iso_string_to_date(iso_string) when is_binary(iso_string) do
    # Only convert full ISO dates back to Date structs
    # Partial dates (year only, year-month) will be lost in the rollback
    case String.split(iso_string, "-") do
      [year, month, day]
      when byte_size(year) == 4 and byte_size(month) == 2 and byte_size(day) == 2 ->
        case Date.from_iso8601(iso_string) do
          {:ok, date} -> date
          {:error, _} -> nil
        end

      _ ->
        # Skip partial dates - they can't be converted back to Date
        nil
    end
  end

  defp convert_iso_string_to_date(_), do: nil
end
