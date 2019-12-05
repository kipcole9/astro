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
end
