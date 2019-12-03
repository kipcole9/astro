defmodule Astro do
  import Astro.Guards

  alias Astro.{Time, Solar}

  @utc_zone "Etc/UTC"

  def sunrise(location, date \\ Date.utc_today(), options \\ default_options())

  def sunrise(location, date, options) when is_list(options) do
    options =
      default_options()
      |> Keyword.merge(options)
      |> Map.new

    sunrise(location, date, options)
  end

  def sunrise({lng, lat, alt}, date, options) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    sunrise(%Geo.PointZ{coordinates: {lng, lat, alt}}, date, options)
  end

  def sunrise({lng, lat}, date, options) when is_lat(lat) and is_lng(lng) do
    sunrise(%Geo.PointZ{coordinates: {lng, lat, 0.0}}, date, options)
  end

  def sunrise(%Geo.Point{coordinates: {lng, lat}}, date, options)
      when is_lat(lat) and is_lng(lng) do
    sunrise(%Geo.PointZ{coordinates: {lng, lat, 0.0}}, date, options)
  end

  def sunrise(%Geo.PointZ{} = location, %Date{} = date, options) do
    with {:ok, naive_datetime} <-
           NaiveDateTime.new(date.year, date.month, date.day, 0, 0, 0, {0, 0}, date.calendar) do
      sunrise(location, naive_datetime, options)
    end
  end

  def sunrise(%Geo.PointZ{} = location, %NaiveDateTime{} = datetime, options) do
    %{time_zone_database: time_zone_database} = options

    with {:ok, iso_datetime} <- NaiveDateTime.convert(datetime, Calendar.ISO),
         {:ok, time_zone} <- Time.timezone_at(location),
         {:ok, utc_datetime} <- DateTime.from_naive(iso_datetime, time_zone, time_zone_database) do
      sunrise(location, utc_datetime, options)
    end
  end

  def sunrise(%Geo.PointZ{} = location, %DateTime{} = datetime, options) do
    %{time_zone_database: time_zone_database} = options

    with {:ok, iso_datetime} <- DateTime.convert(datetime, Calendar.ISO),
         {:ok, utc_datetime} <- DateTime.shift_zone(iso_datetime, @utc_zone, time_zone_database),
         moment_of_sunrise = Solar.utc_sunrise(utc_datetime, location, options),
         {:ok, utc_sunrise} <- Time.moment_to_datetime(moment_of_sunrise, utc_datetime),
         {:ok, zone_sunrise} <-
           Time.datetime_in_requested_zone(utc_sunrise, datetime.time_zone, location, options) do
      DateTime.convert(zone_sunrise, datetime.calendar)
    end
  end

  def default_options do
    [
      solar_elevation: Solar.solar_elevation(:geometric),
      time_zone: :default,
      time_zone_database: Tzdata.TimeZoneDatabase
    ]
  end
end
