defmodule Astro.Time do
  @moduledoc """
  Time scales, conversions, and calendar utilities for astronomical calculations.

  ## Moments

  A **moment** is the primary internal time representation used throughout
  `Astro`. It is a floating-point number of days since the Gregorian epoch
  (0000-01-01 00:00:00 UTC). The integer part identifies the calendar day;
  the fractional part represents the elapsed fraction of that day since
  midnight.

  The public API in `Astro` accepts `Date` and `DateTime` parameters and
  converts them to moments before delegating to the implementation modules
  (`Astro.Solar`, `Astro.Lunar`, `Astro.Solar.SunRiseSet`,
  `Astro.Lunar.MoonRiseSet`). Those modules work exclusively with moments
  and should never convert back to `Date` or `DateTime` internally.

  Use `date_time_to_moment/1` to convert a `Date` or `DateTime` to a
  moment, and `date_time_from_moment/1` to convert a moment back to a
  UTC `DateTime`.

  ## Time scales

  Six time scales appear in astronomical calculations. Each serves a
  different purpose.

  ### Universal Time (UTC)

  The civil clock time standard. UTC is kept within one second of mean
  solar time at 0° longitude by the occasional insertion of leap seconds.
  It is the base time scale for moments: a moment is always in UTC.

  Functions: `universal_from_local/2`, `universal_from_standard/2`,
  `universal_from_dynamical/1`.

  ### Standard Time

  UTC adjusted for a named time zone (e.g. `"America/New_York"`),
  including any daylight-saving offset. Standard time has discrete zone
  boundaries and changes at politically determined transition points.

  Functions: `standard_from_universal/2`, `universal_from_standard/2`.

  ### Local (Mean Solar) Time

  UTC adjusted purely by geographic longitude — what a sundial reads.
  The offset is `longitude / 360` of a day, a smooth function of
  position with no zone boundaries or daylight-saving rules.

  Functions: `local_from_universal/2`, `universal_from_local/2`.

  ### Dynamical Time

  The uniform time scale used for computing planetary and lunar orbits.
  In this library, "dynamical time" refers to TDB (Barycentric Dynamical
  Time) — the time argument expected by JPL ephemerides.

  Two representations coexist:

    * **Moment-domain** — `dynamical_from_universal/1` adds ΔT (as a
      fraction of a day) to a UTC moment, producing a dynamical moment
      used by the Meeus-era polynomial series via
      `julian_centuries_from_moment/1`.

    * **Seconds-past-J2000.0** — `dynamical_time_from_moment/1` converts
      a UTC moment to TDB seconds past J2000.0, the scale used directly
      by the SPK kernel. `dynamical_time_to_moment/1` inverts it.

  Both representations derive ΔT from the unified `delta_t/1` function.

  ### Terrestrial Time (TT)

  A uniform atomic time scale defined on Earth's geoid, the modern
  successor to Ephemeris Time (ET). TT is related to International
  Atomic Time (TAI) by a fixed offset: TT = TAI + 32.184 s. For
  solar-system calculations at Earth's distance, TT ≈ TDB to within
  ~1.7 ms, and this library treats them as identical. The conversion
  function `utc_datetime_from_dynamical_datetime/1` delegates to
  `universal_from_dynamical/1` internally.

  ### Sidereal Time

  Measures Earth's rotation relative to the stars rather than the Sun.
  A sidereal day is ~3 minutes 56 seconds shorter than a solar day.
  Greenwich Mean Sidereal Time (GMST) is used to convert between
  equatorial coordinates and the local horizon; Greenwich Apparent
  Sidereal Time (GAST) adds the equation of the equinoxes (nutation
  in right ascension).

  Functions: `greenwich_mean_sidereal_time/1`,
  `local_sidereal_time/2`, `mean_sidereal_from_moment/1`,
  `apparent_sidereal_from_moment/1`. See also `Astro.Coordinates.gast/1`.

  ## Time scale conversion table

  The table below shows how to convert from one time scale (row) to
  another (column). Each cell describes the conversion algorithm.
  A dash (—) marks the identity diagonal.

  | From \\ To      | UTC              | Standard            | Local               | Dynamical           | Terrestrial         | Sidereal              |
  |:----------------|:-----------------|:--------------------|:--------------------|:--------------------|:--------------------|:----------------------|
  | **UTC**         | —                | + zone offset       | + longitude/360     | + ΔT                | + ΔT (≈ dynamical)  | GMST polynomial in UTC |
  | **Standard**    | − zone offset    | —                   | − zone + long/360   | − zone + ΔT         | − zone + ΔT         | via UTC then GMST     |
  | **Local**       | − longitude/360  | − long/360 + zone   | —                   | − long/360 + ΔT     | − long/360 + ΔT     | via UTC then GMST     |
  | **Dynamical**   | − ΔT             | − ΔT + zone         | − ΔT + long/360     | —                   | identity (≈)        | via UTC then GMST     |
  | **Terrestrial** | − ΔT (≈ dyn)     | − ΔT + zone         | − ΔT + long/360     | identity (≈)        | —                   | via UTC then GMST     |
  | **Sidereal**    | not invertible†  | not invertible†     | not invertible†     | not invertible†     | not invertible†     | —                     |

  **Notes:**

  * **zone offset** = UTC offset + DST offset for the named time zone,
    looked up via the configured `TimeZoneDatabase`.
  * **longitude/360** = fraction of a day corresponding to the observer's
    geographic longitude (west negative).
  * **ΔT** = TT − UTC in seconds, converted to fractional days by
    dividing by 86400. Computed by `delta_t/1`.
  * **Terrestrial ≈ Dynamical**: TT and TDB differ by at most ~1.7 ms;
    this library treats them as identical.
  * **† Sidereal → other**: sidereal time is not uniquely invertible
    because multiple UTC instants map to the same sidereal angle within
    a sidereal day. In practice, sidereal time is computed *from* UTC
    for a known date, not converted back.

  ## ΔT

  ΔT (TT − UTC) is the difference between the uniform dynamical time
  scale and civil clock time. It varies as Earth's rotation rate changes
  due to tidal friction and other geophysical effects. The unified
  `delta_t/1` function returns ΔT in seconds for a given decimal year,
  drawing on IERS observations (1972–2025), the Meeus biennial table
  (1620–1971), and polynomial approximations for earlier and later dates.

  ## Julian day system

  The Julian day system provides a continuous day count independent of
  any calendar. It is the standard time-keeping framework in positional
  astronomy.

  ### Julian Day (JD)

  A continuous count of days (and fractions) from an epoch set at
  Greenwich noon on 1 January 4713 BC (Julian proleptic calendar).
  Day boundaries fall at noon, not midnight — JD 2451545.0 corresponds
  to 2000-01-01 12:00:00 TT.

  Functions: `julian_day_from_date/1`, `datetime_from_julian_days/1`,
  `date_from_julian_days/1`.

  ### J2000.0

  The standard astronomical epoch: 2000 January 1.5 TT (Julian Day
  2451545.0). Precession angles, nutation series, and ephemeris
  polynomials are all referenced to this epoch. Dynamical time in
  this library is expressed as seconds past J2000.0.

  Constant: `j2000/0` (returns the moment for J2000.0).

  ### Modified Julian Day (MJD)

  JD − 2400000.5. This shifts the day boundary from noon to midnight
  and produces smaller numbers, convenient for modern dates. MJD 0
  corresponds to 1858-11-17 00:00:00 UTC.

  Function: `mjd/1`.

  ### Julian Centuries

  A Julian century is exactly 36525 days (100 Julian years of 365.25
  days each). Precession and nutation polynomials are evaluated in
  Julian centuries from J2000.0. Two conversion paths exist:

    * `julian_centuries_from_julian_day/1` — converts a Julian day
      directly.
    * `julian_centuries_from_moment/1` — converts a UTC moment by
      first applying ΔT to obtain a dynamical moment.
    * `julian_centuries_from_dynamical_time/1` — converts dynamical
      time (seconds past J2000.0) to Julian centuries.

  """

  alias Astro.{Math, Guards, Location}
  import Astro.Math, only: [deg: 1, mod: 2]

  @typedoc """
  A time is a floating point number of
  days since 0000-01-01 including the fractional
  part of a day.
  """
  @type time() :: number()

  @typedoc "A number of days as a float"
  @type days() :: number()

  @typedoc "A number of hours as a float"
  @type hours() :: number()

  @typedoc "A number of minutes as a float"
  @type minutes() :: number()

  @typedoc "A number of seconds as a float"
  @type seconds() :: number()

  @typedoc "A time of day as a float fraction of a day"
  @type fraction_of_day() :: number()

  @typedoc "A tuple of integer hours, integer minutes and integer seconds"
  @type hms() :: {Calendar.hour(), Calendar.minute(), Calendar.second()}

  @typedoc """
  A float number of days since the Julian epoch.

  The current Julian epoch is defined to have been
  noon on January 1, 2000. This epoch is
  denoted J2000 and has the exact Julian day
  number `2,451,545.0`.

  """
  @type julian_days() :: number()

  @typedoc """
  The float number of Julian centuries.

  Since there are 365.25 days in a Julian year,
  a Julian century has 36,525 days.
  """
  @type julian_centuries() :: number()

  @typedoc """
  A moment is a floating point representation of
  the fraction of a day.
  """
  @type moment() :: number()

  @typedoc """
  Season expressed as a non-negative number
  that is <= 360 representing the sun angle of incidence
  (the angle at which the sun hits the earth).
  """
  @type season() :: Astro.angle()

  @typedoc "A time zone name as a string"
  @type zone_name() :: binary()

  @julian_day_jan_1_2000 2_451_545
  @julian_days_per_century 36_525.0
  @julian_epoch_days 1_721_425.5
  @utc_zone "Etc/UTC"

  @minutes_per_degree 4
  @seconds_per_minute 60
  @seconds_per_hour @seconds_per_minute * 60
  @seconds_per_day @seconds_per_hour * 24
  @minutes_per_day 1440.0
  @minutes_per_hour 60.0
  @hours_per_day 24.0

  # Mean synodic month in days. Meeus Ch. 49
  @mean_synodic_month 29.530588861

  # Mean tropical year in days
  @mean_tropical_year 365.242189

  @doc false
  def hr(x), do: x / hours_per_day()
  # def mn(x), do: x / hours_per_day() / minutes_per_hour()
  # def sec(x), do: x / hours_per_day() / minutes_per_hour() / seconds_per_minute()
  # def secs(x), do: x / seconds_per_hour()
  # def mins(x), do: x / minutes_per_hour()

  @doc false
  def seconds_per_day, do: @seconds_per_day

  @doc false
  def minutes_per_day, do: @minutes_per_day

  @doc false
  def hours_per_day, do: @hours_per_day

  @doc false
  def seconds_per_hour, do: @seconds_per_hour

  @doc false
  def seconds_per_minute, do: @seconds_per_minute

  @doc false
  def minutes_per_hour, do: @minutes_per_hour

  @doc false
  def julian_epoch_days, do: @julian_epoch_days

  @doc false
  def julian_day_jan_1_2000, do: @julian_day_jan_1_2000

  @doc false
  def julian_days_per_century, do: @julian_days_per_century

  @doc false
  def days_from_minutes(minutes), do: minutes / @minutes_per_day

  @doc false
  def mean_synodic_month, do: @mean_synodic_month

  @doc false
  def mean_tropical_year, do: @mean_tropical_year

  @doc """
  Returns the dynamical moment for a given universal (UTC) moment.

  Adds ΔT (converted to a fraction of a day) to the UTC moment,
  producing a dynamical moment suitable for evaluating Meeus-era
  polynomial series via `julian_centuries_from_moment/1`.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in UTC.

  ### Returns

  * A moment in the dynamical time scale (float Gregorian days).

  ### Examples

      iex> t = Astro.Time.date_time_to_moment(~U[2000-01-01 12:00:00Z])
      iex> dt = Astro.Time.dynamical_from_universal(t)
      iex> Float.round(dt - t, 6)
      0.000739

  """
  @spec dynamical_from_universal(time()) :: time()
  def dynamical_from_universal(t) do
    %{year: year} = Date.from_gregorian_days(floor(t))
    frac = (Date.new!(year, 7, 1) |> Date.to_gregorian_days()) - floor(t)
    decimal_year = year + (0.5 - frac / 365.25)
    t + delta_t(decimal_year) / @seconds_per_day
  end

  @doc """
  Returns the universal (UTC) moment for a given dynamical moment.

  Subtracts ΔT (converted to a fraction of a day) from a dynamical
  moment, recovering the corresponding UTC moment.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in
    dynamical time.

  ### Returns

  * A moment in the UTC time scale (float Gregorian days).

  ### Examples

      iex> t = Astro.Time.date_time_to_moment(~U[2000-01-01 12:00:00Z])
      iex> dyn = Astro.Time.dynamical_from_universal(t)
      iex> Astro.Time.universal_from_dynamical(dyn) == t
      true

  """
  @spec universal_from_dynamical(time()) :: time()
  def universal_from_dynamical(t) do
    %{year: year} = Date.from_gregorian_days(floor(t))
    frac = (Date.new!(year, 7, 1) |> Date.to_gregorian_days()) - floor(t)
    decimal_year = year + (0.5 - frac / 365.25)
    t - delta_t(decimal_year) / @seconds_per_day
  end

  @doc """
  Returns the local mean solar time for a given universal (UTC) moment
  and location.

  Local mean solar time is UTC plus an offset derived purely from
  geographic longitude (`longitude / 360` of a day). This is distinct
  from standard time, which uses named time zone boundaries and
  daylight-saving rules.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in UTC.
  * `location` is a `Geo.PointZ` with `{longitude, latitude, altitude}`.

  ### Returns

  * A moment in local mean solar time (float Gregorian days).

  ### Examples

      iex> location = %Geo.PointZ{coordinates: {-90.0, 40.0, 0.0}}
      iex> t = 740047.5
      iex> Astro.Time.local_from_universal(t, location)
      740047.25

  """
  @spec local_from_universal(time(), Geo.PointZ.t()) :: time()
  def local_from_universal(t, %Geo.PointZ{coordinates: {longitude, _latitude, _altitude}}) do
    t + offset_from_longitude(longitude)
  end

  @doc """
  Returns the universal (UTC) moment for a given local mean solar
  time moment and location.

  Subtracts the longitude-based offset (`longitude / 360` of a day)
  from the local time to recover UTC. This is the inverse of
  `local_from_universal/2`.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in
    local mean solar time.
  * `location` is a `Geo.PointZ` with `{longitude, latitude, altitude}`.

  ### Returns

  * A moment in UTC (float Gregorian days).

  ### Examples

      iex> location = %Geo.PointZ{coordinates: {-90.0, 40.0, 0.0}}
      iex> local_t = 740047.25
      iex> Astro.Time.universal_from_local(local_t, location)
      740047.5

  """
  @spec universal_from_local(time(), Geo.PointZ.t()) :: time()
  def universal_from_local(t, %Geo.PointZ{coordinates: {longitude, _latitude, _altitude}}) do
    t - offset_from_longitude(longitude)
  end

  @doc """
  Returns the standard time moment for a given universal (UTC) moment
  and time zone.

  Standard time is UTC adjusted by the named time zone's UTC offset
  and any daylight-saving offset in effect at the given instant.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in UTC.
  * `zone_name` is either a time zone name string
    (e.g. `"America/New_York"`) or a numeric offset in fractional days.

  ### Returns

  * A moment in standard time (float Gregorian days).

  ### Examples

      iex> t = Astro.Time.date_time_to_moment(~U[2024-01-15 12:00:00Z])
      iex> standard = Astro.Time.standard_from_universal(t, 0.25)
      iex> standard - t
      0.25

  """
  @spec standard_from_universal(time(), zone_name() | number()) :: time()
  def standard_from_universal(t, zone_name) when is_binary(zone_name) do
    t + offset_for_zone(t, zone_name)
  end

  def standard_from_universal(t, offset) when is_number(offset) do
    t + offset
  end

  @doc """
  Returns the universal (UTC) moment for a given standard time moment
  and time zone.

  Subtracts the time zone offset (UTC offset + DST) from the standard
  time moment to recover UTC. This is the inverse of
  `standard_from_universal/2`.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in
    standard time.
  * `zone_name` is either a time zone name string
    (e.g. `"America/New_York"`) or a numeric offset in fractional days.

  ### Returns

  * A moment in UTC (float Gregorian days).

  ### Examples

      iex> t = 740047.75
      iex> utc = Astro.Time.universal_from_standard(t, 0.25)
      iex> t - utc
      0.25

  """
  @spec universal_from_standard(time(), zone_name() | number()) :: time()
  def universal_from_standard(t, zone_name) when is_binary(zone_name) do
    t - offset_for_zone(t, zone_name)
  end

  def universal_from_standard(t, offset) when is_number(offset) do
    t - offset
  end

  @doc false
  def mean_sidereal_from_moment(t) do
    # c = (t - j2000()) / @julian_days_per_century
    c = julian_centuries_from_moment(t)

    terms =
      Enum.map(
        [280.46061837, 36525 * 360.98564736629, 0.000387933, -1 / 38_710_000.0],
        &Math.deg/1
      )

    mod(Math.poly(c, terms), 360)
  end

  def apparent_sidereal_from_moment(t) do
    # c = (t - j2000()) / @julian_days_per_century
    c = julian_centuries_from_moment(t)

    terms =
      Enum.map([100.4606184, 36_000.77004, 0.000387933, -1 / 38_710_000.0], &Math.deg/1)

    mod(Math.poly(c, terms), 360)
  end

  @doc """
  Returns the Greenwich Mean Sidereal Time (GMST) in degrees for a
  given datetime.

  GMST measures Earth's rotation relative to the stars. It is the
  hour angle of the mean vernal equinox at the Greenwich meridian.

  ### Arguments

  * `date_time` is any `t:Calendar.datetime/0`. If not already in UTC,
    it is converted to UTC before computation.

  ### Returns

  * GMST in degrees (float, typically 0–360).

  ### Examples

      iex> gmst = Astro.Time.greenwich_mean_sidereal_time(~U[2000-01-01 12:00:00Z])
      iex> Float.round(gmst, 4)
      280.7273

  """
  @doc since: "0.11.0"
  @spec greenwich_mean_sidereal_time(Calendar.datetime()) :: moment()

  def greenwich_mean_sidereal_time(date_time) do
    date_time_utc =
      date_time
      |> DateTime.convert!(Calendar.ISO)
      |> DateTime.shift_zone!("UTC")

    date_time_utc
    |> date_time_to_moment()
    |> mean_sidereal_from_moment()
  end

  @doc """
  Returns the local sidereal time in degrees for a given location
  and datetime.

  Local sidereal time is GMST plus the observer's geographic
  longitude.

  ### Arguments

  * `location` is any `t:Astro.location/0` (a `Geo.Point`,
    `Geo.PointZ`, or `{longitude, latitude}` tuple).
  * `date_time` is any `t:Calendar.datetime/0`.

  ### Returns

  * Local sidereal time in degrees (float).

  ### Examples

      iex> lst = Astro.Time.local_sidereal_time({0.0, 51.5}, ~U[2000-01-01 12:00:00Z])
      iex> Float.round(lst, 4)
      280.7273

  """
  @doc since: "0.11.0"
  @spec local_sidereal_time(Astro.location(), Calendar.datetime()) :: moment()

  def local_sidereal_time(location, date_time) do
    %Geo.PointZ{coordinates: {longitude, _latitude, _altitude}} =
      Location.normalize_location(location)

    date_time
    |> greenwich_mean_sidereal_time()
    |> Kernel.+(longitude)
  end

  @doc """
  Returns the local mean solar time offset from UTC as a fraction
  of a day for a given longitude.

  The offset is `longitude / 360` of a day. West longitudes
  (negative) produce negative offsets, east longitudes produce
  positive offsets.

  ### Arguments

  * `longitude` is either a `Geo.PointZ` struct or a numeric
    longitude in degrees (west negative, east positive).

  ### Returns

  * The offset as a fraction of a day (float). For example, −90°
    returns −0.25 (6 hours behind UTC).

  ### Examples

      iex> Astro.Time.offset_from_longitude(-90.0)
      -0.25

      iex> Astro.Time.offset_from_longitude(180.0)
      0.5

  """
  @spec offset_from_longitude(Geo.PointZ.t() | Astro.longitude()) :: moment()
  def offset_from_longitude(%Geo.PointZ{coordinates: {longitude, _latitude, _altitude}}) do
    offset_from_longitude(longitude)
  end

  def offset_from_longitude(longitude) when is_number(longitude) do
    longitude / deg(360.0)
  end

  @doc """
  Returns the astronomical Julian day number for a given date.

  ### Arguments

  * `date` is any `t:Calendar.date/0`.

  ### Returns

  * The Julian day as a `float`. The `.5` fractional part
    reflects the Julian day convention of starting at noon.

  ### Examples

      iex> Astro.Time.julian_day_from_date(~D[2019-12-05])
      2458822.5

      iex> Astro.Time.julian_day_from_date(~D[2000-01-01])
      2451544.5

  """
  @spec julian_day_from_date(Calendar.date()) :: julian_days()
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
  Returns Julian centuries from J2000.0 for a given Julian day.

  ### Arguments

  * `julian_day` is a Julian day number (float) such as returned
    from `julian_day_from_date/1`.

  ### Returns

  * Julian centuries from J2000.0 as a `float`.

  ### Examples

      iex> Astro.Time.julian_centuries_from_julian_day(2451545.0)
      0.0

      iex> Float.round(Astro.Time.julian_centuries_from_julian_day(2451545.0 + 36525.0), 1)
      1.0

  """
  def julian_centuries_from_julian_day(julian_day) do
    (julian_day - @julian_day_jan_1_2000) / @julian_days_per_century
  end

  @doc """
  Returns Julian centuries from J2000.0 for a given UTC moment.

  First converts the UTC moment to a dynamical moment (by adding ΔT),
  then computes Julian centuries from J2000.0. This is the time
  argument expected by Meeus-era polynomial series for precession,
  nutation, and orbital elements.

  ### Arguments

  * `t` is a moment (float Gregorian days since 0000-01-01) in UTC.

  ### Returns

  * Julian centuries from J2000.0 as a `float`.

  ### Examples

      iex> t = Astro.Time.date_time_to_moment(~U[2000-01-01 12:00:00Z])
      iex> Float.round(Astro.Time.julian_centuries_from_moment(t), 6)
      0.0

  """
  def julian_centuries_from_moment(t) do
    (dynamical_from_universal(t) - j2000()) / @julian_days_per_century
  end

  @doc """
  Returns the J2000.0 epoch as a moment (Gregorian days since
  0000-01-01).

  J2000.0 is 2000 January 1.5 TT (noon on January 1, 2000). This
  is the standard reference epoch for precession, nutation, and
  ephemeris polynomials.

  ### Returns

  * The J2000.0 moment as a `float` (730485.5).

  ### Examples

      iex> Astro.Time.j2000()
      730485.5

  """
  @new_year_2000 Date.new!(2000, 1, 1)
  @j2000 Date.to_gregorian_days(@new_year_2000) + 0.5

  def j2000 do
    @j2000
  end

  @doc """
  Returns the Julian day for a given number of Julian centuries
  from J2000.0.

  This is the inverse of `julian_centuries_from_julian_day/1`.

  ### Arguments

  * `julian_centuries` is a float number of Julian centuries from
    J2000.0.

  ### Returns

  * The Julian day as a `float`.

  ### Examples

      iex> Astro.Time.julian_day_from_julian_centuries(0.0)
      2451545.0

      iex> Astro.Time.julian_day_from_julian_centuries(1.0)
      2488070.0

  """
  @spec julian_day_from_julian_centuries(julian_centuries()) :: julian_days()
  def julian_day_from_julian_centuries(julian_centuries) do
    julian_centuries * @julian_days_per_century + @julian_day_jan_1_2000
  end

  @doc """
  Returns a UTC datetime for a given Julian day number.

  ### Arguments

  * `julian_day` is a Julian day number as a `float`.

  ### Returns

  * `{:ok, datetime}` — a `t:DateTime.t/0` in the UTC time zone.

  ### Examples

      iex> Astro.Time.datetime_from_julian_days(2458822.5)
      {:ok, ~U[2019-12-05 00:00:00Z]}

      iex> Astro.Time.datetime_from_julian_days(2451545.0)
      {:ok, ~U[2000-01-01 12:00:00Z]}

  """
  @spec datetime_from_julian_days(julian_days()) :: {:ok, Calendar.datetime()}
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

    {:ok, date} = Date.new(year, month, day)
    {:ok, time} = Time.new(hours, minutes, seconds)
    {:ok, naive_datetime} = NaiveDateTime.new(date, time)

    datetime_in_utc(naive_datetime)
  end

  @doc """
  Returns the date for a given Julian day number.

  The Julian day is rounded to the nearest integer before
  conversion. This is suitable when only the calendar date is
  needed, without time-of-day information.

  ### Arguments

  * `julian_day` is a Julian day number (float or integer).

  ### Returns

  * `{:ok, date}` — a `t:Date.t/0`.

  ### Examples

      iex> Astro.Time.date_from_julian_days(2458822.5)
      {:ok, ~D[2019-12-05]}

  """
  def date_from_julian_days(julian_days) do
    julian_days = round(julian_days)

    f = julian_days + 1_401 + div(div(4 * julian_days + 274_277, 146_097) * 3, 4) - 38
    e = 4 * f + 3
    g = rem(e, 1_461) |> div(4)
    h = 5 * g + 2

    day = rem(h, 153) |> div(5) |> Kernel.+(1)
    month = rem(div(h, 153) + 2, 12) + 1
    year = div(e, 1_461) - 4_716 + div(14 - month, 12)

    Date.new(year, month, day)
  end

  @doc """
  Converts a Terrestrial Time (TT) datetime to a UTC datetime.

  TT is the uniform atomic time scale on Earth's geoid, the modern
  successor to Ephemeris Time (ET). This library treats TT as
  identical to dynamical time (TDB), since the two differ by at most
  ~1.7 ms — well below the precision of rise/set calculations.

  Internally this converts the TT datetime to a moment, applies the
  same ΔT subtraction as `universal_from_dynamical/1`, and converts
  back to a UTC `DateTime`.

  ### Arguments

  * `datetime` is a `DateTime` whose clock reading is in Terrestrial
    Time (equivalently, dynamical time).

  ### Returns

  * `{:ok, utc_datetime}` — the corresponding UTC `DateTime`.

  ### Examples

      iex> {:ok, tt} = Astro.Time.datetime_from_julian_days(2451545.0)
      iex> {:ok, utc} = Astro.Time.utc_datetime_from_dynamical_datetime(tt)
      iex> DateTime.truncate(utc, :second)
      ~U[2000-01-01 11:58:56Z]

  """
  @spec utc_datetime_from_dynamical_datetime(Calendar.datetime()) :: {:ok, Calendar.datetime()}
  def utc_datetime_from_dynamical_datetime(datetime) do
    tt_moment = date_time_to_moment(datetime)
    utc_moment = universal_from_dynamical(tt_moment)
    date_time_from_moment(utc_moment)
  end

  @doc """
  Returns the Modified Julian Day (MJD) for a given date.

  MJD is JD − 2400000.5, shifting the day boundary from noon to
  midnight and producing smaller numbers. MJD 0 corresponds to
  1858-11-17 00:00:00 UTC.

  ### Arguments

  * `date` is any `t:Calendar.date/0`.

  ### Returns

  * The Modified Julian Day as a `float`.

  ### Examples

      iex> Astro.Time.mjd(~D[2019-12-05])
      58822.0

  """
  @spec mjd(Calendar.date()) :: julian_days()
  def mjd(date) do
    ajd(date) - 2_400_000.5
  end

  @doc """
  Returns a UTC datetime by combining a date with a float number
  of hours since midnight.

  ### Arguments

  * `time_of_day` is a float number of hours since midnight
    (e.g. 13.5 for 1:30 PM).
  * `date` is any `t:Calendar.date/0`.

  ### Returns

  * `{:ok, datetime}` — a `t:DateTime.t/0` in UTC.

  ### Examples

      iex> {:ok, dt} = Astro.Time.hours_and_date_to_datetime(12.0, ~D[2024-06-21])
      iex> DateTime.truncate(dt, :second)
      ~U[2024-06-21 12:00:00Z]

  """
  @spec hours_and_date_to_datetime(hours(), Calendar.date()) :: {:ok, Calendar.datetime()}
  def hours_and_date_to_datetime(time_of_day, %{year: year, month: month, day: day}) do
    with {hours, minutes, seconds} <- hours_to_hms(time_of_day),
         {:ok, naive_datetime} <- NaiveDateTime.new(year, month, day, hours, minutes, seconds, 0) do
      datetime_in_utc(naive_datetime)
    end
  end

  @doc """
  Returns an `{hours, minutes, seconds}` tuple for a given float
  number of hours since midnight.

  ### Arguments

  * `time_of_day` is a float number of hours since midnight.

  ### Returns

  * A `{hour, minute, second}` tuple. Fractional seconds are
    truncated.

  ### Examples

      iex> Astro.Time.hours_to_hms(0.0)
      {0, 0, 0}

      iex> Astro.Time.hours_to_hms(23.999)
      {23, 59, 56}

      iex> Astro.Time.hours_to_hms(15.456)
      {15, 27, 21}

  """
  @spec hours_to_hms(hours()) :: hms()
  def hours_to_hms(time_of_day) when is_float(time_of_day) do
    hours = trunc(time_of_day)
    minutes = (time_of_day - hours) * @minutes_per_hour
    seconds = (minutes - trunc(minutes)) * @seconds_per_minute

    {hours, trunc(minutes), trunc(seconds)}
  end

  @doc """
  Returns the number of days for a given number of hours.

  ### Arguments

  * `hours` is a number of hours.

  ### Returns

  * The equivalent number of days as a `float`.

  ### Examples

      iex> Astro.Time.hours_to_days(48)
      2.0

      iex> Astro.Time.hours_to_days(6)
      0.25

  """
  @spec hours_to_days(hours()) :: days()
  def hours_to_days(hours) do
    hours / @hours_per_day
  end

  @doc """
  Returns an `{hours, minutes, seconds}` tuple for a given number
  of seconds since midnight.

  ### Arguments

  * `time_of_day` is a number of seconds since midnight.

  ### Returns

  * A `{hour, minute, second}` tuple. Fractional seconds are
    truncated.

  ### Examples

      iex> Astro.Time.seconds_to_hms(0.0)
      {0, 0, 0}

      iex> Astro.Time.seconds_to_hms(3214)
      {0, 53, 34}

      iex> Astro.Time.seconds_to_hms(10_000)
      {2, 46, 39}

  """
  @spec seconds_to_hms(fraction_of_day()) :: hms()
  def seconds_to_hms(time_of_day) when is_number(time_of_day) do
    (time_of_day / @seconds_per_minute / @minutes_per_hour)
    |> hours_to_hms()
  end

  @doc """
  Returns a UTC datetime by combining a date with a float number
  of minutes since midnight.

  ### Arguments

  * `minutes` is a float number of minutes since midnight.
  * `date` is any `t:Calendar.date/0`.

  ### Returns

  * `{:ok, datetime}` — a `t:DateTime.t/0` in UTC.

  ### Examples

      iex> Astro.Time.datetime_from_date_and_minutes(720.0, ~D[2024-06-21])
      {:ok, ~U[2024-06-21 12:00:00Z]}

  """
  @spec datetime_from_date_and_minutes(minutes(), Calendar.date()) :: {:ok, Calendar.datetime()}
  def datetime_from_date_and_minutes(minutes, date) do
    {:ok, naive_datetime} = NaiveDateTime.new(date.year, date.month, date.day, 0, 0, 0)
    {:ok, datetime} = datetime_in_utc(naive_datetime)
    {:ok, DateTime.add(datetime, trunc(minutes * @seconds_per_minute), :second)}
  end

  @doc false
  def adjust_for_wraparound(datetime, location, %{rise_or_set: :rise}) do
    # sunrise after 6pm indicates the UTC date has occurred earlier
    if datetime.hour + local_hour_offset(datetime, location) > 18 do
      {:ok, DateTime.add(datetime, -@seconds_per_day, :second)}
    else
      {:ok, datetime}
    end
  end

  def adjust_for_wraparound(datetime, location, %{rise_or_set: :set}) do
    # sunset before 6am indicates the UTC date has occurred later
    if datetime.hour + local_hour_offset(datetime, location) < 6 do
      {:ok, DateTime.add(datetime, @seconds_per_day, :second)}
    else
      {:ok, datetime}
    end
  end

  defp local_hour_offset(datetime, location) do
    gregorian_seconds = date_time_to_gregorian_seconds(datetime)

    local_mean_time_offset =
      local_mean_time_offset(location, gregorian_seconds, datetime.time_zone)

    (local_mean_time_offset + datetime.std_offset) / @seconds_per_hour
  end

  @doc false
  def antimeridian_adjustment(location, %{time_zone: time_zone} = datetime, options) do
    %{time_zone_database: time_zone_database} = options
    gregorian_seconds = date_time_to_gregorian_seconds(datetime)

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

  @doc """
  Returns the time zone offset as a fraction of a day for a given
  instant and time zone.

  ### Arguments

  * `gregorian_seconds` is the number of seconds since the Gregorian
    epoch (0000-01-01 00:00:00).
  * `time_zone` is a time zone name string (e.g. `"Europe/London"`).
  * `time_zone_database` is the time zone database module (defaults
    to `Calendar.get_time_zone_database()`).

  ### Returns

  * The total offset (UTC offset + DST) as a fraction of a day
    (float).
  * `:ambiguous_time` if the instant falls in a DST overlap.
  * `:no_such_time_or_zone` if the zone is unknown or the instant
    falls in a DST gap.

  ### Examples

      iex> t = Date.to_gregorian_days(~D[2021-08-01]) * (60 * 60 * 24)
      iex> Astro.Time.offset_for_zone(t, "Europe/London")
      0.041666666666666664

  """
  @spec offset_for_zone(moment(), zone_name()) :: fraction_of_day()
  def offset_for_zone(
        gregorian_seconds,
        time_zone,
        time_zone_database \\ Calendar.get_time_zone_database()
      )
      when is_number(gregorian_seconds) and is_binary(time_zone) do
    case periods_for_time(time_zone, gregorian_seconds, time_zone_database) do
      [period] ->
        (period.utc_offset + period.std_offset) / @seconds_per_day

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
        with {:ok, time_zone} <- timezone_at(location, options[:time_zone_resolver]) do
          DateTime.shift_zone(utc_event_time, time_zone, time_zone_database)
        end

      time_zone when is_binary(time_zone) ->
        DateTime.shift_zone(utc_event_time, time_zone, time_zone_database)
    end
  end

  @doc false
  if Code.ensure_loaded?(TzWorld) do
    def timezone_at(%Geo.PointZ{} = location, nil) do
      location = %Geo.Point{coordinates: Tuple.delete_at(location.coordinates, 2)}
      TzWorld.timezone_at(location)
    end
  else
    def timezone_at(%Geo.PointZ{} = _location, nil) do
      {:error, :time_zone_not_resolved}
    end
  end

  def timezone_at(%Geo.PointZ{} = location, time_zone_resolver) do
    location = %Geo.Point{coordinates: Tuple.delete_at(location.coordinates, 2)}
    time_zone_resolver.(location)
  end

  # ── Unified ΔT computation ────────────────────────────────────────────────

  # IERS-observed ΔT values (TT − UT1 ≈ TT − UTC to within 0.9 s),
  # one value per year at the year midpoint (July 1), 1972–2025.
  # Source: IERS Earth Orientation Parameters, Bulletin A/B.
  @iers_delta_t_table %{
    1972 => 42.23,
    1973 => 43.37,
    1974 => 44.49,
    1975 => 45.48,
    1976 => 46.46,
    1977 => 47.52,
    1978 => 48.53,
    1979 => 49.59,
    1980 => 50.54,
    1981 => 51.38,
    1982 => 52.17,
    1983 => 52.96,
    1984 => 53.79,
    1985 => 54.34,
    1986 => 54.87,
    1987 => 55.32,
    1988 => 55.82,
    1989 => 56.30,
    1990 => 56.86,
    1991 => 57.57,
    1992 => 58.31,
    1993 => 59.12,
    1994 => 59.98,
    1995 => 60.78,
    1996 => 61.63,
    1997 => 62.29,
    1998 => 62.97,
    1999 => 63.47,
    2000 => 63.83,
    2001 => 64.09,
    2002 => 64.30,
    2003 => 64.47,
    2004 => 64.57,
    2005 => 64.69,
    2006 => 64.85,
    2007 => 65.15,
    2008 => 65.46,
    2009 => 65.78,
    2010 => 66.07,
    2011 => 66.32,
    2012 => 66.60,
    2013 => 66.91,
    2014 => 67.28,
    2015 => 67.64,
    2016 => 68.10,
    2017 => 68.59,
    2018 => 68.97,
    2019 => 69.22,
    2020 => 69.36,
    2021 => 69.36,
    2022 => 69.18,
    2023 => 69.04,
    2024 => 69.18,
    2025 => 69.30
  }

  @iers_first_year 1972
  @iers_last_year 2025
  # Linear extrapolation rate beyond the IERS table (seconds/year).
  @iers_extrap_rate 0.15

  # Meeus biennial lookup table for 1620–2002 (ΔT in seconds, even years only).
  # Source: Meeus, Astronomical Algorithms, Table 10.A.
  @meeus_delta_t_tuple {
    121,
    112,
    103,
    95,
    88,
    82,
    77,
    72,
    68,
    63,
    60,
    56,
    53,
    51,
    48,
    46,
    44,
    42,
    40,
    38,
    35,
    33,
    31,
    29,
    26,
    24,
    22,
    20,
    18,
    16,
    14,
    12,
    11,
    10,
    9,
    8,
    7,
    7,
    7,
    7,
    7,
    7,
    8,
    8,
    9,
    9,
    9,
    9,
    9,
    10,
    10,
    10,
    10,
    10,
    10,
    10,
    10,
    11,
    11,
    11,
    11,
    11,
    12,
    12,
    12,
    12,
    13,
    13,
    13,
    14,
    14,
    14,
    14,
    15,
    15,
    15,
    15,
    15,
    16,
    16,
    16,
    16,
    16,
    16,
    16,
    16,
    15,
    15,
    14,
    13,
    13.1,
    12.5,
    12.2,
    12.0,
    12.0,
    12.0,
    12.0,
    12.0,
    12.0,
    11.9,
    11.6,
    11.0,
    10.2,
    9.2,
    8.2,
    7.1,
    6.2,
    5.6,
    5.4,
    5.3,
    5.4,
    5.6,
    5.9,
    6.2,
    6.5,
    6.8,
    7.1,
    7.3,
    7.5,
    7.6,
    7.7,
    7.3,
    6.2,
    5.2,
    2.7,
    1.4,
    -1.2,
    -2.8,
    -3.8,
    -4.8,
    -5.5,
    -5.3,
    -5.6,
    -5.7,
    -5.9,
    -6.0,
    -6.3,
    -6.5,
    -6.2,
    -4.7,
    -2.8,
    -0.1,
    2.6,
    5.3,
    7.7,
    10.4,
    13.3,
    16.0,
    18.2,
    20.2,
    21.1,
    22.4,
    23.5,
    23.8,
    24.3,
    24.0,
    23.9,
    23.9,
    23.7,
    24.0,
    24.3,
    25.3,
    26.2,
    27.3,
    28.2,
    29.1,
    30.0,
    30.7,
    31.4,
    32.2,
    33.1,
    34.0,
    35.0,
    36.5,
    38.3,
    40.2,
    42.2,
    44.5,
    46.5,
    48.5,
    50.5,
    52.5,
    53.8,
    54.9,
    55.8,
    56.9,
    58.3,
    60.0,
    61.6,
    63.0,
    63.8,
    64.3
  }

  @meeus_first_year 1620
  @meeus_last_year 2002

  @doc """
  Returns ΔT (TT − UTC) in seconds for the given decimal year.

  ΔT is the difference between Terrestrial Time (TT) and Universal
  Time (UTC). It varies over time as Earth's rotation rate changes.

  Uses the best available data for each era:
  - **1972–2025**: IERS-observed annual values with linear interpolation
  - **1620–1971**: Meeus biennial lookup table with interpolation
  - **Pre-1620 and post-2025**: Polynomial approximations

  ### Arguments

  * `year` is a decimal year (e.g., 2024.5 for mid-2024)

  ### Returns

  * ΔT in seconds as a `float`.

  ### Examples

      iex> Astro.Time.delta_t(2000.0)
      63.83

      iex> Float.round(Astro.Time.delta_t(2024.5), 2)
      69.24

  """
  @spec delta_t(float()) :: float()
  def delta_t(year) when is_number(year) do
    cond do
      # IERS observed values — most accurate for modern dates
      year >= @iers_first_year and year <= @iers_last_year ->
        iers_delta_t(year)

      # Post-IERS: extrapolate forward from last IERS entry
      year > @iers_last_year ->
        @iers_delta_t_table[@iers_last_year] + @iers_extrap_rate * (year - @iers_last_year)

      # Meeus biennial table for 1620–1971
      year >= @meeus_first_year ->
        meeus_table_delta_t(year)

      # Pre-1620: Meeus polynomial approximations
      year < 948 ->
        t = (year - 2000) / 100.0
        2177 + 497 * t + 44.1 * t * t

      true ->
        # 948–1619
        t = (year - 2000) / 100.0
        102 + 102 * t + 25.3 * t * t
    end
  end

  # IERS annual interpolation
  defp iers_delta_t(year) do
    y0 = trunc(year)
    y1 = y0 + 1
    frac = year - y0

    v0 = @iers_delta_t_table[y0] || @iers_delta_t_table[@iers_first_year]
    v1 = @iers_delta_t_table[y1] || @iers_delta_t_table[@iers_last_year]
    v0 + frac * (v1 - v0)
  end

  # Meeus biennial table interpolation (even-year entries, 1620–2002)
  defp meeus_table_delta_t(year) do
    year_int = trunc(year)

    cond do
      year_int >= @meeus_first_year and year_int <= @meeus_last_year and rem(year_int, 2) == 0 ->
        idx = div(year_int - @meeus_first_year, 2)
        v0 = elem(@meeus_delta_t_tuple, idx)
        # Interpolate fractional year within the 2-year bin
        if year_int + 2 <= @meeus_last_year do
          v1 = elem(@meeus_delta_t_tuple, idx + 1)
          frac = (year - year_int) / 2.0
          v0 + frac * (v1 - v0)
        else
          v0
        end

      year_int >= @meeus_first_year and year_int <= @meeus_last_year ->
        # Odd year: average of neighboring even years
        v_prev = meeus_table_delta_t(year_int - 1.0)
        v_next = meeus_table_delta_t(year_int + 1.0)
        frac = year - year_int
        avg = (v_prev + v_next) / 2.0

        if year_int + 1 <= @meeus_last_year do
          avg + frac * (v_next - avg)
        else
          avg
        end

      true ->
        # Shouldn't reach here, but fallback to polynomial
        t = (year - 2000) / 100.0
        102 + 102 * t + 25.3 * t * t
    end
  end

  # ── Dynamical time / moment conversions ──────────────────────────────────────

  # J2000.0 Julian date (TT): 2000-01-01 12:00:00 TT
  @jd_j2000 2_451_545.0

  # Offset from Gregorian day 0 (0000-01-01) to JD 0.
  @jd_gregorian_epoch 1_721_059.5

  @doc """
  Returns dynamical time (TDB seconds past J2000.0) for a given
  UTC moment.

  Applies a date-dependent ΔT via `delta_t/1` to convert the UTC
  moment to TDB, the time scale expected by the JPL SPK ephemeris
  kernel.

  ### Arguments

  * `moment` is a moment (float Gregorian days since 0000-01-01)
    in UTC.

  ### Returns

  * Dynamical time as a `float` (TDB seconds past J2000.0).

  ### Examples

      iex> t = Astro.Time.date_time_to_moment(~U[2000-01-01 12:00:00Z])
      iex> dt = Astro.Time.dynamical_time_from_moment(t)
      iex> Float.round(dt, 1)
      63.8

  """
  @spec dynamical_time_from_moment(float()) :: float()
  def dynamical_time_from_moment(moment) do
    jd_utc = moment + @jd_gregorian_epoch
    year = jd_to_decimal_year(jd_utc)
    dt = delta_t(year)
    jd_tt = jd_utc + dt / @seconds_per_day
    (jd_tt - @jd_j2000) * @seconds_per_day
  end

  @doc """
  Returns a UTC moment for a given dynamical time (TDB seconds past
  J2000.0).

  This is the inverse of `dynamical_time_from_moment/1`. Subtracts a
  date-dependent ΔT to recover the UTC moment.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0 (float).

  ### Returns

  * A moment (float Gregorian days since 0000-01-01) in UTC.

  ### Examples

      iex> t = Astro.Time.date_time_to_moment(~U[2000-01-01 12:00:00Z])
      iex> dt = Astro.Time.dynamical_time_from_moment(t)
      iex> round_trip = Astro.Time.dynamical_time_to_moment(dt)
      iex> Float.round(abs(round_trip - t) * 86400, 3)
      0.0

  """
  @spec dynamical_time_to_moment(float()) :: float()
  def dynamical_time_to_moment(dynamical_time) do
    jd_tt = dynamical_time / @seconds_per_day + @jd_j2000
    year = jd_to_decimal_year(jd_tt)
    dt = delta_t(year)
    jd_utc = jd_tt - dt / @seconds_per_day
    jd_utc - @jd_gregorian_epoch
  end

  @doc """
  Returns Julian centuries from J2000.0 for a given dynamical time.

  A pure arithmetic conversion: divides TDB seconds by the number
  of seconds in a Julian century (36525 × 86400).

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0 (float).

  ### Returns

  * Julian centuries from J2000.0 as a `float`.

  ### Examples

      iex> Astro.Time.julian_centuries_from_dynamical_time(0.0)
      0.0

      iex> Astro.Time.julian_centuries_from_dynamical_time(36525.0 * 86400.0)
      1.0

  """
  @spec julian_centuries_from_dynamical_time(float()) :: float()
  def julian_centuries_from_dynamical_time(dynamical_time) do
    dynamical_time / (@seconds_per_day * 36_525.0)
  end

  # Converts a Julian Date to a decimal year (approximate, for ΔT lookup).
  defp jd_to_decimal_year(jd) do
    2000.0 + (jd - @jd_j2000) / 365.25
  end

  @doc """
  Returns a UTC `DateTime` for a given moment.

  A moment is by definition in the UTC timezone, so the returned
  `DateTime` always has `time_zone: "Etc/UTC"`. Microsecond
  precision is preserved.

  ### Arguments

  * `moment` is a float representation of a UTC datetime where
    the integer part is the number of Gregorian days since
    0000-01-01 and the fractional part is the fraction of a day
    since midnight.

  ### Returns

  * `{:ok, datetime}` — a `t:DateTime.t/0` in UTC with
    microsecond precision.

  ### Examples

      iex> Astro.Time.date_time_from_moment(740047.5)
      {:ok, ~U[2026-03-07 12:00:00.000000Z]}

      iex> Astro.Time.date_time_from_moment(740047.0)
      {:ok, ~U[2026-03-07 00:00:00.000000Z]}

      iex> Astro.Time.date_time_from_moment(740047.999999)
      {:ok, ~U[2026-03-07 23:59:59.913599Z]}

  """
  @spec date_time_from_moment(moment()) :: {:ok, DateTime.t()}

  def date_time_from_moment(t) do
    days = trunc(t)
    frac_us = round((t - days) * @seconds_per_day * 1_000_000)

    # Handle rounding that pushes past midnight
    us_per_day = 86_400_000_000

    {days, frac_us} =
      if frac_us >= us_per_day, do: {days + 1, frac_us - us_per_day}, else: {days, frac_us}

    total_seconds = div(frac_us, 1_000_000)
    microseconds = rem(frac_us, 1_000_000)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    seconds = rem(total_seconds, 60)

    date = Elixir.Date.from_gregorian_days(days)

    with {:ok, naive} <-
           NaiveDateTime.new(
             date.year,
             date.month,
             date.day,
             hours,
             minutes,
             seconds,
             {microseconds, 6}
           ) do
      datetime_in_utc(naive)
    end
  end

  @doc """
  Returns a moment for a given date or datetime.

  A moment is a float where the integer part is the number of Gregorian
  days since 0000-01-01 and the fractional part is the fraction of a day
  since midnight. Moments are always in UTC.

  When given a `DateTime`, it is first shifted to UTC before conversion.
  When given a `Date`, returns the integer Gregorian day number
  (midnight UTC).

  ### Arguments

  * `date_or_datetime` is any `t:Calendar.date/0` or
    `t:Calendar.datetime/0`.

  ### Returns

  * A moment as a `float` (or integer for `Date` inputs).

  ### Examples

      iex> Astro.Time.date_time_to_moment(~U[2026-03-07 12:00:00Z])
      740047.5

      iex> Astro.Time.date_time_to_moment(~D[2026-03-07])
      740047

  """
  @spec date_time_to_moment(Calendar.date() | Calendar.datetime()) :: moment()

  def date_time_to_moment(unquote(Guards.datetime()) = date_time) do
    utc_dt = DateTime.shift_zone!(date_time, "Etc/UTC")
    %{year: year, month: month, day: day, hour: hour} = utc_dt
    %{minute: minute, second: second, microsecond: microsecond} = utc_dt

    {days, {numerator, denominator}} =
      calendar.naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond)

    days + numerator / denominator
  end

  def date_time_to_moment(unquote(Guards.date()) = date) do
    {days, {_numerator, _denominator}} =
      calendar.naive_datetime_to_iso_days(date.year, date.month, date.day, 0, 0, 0, {0, 0})

    days
  end

  defp date_time_to_gregorian_seconds(datetime) do
    {numerator, denominator} = DateTime.to_gregorian_seconds(datetime)

    if denominator == 0 do
      numerator
    else
      numerator / denominator
    end
  end

  @doc false
  def periods_for_time(time_zone, gregorian_seconds, time_zone_database) do
    {:ok, date_time} = date_time_from_moment(gregorian_seconds / @seconds_per_day)

    case time_zone_database.time_zone_periods_from_wall_datetime(date_time, time_zone) do
      {:ok, zone} -> [zone]
      other -> other
    end
  end

  @doc false
  def datetime_in_utc(
        datetime,
        time_zone \\ @utc_zone,
        time_zone_database \\ Calendar.get_time_zone_database()
      ) do
    case DateTime.from_naive(datetime, time_zone, time_zone_database) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, error} -> {:error, error}
      {:ambiguous, _datetime1, datetime2} -> {:ok, datetime2}
      {:gap, _datetime1, datetime2} -> {:ok, datetime2}
    end
  end
end
