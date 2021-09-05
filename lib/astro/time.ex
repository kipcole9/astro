defmodule Astro.Time do
  @moduledoc """
  Calculations converting between geometry and time

  All public functions use degrees as their input
  parameters

  Time is a fraction of a day after UTC

  """

  alias Astro.{Math, Guards}
  import Astro.Math, only: [poly: 2, deg: 1, mod: 2]

  @type hours() :: number()

  @typedoc """
  A time is a floating point number of
  days since 0000-01-01 including the fractional
  part of a day.
  """
  @type time() :: number()

  @typedoc """
  The current Julian epoch is defined to have been
  noon on January 1, 2000. This epoch is
  denoted J2000 and has the exact Julian day
  number 2,451,545.0.

  Since there are 365.25 days in a Julian year,
  a Julian century has 36,525 days.
  """
  @type julian_centuries() :: number()

  @typedoc """
  A moment is a floating point representations of
  the fraction of a day.
  """
  @type moment() :: number()
  @type season() :: Astro.angle()
  @type zone_name() :: String.t

  @julian_day_jan_1_2000 2_451_545
  @julian_days_per_century 36_525.0
  @utc_zone "Etc/UTC"

  @minutes_per_degree 4
  @seconds_per_minute 60
  @seconds_per_hour @seconds_per_minute * 60
  @seconds_per_day @seconds_per_hour * 24
  @minutes_per_day 1440.0
  @minutes_per_hour 60.0
  @hours_per_day 24.0

  # Mean synodic month in days
  @mean_synodic_month 29.530588861

  # Mean tropical year in days
  @mean_tropical_year 365.242189

  def hr(x), do: x / hours_per_day()
  # def mn(x), do: x / hours_per_day() / minutes_per_hour()
  # def sec(x), do: x / hours_per_day() / minutes_per_hour() / seconds_per_minute()
  # def secs(x), do: x / seconds_per_hour()
  # def mins(x), do: x / minutes_per_hour()

  @doc false
  def seconds_per_day, do: @seconds_per_day
  def minutes_per_day, do: @minutes_per_day
  def hours_per_day, do: @hours_per_day
  def seconds_per_hour, do: @seconds_per_hour
  def seconds_per_minute, do: @seconds_per_minute

  def minutes_per_hour, do: @minutes_per_hour
  def days_from_minutes(minutes), do: minutes / @minutes_per_day

  def mean_synodic_month, do: @mean_synodic_month
  def mean_tropical_year, do: @mean_tropical_year

  @doc """
  Returns the dynamical time for a given
  universal time.

  Dynamical time is the time-scale that is used in
  calculating orbital motions within the Solar
  System. The underlying physical law governing
  such motions is the law of gravitation.


  """
  @spec dynamical_from_universal(time()) :: time()
  def dynamical_from_universal(t) do
    t + ephemeris_correction(t)
  end

  @doc """
  Returns the universal (UTC) time
  for a given dynamical time.

  Coordinated Universal Time or UTC is
  the primary time standard by which the
  world regulates clocks and time.

  It is within about 1 second of mean solar
  time at 0° longitude and is not adjusted
  for daylight saving time.

  It is effectively a successor to Greenwich
  Mean Time (GMT).

  """
  @spec universal_from_dynamical(time()) :: time()
  def universal_from_dynamical(t) do
    t - ephemeris_correction(t)
  end

  @doc """
  Returns the local time from the
  universal time at a given location.

  Locale time is UTC time plus the number
  of hours offset calculated from the longitude
  of a location.

  This is different to standard time which
  is UTC time adjusted for a specific time
  zone name.

  """
  @spec local_from_universal(time(), Geo.PointZ.t()) :: time()
  def local_from_universal(t, %Geo.PointZ{coordinates: {longitude, _latitude, _altitude}}) do
    t + offset_from_longitude(longitude)
  end

  @doc """
  Returns the universal time (UTC) from
  the local time at a given location.

  Locale time is UTC time plus the number
  of hours offset calculated from the longitude
  of a location.

  This is different to standard time which
  is UTC time adjusted for a specific time
  zone name.

  """
  @spec universal_from_local(time(), Geo.PointZ.t()) :: time()
  def universal_from_local(t, %Geo.PointZ{coordinates: {longitude, _latitude, _altitude}}) do
    t - offset_from_longitude(longitude)
  end

  @doc """
  Returns the standard time for a
  universal time in a given
  time zone.

  """
  @spec standard_from_universal(time(), zone_name()) :: time()
  def standard_from_universal(t, zone_name) when is_binary(zone_name) do
    t + offset_for_zone(t, zone_name)
  end

  def standard_from_universal(t, offset) when is_number(offset) do
    t + offset
  end

  @doc """
  Returns the universal (UTC) time for
  a standard time in a given time
  zone.

  """
  @spec universal_from_standard(time(), zone_name()) :: time()
  def universal_from_standard(t, zone_name) when is_binary(zone_name) do
    t - offset_for_zone(t, zone_name)
  end

  def universal_from_standard(t, offset) when is_number(offset) do
    t - offset
  end

  # @doc """
  # Returns the standard time from
  # a local time at a given location.
  #
  # """
  # @spec standard_from_local(time(), zone_name()) :: time()
  # def standard_from_local(t, zone_name) do
  #   t
  #   |> universal_from_local(zone_name)
  #   |> standard_from_universal(zone_name)
  # end
  #
  # @doc """
  # Returns the local time from
  # a standard time at a given location.
  #
  # """
  # @spec local_from_standard(time(), zone_name()) :: time()
  # def local_from_standard(t, zone_name) do
  #   t
  #   |> universal_from_standard(zone_name)
  #   |> local_from_universal(zone_name)
  # end

  def sidereal_from_moment(t) do
    c = (t - j2000()) / @julian_days_per_century

    terms =
      Enum.map([280.46061837, 36525 * 360.98564736629, 0.000387933, -1 / 38710000.0], &Math.deg/1)

    mod(Math.poly(c, terms), 360)
  end

  @doc """
  Returns the zone difference in hours between
  a given location and UTC.

  """
  @spec offset_from_longitude(Geo.PointZ.t() | Astro.longitude()) :: moment()
  def offset_from_longitude(%Geo.PointZ{coordinates: {longitude, _latitude, _altitude}}) do
    offset_from_longitude(longitude)
  end

  def offset_from_longitude(longitude) when is_number(longitude) do
    longitude / deg(360.0)
  end

  @doc """
  Returns the astronomical Julian day for a given
  date

  ## Arguments

  * `date` is any `Calendar.date`

  ## Returns

  * the astronomical Julian day as a `float`

  ## Example

    iex> Astro.Time.julian_day_from_date ~D[2019-12-05]
    2458822.5

  """
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

  defdelegate ajd(date), to: __MODULE__, as: :julian_day_from_date

  @doc """
  Returns the Julian centuries for a given
  Julian day

  ## Arguments

  * `julian_day` is any astronomical Julian day such
    as returned from `Astro.Time.julian_day_from_date/1`

  ## Returns

  * the astronomical Julian century as a `float`

  """
  def julian_centuries_from_julian_day(julian_day) do
    (julian_day - @julian_day_jan_1_2000) / @julian_days_per_century
  end

  def julian_centuries_from_moment(t) do
    (dynamical_from_universal(t) - j2000()) / @julian_days_per_century
  end

  @doc """
  Returns the day number for
  January 1st, 2000

  """
  @new_year_2000 Date.new!(2000, 1, 1)
  @j2000 Date.to_gregorian_days(@new_year_2000) + 0.5

  def j2000 do
    @j2000
  end

  @doc """
  Returns the Julian day for a given
  Julian century

  ## Arguments

  * `julian_century` is any astronomical Julian century such
    as returned from `Astro.Time.julian_centuries_from_julian_day/1`

  ## Returns

  * the astronomical Julian day as a `float`

  """
  def julian_day_from_julian_centuries(julian_centuries) do
    julian_centuries * @julian_days_per_century + @julian_day_jan_1_2000
  end

  @doc """
  Returns the datetime for a given Julian day

  ## Arguments

  * `julian_day` is any astronomical Julian day such
    as returned from `Astro.Time.julian_day_from_date/1`

  ## Returns

  * a `DateTime.t` in the UTC time zone

  ## Example

      iex> Astro.Time.datetime_from_julian_days 2458822.5
      {:ok, ~U[2019-12-05 00:00:00Z]}

  """
  def datetime_from_julian_days(julian_days) when is_float(julian_days) do
    z = trunc(julian_days + 0.5)
    f = julian_days + 0.5 - z

    a =
      if z < 2_299_161 do
        z
      else
        alpha = trunc((z - 1_867_216.25) / 36_524.25)
        z + 1 + alpha - trunc(alpha / 4.0)
      end

    b = a + 1_524
    c = trunc((b - 122.1) / 365.25)
    d = trunc(365.25 * c)
    e = trunc((b - d) / 30.6001)
    dt = b - d - trunc(30.6001 * e) + f
    month = e - if(e < 13.5, do: 1, else: 13)
    year = c - if(month > 2.5, do: 4716, else: 4715)
    day = trunc(dt)
    h = 24 * (dt - day)
    hours = trunc(h)
    m = 60 * (h - hours)
    minutes = trunc(m)
    seconds = trunc(60 * (m - minutes))

    {:ok, naive_datetime} = NaiveDateTime.new(year, month, day, hours, minutes, seconds, {0, 0})
    DateTime.from_naive(naive_datetime, @utc_zone)
  end

  @doc """
  Converts a terrestrial datetime to a UTC datetime

  ## Arguments

  * `datetime` is any UTC datetime which is considered
    to be a Terrestrial Time.

  ## Returns

  * A UTC datetime adjusted for the difference
    between Terrestrial Time and UTC time

  ## Notes

  Terrestrial Time (TT) was introduced by the IAU in 1979 as
  the coordinate time scale for an observer on the
  surface of Earth. It takes into account relativistic
  effects and is based on International Atomic Time (TAI),
  which is a high-precision standard using several hundred
  atomic clocks worldwide. As such, TD is the atomic time
  equivalent to its predecessor Ephemeris Time (ET) and is
  used in the theories of motion for bodies in the solar
  system.

  To ensure continuity with ET, TD was defined to match
  ET for the date 1977 Jan 01. In 1991, the IAU refined
  the definition of TT to make it more precise. It was
  also renamed Terrestrial Time (TT) from the earlier
  Terrestrial Dynamical Time (TDT).

  """
  def utc_datetime_from_terrestrial_datetime(%{year: year} = datetime) do
    t = (year - 2000) / 100.0
    delta_seconds = trunc(delta_seconds_for_year(year, t))
    {:ok, DateTime.add(datetime, -delta_seconds, :second)}
  end

  @correction_first_year 1620
  @correction_last_year 2002
  @correction_lookup @correction_first_year..@correction_last_year

  defp delta_seconds_for_year(year, _t) when year in @correction_lookup and rem(year, 2) == 0 do
    elem(delta_seconds_1620_2002(), div(year - @correction_first_year, 2))
  end

  defp delta_seconds_for_year(year, t) when year in @correction_lookup do
    (delta_seconds_for_year(year - 1, t) + delta_seconds_for_year(year + 1, t)) / 2
  end

  defp delta_seconds_for_year(year, t) when year < 948 do
    2177 + 497 * t + 44.1 * :math.pow(t, 2)
  end

  defp delta_seconds_for_year(year, t) when year in 2000..2100 do
    delta_t = 102 + 102 * t + 25.3 * :math.pow(t, 2)
    delta_t + 0.37 * (year - 2100)
  end

  defp delta_seconds_for_year(year, t) when year >= 948 do
    102 + 102 * t + 25.3 * :math.pow(t, 2)
  end

  defp delta_seconds_1620_2002 do
    {121, 112, 103, 95, 88, 82, 77, 72, 68, 63, 60, 56, 53, 51, 48, 46, 44, 42, 40, 38, 35, 33,
     31, 29, 26, 24, 22, 20, 18, 16, 14, 12, 11, 10, 9, 8, 7, 7, 7, 7, 7, 7, 8, 8, 9, 9, 9, 9, 9,
     10, 10, 10, 10, 10, 10, 10, 10, 11, 11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 14, 14, 14,
     14, 15, 15, 15, 15, 15, 16, 16, 16, 16, 16, 16, 16, 16, 15, 15, 14, 13, 13.1, 12.5, 12.2,
     12.0, 12.0, 12.0, 12.0, 12.0, 12.0, 11.9, 11.6, 11.0, 10.2, 9.2, 8.2, 7.1, 6.2, 5.6, 5.4,
     5.3, 5.4, 5.6, 5.9, 6.2, 6.5, 6.8, 7.1, 7.3, 7.5, 7.6, 7.7, 7.3, 6.2, 5.2, 2.7, 1.4, -1.2,
     -2.8, -3.8, -4.8, -5.5, -5.3, -5.6, -5.7, -5.9, -6.0, -6.3, -6.5, -6.2, -4.7, -2.8, -0.1,
     2.6, 5.3, 7.7, 10.4, 13.3, 16.0, 18.2, 20.2, 21.1, 22.4, 23.5, 23.8, 24.3, 24.0, 23.9, 23.9,
     23.7, 24.0, 24.3, 25.3, 26.2, 27.3, 28.2, 29.1, 30.0, 30.7, 31.4, 32.2, 33.1, 34.0, 35.0,
     36.5, 38.3, 40.2, 42.2, 44.5, 46.5, 48.5, 50.5, 52.5, 53.8, 54.9, 55.8, 56.9, 58.3, 60.0,
     61.6, 63.0, 63.8, 64.3}
  end

  @doc """
  Returns the modified Julian day for a date

  ## Arguments

  * `date` is any `Calendar.date`

  ## Returns

  * the modified Julian day as a `float`

  ## Notes

  A modified version of the Julian date denoted MJD is
  obtained by subtracting 2,400,000.5 days from the
  Julian date JD,

  The MJD therefore gives the number of days since
  midnight on November 17, 1858. This date corresponds
  to `2400000.5` days after day 0 of the Julian calendar.

  """
  def mjd(date) do
    ajd(date) - 2_400_000.5
  end

  @doc """
  Converts a float number of hours since midnight to
  a `DateTime.t()`

  ## Arguments

  * `time_of_day` is a float number of hours
    since midnight

  * `date` is any `Calendar.date()`

  ## Returns

  A `DateTime.t()` combining the `date` and `time_of_day`
  in the UTC timezone.

  """
  def moment_to_datetime(time_of_day, %{year: year, month: month, day: day}) do
    with {hours, minutes, seconds} <- hours_to_hms(time_of_day),
         {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hours, minutes, seconds, 0) do
      DateTime.from_naive(naive_datetime, @utc_zone)
    end
  end

  @doc """
  Converts a float number of hours
  since midnight into `{hours, minutes, seconds}`.

  ## Arguments

  * `time_of_day` is a float number of hours
    since midnight

  ## Returns

  * A `{hour, minute, second}` tuple.

  ## Examples

    iex> Astro.Time.hours_to_hms 0.0
    {0, 0, 0}

    iex> Astro.Time.hours_to_hms 23.999
    {23, 59, 56}

    iex> Astro.Time.hours_to_hms 15.456
    {15, 27, 21}

  """
  def hours_to_hms(time_of_day) when is_float(time_of_day) do
    hours = trunc(time_of_day)
    minutes = (time_of_day - hours) * @minutes_per_hour
    seconds = (minutes - trunc(minutes)) * @seconds_per_minute

    {hours, trunc(minutes), trunc(seconds)}
  end

  @doc """
  Converts a number of hourse into
  days.

  ## Arguments

  ## Returns

  ## Examples

  """
  def hours_to_days(hours) do
    hours / @hours_per_day
  end

  @doc """
  Converts a number of seconds
  since midnight into `{hours, minutes, seconds}`.

  ## Arguments

  * `time_of_day` is a number of seconds

  ## Returns

  * A `{hour, minute, second}` tuple.

  ## Examples

    iex> Astro.Time.seconds_to_hms 0.0
    {0, 0, 0}

    iex> Astro.Time.seconds_to_hms 3214
    {0, 53, 34}

    iex> Astro.Time.seconds_to_hms 10_000
    {2, 46, 39}

  """
  def seconds_to_hms(time_of_day) when is_number(time_of_day) do
    (time_of_day / @seconds_per_minute / @minutes_per_hour)
    |> hours_to_hms
  end

  @doc """
  Adds the requested minutes to a date
  returning a datetime in the UTC time zone

  ## Arguments

  * `minutes` is a float number of minutes since midnight

  * `date` is any date in the Gregorian calendar

  ## Returns

  * a datetime in the UTC time zone

  """
  def datetime_from_date_and_minutes(minutes, date) do
    {:ok, naive_datetime} = NaiveDateTime.new(date.year, date.month, date.day, 0, 0, 0)
    {:ok, datetime} = DateTime.from_naive(naive_datetime, @utc_zone)
    {:ok, DateTime.add(datetime, trunc(minutes * @seconds_per_minute), :second)}
  end

  # @doc """
  # Returns the number of seconds since `0001-01-01`
  # in the Gregorian calendar.
  #
  # ## Arguments
  #
  # * `datetime` is any `DateTime.t` since `0001-01-01`in the `Calendar.ISO`
  #   calendar
  #
  # ## Returns
  #
  # * An integer number of seconds since `0001-01-01`
  #
  # """
  # def datetime_to_gregorian_seconds(unquote(Cldr.Calendar.datetime()) = datetime) do
  #   _ = calendar
  #
  #   %{year: year, month: month, day: day, hour: hour, minute: minute, second: second} = datetime
  #   :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}})
  # end

  @doc false
  def adjust_for_wraparound(unquote(Guards.datetime()) = datetime, location, %{rise_or_set: :rise}) do
    _ = calendar

    # sunrise after 6pm indicates the UTC date has occurred earlier
    if datetime.hour + local_hour_offset(datetime, location) > 18 do
      {:ok, DateTime.add(datetime, -@seconds_per_day, :second)}
    else
      {:ok, datetime}
    end
  end

  def adjust_for_wraparound(unquote(Guards.datetime()) = datetime, location, %{rise_or_set: :set}) do
    _ = calendar

    # sunset before 6am indicates the UTC date has occurred later
    if datetime.hour + local_hour_offset(datetime, location) < 6 do
      {:ok, DateTime.add(datetime, @seconds_per_day, :second)}
    else
      {:ok, datetime}
    end
  end

  defp local_hour_offset(datetime, location) do
    gregorian_seconds = to_gregorian_seconds(datetime)

    local_mean_time_offset =
      local_mean_time_offset(location, gregorian_seconds, datetime.time_zone)

    (local_mean_time_offset + datetime.std_offset) / @seconds_per_hour
  end

  @doc false
  def antimeridian_adjustment(location, %{time_zone: time_zone} = datetime, options) do
    %{time_zone_database: time_zone_database} = options
    gregorian_seconds = to_gregorian_seconds(datetime)

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

  @doc false
  def local_mean_time_offset(%Geo.PointZ{} = location, gregorian_seconds, time_zone) do
    %Geo.PointZ{coordinates: {longitude, _, _}} = location
    local_mean_time = longitude * @minutes_per_degree * @seconds_per_minute
    local_mean_time - offset_for_zone(gregorian_seconds, time_zone) * seconds_per_day()
  end

  def offset_from_location(%Geo.PointZ{} = location, t) do
    {:ok, time_zone} = timezone_at(location)
    offset_for_zone(t, time_zone)
  end

  @doc """
  Returns the offset in float days
  for a given `moment` and time zone.

  ## Example

      # Returns a 1 hour offset as a fraction of day
      iex> t = Date.to_gregorian_days(~D[2021-08-01])
      iex> Astro.Time.offset_for_zone t, "Europe/London"
      0.041666666666666664

  """
  def offset_for_zone(t, time_zone) do
    gregorian_seconds = t * seconds_per_day()

    case Tzdata.periods_for_time(time_zone, gregorian_seconds, :wall) do
      [period] ->
        ((period.utc_off + period.std_off) / seconds_per_day())

      [_period_a | _period_b] ->
        :ambiguous_time

      [] ->
        :no_such_time_or_zone
    end
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
    TzWorld.timezone_at(location)
  end

  @jan_1_1900  Date.new!(1900, 1, 1)

  def ephemeris_correction(t) do
    %{year: year} = Date.from_gregorian_days(floor(t))
    c = Date.diff(Date.new!(year, 7, 1), @jan_1_1900) / @julian_days_per_century

    cond do
      year in 1988..2019 ->
        (year - 1933) / @seconds_per_day

      year in [1900, 1987] ->
        poly(c, [
          -0.00002, 0.000297, 0.025184,
          -0.181133, 0.553040, -0.861938,
          0.677066, -0.212591
        ])

      year in 1800..1899 ->
        poly(c, [
          -0.000009, 0.003844, 0.083563,
          0.865736, 4.867575, 15.845535,
          31.332267, 38.291999, 28.316289,
          11.636204, 2.043794
        ])

      year in [1700, 1799] ->
        poly(year - 1700, [8.118780842, -0.005092142, 0.003336121, -0.0000266484]) /
          @seconds_per_day

      year in 1600..1699 ->
         poly(year - 1600, [196.58333, -4.0675, 0.0219167]) /
           @seconds_per_day

       true ->
         x = hr(12) + Date.diff(Date.new!(year, 1, 1), Date.new!(1810, 1, 1))
         ((x * x) / 41_048_480.0 - 15) / @seconds_per_day
    end
  end

  @doc false
  @spec date_time_from_moment(moment()) :: Calendar.datetime()

  def date_time_from_moment(t) do
    days = trunc(t)
    hours = (t - days) * @hours_per_day

    date = Elixir.Date.from_gregorian_days(days)
    moment_to_datetime(hours, date)
  end

  @doc false
  @spec date_time_to_moment(Calendar.datetime()) :: moment()

  def date_time_to_moment(unquote(Guards.datetime()) = date_time) do
    %{year: year, month: month, day: day, hour: hour} = date_time
    %{minute: minute, second: second, microsecond: microsecond} = date_time

    {days, {numerator, denominator}} =
      calendar.naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond)

    days + numerator / denominator
  end

  defp to_gregorian_seconds(datetime) do
    {numerator, denominator} = DateTime.to_gregorian_seconds(datetime)

    if denominator == 0 do
      numerator
    else
      numerator / denominator
    end
  end
end
