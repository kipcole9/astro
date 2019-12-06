defmodule Astro.TestData do
  def sunrise(file) do
    File.read!("./test/support/#{file}.csv")
    |> String.replace(~r/#.*\n/, "")
    |> String.replace(~r/\t/, "")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.split(&1, ",", trim: true))
    |> Enum.map(&convert_to_integer/1)
  end

  defp convert_to_integer(row) do
    row
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_integer/1)
  end

  def solstice do
    File.read!("./test/support/solstice.csv")
    |> String.replace(~r/#.*\n/, "")
    |> String.replace(~r/\t/, "")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.split(&1, ",", trim: true))
    |> Enum.map(&trim_columns/1)
    |> Enum.map(fn [year, month, day, time] ->
      [String.to_integer(year), transform_month(month), String.to_integer(day), transform_time(time)]
    end)
  end

  defp transform_month("June"), do: :june
  defp transform_month("Dec"), do: :december

  defp transform_time(time) do
    time
    |> String.split(":", trim: true)
    |> Enum.map(&String.to_integer/1)
  end

  defp trim_columns(row) do
    row
    |> Enum.map(&String.trim/1)
  end

end
