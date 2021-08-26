defmodule Astro.Moon.TestData do
  @moon_phase "moon_phase_2021"
  @year 2021

  def moon_phase do
    File.read!("./test/data/#{@moon_phase}.csv")
    |> String.replace(~r/#.*\n/, "")
    |> String.replace(~r/\t/, "")
    |> String.split("\n")
    |> tl()
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.split(&1, ",", trim: true))
    |> Enum.map(&Enum.map(&1, fn l -> String.trim(l) end))
    |> Enum.map(&transform/1)
  end

  def transform([phase, month, day, hour, minute]) do
    [phase(phase), date(month, day), time(hour, minute)]
  end

  def phase(phase) do
    String.to_atom(phase)
  end

  def date(month, day) do
    Date.new!(@year, lookup(month), String.to_integer(day))
  end

  def time(hour, minute) do
    Time.new!(String.to_integer(hour), String.to_integer(minute), 0)
  end

  def lookup("Jan"), do: 1
  def lookup("Feb"), do: 2
  def lookup("Mar"), do: 3
  def lookup("Apr"), do: 4
  def lookup("May"), do: 5
  def lookup("Jun"), do: 6
  def lookup("Jul"), do: 7
  def lookup("Aug"), do: 8
  def lookup("Sep"), do: 9
  def lookup("Oct"), do: 10
  def lookup("Nov"), do: 11
  def lookup("Dec"), do: 12

end