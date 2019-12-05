defmodule Astro.Time do
  @moduledoc """
  Calculations converting between geometry and time

  All public functions use degrees as their input
  parameters

  Time is a fraction of a day after UTC

  """

  @julian_day_jan_1_2000 2_451_545.0
  @julian_days_per_century 36525.0
  @utc_zone "Etc/UTC"

  @minutes_per_degree 4
  @seconds_per_minute 60
  @seconds_per_hour @seconds_per_minute * 60
  @seconds_per_day @seconds_per_hour * 24

  def julian_day_from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    div(1461 * (year + 4800 + div(month - 14, 12)), 4) +
      div(367 * (month - 2 - 12 * div(month - 14, 12)), 12) -
      div(3 * div(year + 4900 + div(month - 14, 12), 100), 4) +
      day - 32075 - 0.5
  end

  def julian_day_from_date(%{year: _, month: _, day: _, calendar: _} = date) do
    {:ok, iso_date} = Date.convert(date, Calendar.ISO)
    julian_day_from_date(iso_date)
  end

  def julian_centuries_from_julian_day(julian_day) do
    (julian_day - @julian_day_jan_1_2000) / @julian_days_per_century
  end

  def julian_day_from_julian_centuries(julian_centuries) do
    julian_centuries * @julian_days_per_century + @julian_day_jan_1_2000
  end

  def ajd(date) do
    julian_day_from_date(date)
  end

  def mjd(date) do
    ajd(date) - 2_400_000.5
  end

  def moment_to_datetime(time_of_day, %{year: year, month: month, day: day}) do
    with {hours, minutes, seconds} <- to_hms(time_of_day),
         {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hours, minutes, seconds, 0) do
      DateTime.from_naive(naive_datetime, @utc_zone)
    end
  end

  @doc false
  def adjust_for_wraparound(%DateTime{} = datetime, location, %{rise_or_set: :rise}) do
    # sunrise after 6pm indicates the UTC date has occurred earlier
    if datetime.hour + local_hour_offset(datetime, location) > 18 do
      {:ok, DateTime.add(datetime, -@seconds_per_day, :second)}
    else
      {:ok, datetime}
    end
  end

  def adjust_for_wraparound(%DateTime{} = datetime, location, %{rise_or_set: :set}) do
    # sunset before 6am indicates the UTC date has occurred later
    if datetime.hour + local_hour_offset(datetime, location) < 6 do
      {:ok, DateTime.add(datetime, @seconds_per_day, :second)}
    else
      {:ok, datetime}
    end
  end

  def local_hour_offset(datetime, location) do
    gregorian_seconds = datetime_to_gregorian_seconds(datetime)

    local_mean_time_offset =
      local_mean_time_offset(location, gregorian_seconds, datetime.time_zone)

    (local_mean_time_offset + datetime.std_offset) / @seconds_per_hour
  end

  def to_hms(time_of_day) do
    hours = trunc(time_of_day)
    minutes = trunc((time_of_day - hours) * 60.0)

    {hours, minutes, 0}
  end

  def datetime_to_gregorian_seconds(%DateTime{} = datetime) do
    %{year: year, month: month, day: day, hour: hour, minute: minute, second: second} = datetime
    :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}})
  end

  @doc false
  def antimeridian_adjustment(location, %{time_zone: time_zone} = datetime, options) do
    %{time_zone_database: time_zone_database} = options
    gregorian_seconds = datetime_to_gregorian_seconds(datetime)

    local_hours_offset =
      local_mean_time_offset(location, gregorian_seconds, time_zone) / @seconds_per_hour

    date_adjustment =
      cond do
        local_hours_offset >= 20 -> 1
        local_hours_offset <= -20 -> -1
        true -> 0
      end

    {:ok, DateTime.add(datetime, date_adjustment * @seconds_per_day, :second, time_zone_database)}
  end

  # Local Mean Time offset for the expected time zone (in ms).
  #
  # The offset is the difference between Local Mean Time at the given
  # longitude and Standard Time in effect for the given time zone.
  def local_mean_time_offset(%Geo.PointZ{} = location, gregorian_seconds, time_zone) do
    %Geo.PointZ{coordinates: {lng, _, _}} = location

    lng * @minutes_per_degree * @seconds_per_minute -
      offset_for_zone(gregorian_seconds, time_zone)
  end

  def offset_for_zone(gregorian_seconds, time_zone) when is_integer(gregorian_seconds) do
    [period | _] = Tzdata.periods_for_time(time_zone, gregorian_seconds, :wall)
    period.utc_off + period.std_off
  end

  @doc false
  def datetime_in_requested_zone(utc_event_time, location, options) do
    %{time_zone_database: time_zone_database} = options

    case Map.fetch!(options, :time_zone) do
      :utc ->
        {:ok, utc_event_time}

      :default ->
        with {:ok, time_zone} <- timezone_at(location) do
          DateTime.shift_zone(utc_event_time, time_zone, time_zone_database)
        end

      time_zone when is_binary(time_zone) ->
        DateTime.shift_zone(utc_event_time, time_zone, time_zone_database)
    end
  end

  @doc false
  def timezone_at(%Geo.PointZ{} = location) do
    location = %Geo.Point{coordinates: Tuple.delete_at(location.coordinates, 2)}
    timezone_at(location)
  end

  def timezone_at(%Geo.Point{} = location) do
    TzWorld.timezone_at(location)
  end
end
