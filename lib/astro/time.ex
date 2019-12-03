defmodule Astro.Time do
  @moduledoc """
  Calculations converting between geometry and time

  All public functions use degrees as their input
  parameters

  Time is a fraction of a day after UTC

  """

  alias Astro.Location

  @julian_day_jan_1_2000 2_451_545.0
  @julian_days_per_century 36525.0
  @utc_zone "Etc/UTC"

  @doc """
  Calculates the time zone from a longitude
  in degrees

  ## Arguments

  * `lng` is a longitude in degrees

  ## Returns

  * `time` as a fraction of a day after UTC

  """
  def offset(lng) do
    lng / 360.0
  end

  def utc_from_local(local_time, %Location{offset: offset}) do
    local_time - offset
  end

  def local_from_utc(utc_time, %Location{offset: offset}) do
    utc_time + offset
  end

  def standard_from_utc(utc_time, %Location{zone: zone}) do
    utc_time + zone
  end

  def utc_from_standard(standard_time, %Location{zone: zone}) do
    standard_time - zone
  end

  def julian_centuries_from_julian_day(julian_day) do
    (julian_day - @julian_day_jan_1_2000) / @julian_days_per_century
  end

  def julian_day_from_julian_centuries(julian_centuries) do
    julian_centuries * @julian_days_per_century + @julian_day_jan_1_2000
  end

  def julian_day_from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    div((1461 * (year + 4800 + div(month - 14, 12))), 4) +
    div((367 * (month - 2 - 12 * div(month - 14, 12))), 12) -
    div(3 * div(year + 4900 + div(month - 14, 12), 100), 4) +
    day - 32075 + 0.5
  end

  def julian_day_from_date(%{year: _, month: _, day: _, calendar: _} = date) do
    {:ok, iso_date} = Date.convert(date, Calendar.ISO)
    julian_day_from_date(iso_date)
  end

  def ajd(date) do
    julian_day_from_date(date)
  end

  def mjd(date) do
    ajd(date) - 2_400_000.5
  end

  def moment_to_datetime(time_of_day, %{
        year: year,
        month: month,
        day: day,
        calendar: Calendar.ISO
      }) do
    with {hours, minutes, seconds} <- to_hms(time_of_day),
         {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hours, minutes, seconds, 0) do
      DateTime.from_naive(naive_datetime, @utc_zone)
    end
  end

  def to_hms(time_of_day) do
    hours = trunc(time_of_day)
    minutes = (time_of_day - hours) * 60.0
    seconds = (minutes - trunc(minutes)) * 60.0

    minutes = trunc(minutes)
    seconds = trunc(seconds)

    {hours, minutes, seconds}
  end

  def datetime_in_requested_zone(utc_event_time, original_time_zone, location, options) do
    %{time_zone_database: time_zone_database} = options

    case Map.fetch!(options, :time_zone) do
      :utc ->
        {:ok, utc_event_time}

      :default ->
        DateTime.shift_zone(utc_event_time, original_time_zone, time_zone_database)

      :local ->
        with {:ok, time_zone} <- timezone_at(location) do
          DateTime.shift_zone(utc_event_time, time_zone, time_zone_database)
        end

      time_zone when is_binary(time_zone) ->
        DateTime.shift_zone(utc_event_time, time_zone, time_zone_database)
    end
  end

  def timezone_at(%Geo.PointZ{} = location) do
    location = %Geo.Point{coordinates: Tuple.delete_at(location.coordinates, 2)}
    timezone_at(location)
  end

  def timezone_at(%Geo.Point{} = location) do
    TzWorld.timezone_at(location)
  end
end
