defmodule Astro do
  alias Astro.{Time, Solar, Utils}

  @utc_zone "Etc/UTC"

  def sunrise(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :rise)
    sun_rise_or_set(location, date, options)
  end

  def sunset(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :set)
    sun_rise_or_set(location, date, options)
  end

  def sun_rise_or_set(location, date, options) when is_list(options) do
    options =
      default_options()
      |> Keyword.merge(options)
      |> Map.new

    sun_rise_or_set(location, date, options)
  end

  def sun_rise_or_set(%Geo.PointZ{} = location, %Date{} = date, options) do
    with {:ok, naive_datetime} <-
           NaiveDateTime.new(date.year, date.month, date.day, 0, 0, 0, {0, 0}, date.calendar) do
      sun_rise_or_set(location, naive_datetime, options)
    end
  end

  def sun_rise_or_set(%Geo.PointZ{} = location, %NaiveDateTime{} = datetime, options) do
    %{time_zone_database: time_zone_database} = options

    with {:ok, iso_datetime} <- NaiveDateTime.convert(datetime, Calendar.ISO),
         {:ok, time_zone} <- Time.timezone_at(location),
         {:ok, utc_datetime} <- DateTime.from_naive(iso_datetime, time_zone, time_zone_database) do
      sun_rise_or_set(location, utc_datetime, options)
    end
  end

  def sun_rise_or_set(%Geo.PointZ{} = location, %DateTime{} = datetime, options) do
    %{time_zone_database: time_zone_database} = options
    with {:ok, iso_datetime} <- DateTime.convert(datetime, Calendar.ISO),
         {:ok, utc_datetime} <- DateTime.shift_zone(iso_datetime, @utc_zone, time_zone_database),
         moment_of_sunrise = utc_sun_rise_or_set(utc_datetime, location, options),
         {:ok, utc_sunrise} <- Time.moment_to_datetime(moment_of_sunrise, utc_datetime),
         {:ok, zone_sunrise} <-
           Time.datetime_in_requested_zone(utc_sunrise, datetime.time_zone, location, options) do
      DateTime.convert(zone_sunrise, datetime.calendar)
    end
  end

  def sun_rise_or_set(location, datetime, options) do
    Utils.normalize_location(location)
    |> sun_rise_or_set(datetime, options)
  end

  def utc_sun_rise_or_set(utc_datetime, location, %{rise_or_set: :rise} = options) do
    Solar.utc_sunrise(utc_datetime, location, options)
  end

  def utc_sun_rise_or_set(utc_datetime, location, %{rise_or_set: :set} = options) do
    Solar.utc_sunset(utc_datetime, location, options)
  end

  def default_options do
    [
      solar_elevation: Solar.solar_elevation(:geometric),
      time_zone: :default,
      time_zone_database: Tzdata.TimeZoneDatabase
    ]
  end
end
