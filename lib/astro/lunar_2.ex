defmodule Astro.Lunar.Dev do
  @moduledoc false

  @doc """
  Moonrise

  ## Arguments
  """

  # def moonrise(datetime, location, options \\ default_options())
  #
  # def moonrise(unquote(Cldr.Calendar.datetime()) = date_time, location, options) do
  #   time_zone = date_time.time_zone
  #   time_zone_database = Keyword.get(options, :time_zone_database)
  #
  #   do_moonrise(date_time, calendar, time_zone, location, time_zone_database)
  # end
  #
  # def moonrise(unquote(Cldr.Calendar.date()) = date, location, options) do
  #   location = Location.normalize_location(location)
  #   time_zone_database = Keyword.get(options, :time_zone_database)
  #   {:ok, time_zone} = TzWorld.timezone_at(location)
  #
  #   do_moonrise(date, calendar, time_zone, location, time_zone_database)
  # end
  #
  # def do_moonrise(date, calendar, time_zone, location, time_zone_database) do
  #   date
  #   |> Cldr.Calendar.date_to_iso_days()
  #   |> Lunar.moonrise(time_zone, location)
  #   |> Time.date_time_from_iso_days()
  #   |> DateTime.convert!(calendar)
  #   |> DateTime.from_naive!(time_zone, time_zone_database)
  # end
end