defmodule Astro.Solar do
  @moduledoc """
  Solar position, orbital mechanics, and equinox/solstice calculations.

  The Sun's apparent position is evaluated from the JPL DE440s
  ephemeris via `Astro.Ephemeris`. The Meeus *Astronomical Algorithms*
  series are retained only for the geometric mean longitude used by
  the equation of time and for the initial estimate that seeds the
  equinox and solstice search.

  For sunrise and sunset calculations see `Astro.Solar.SunRiseSet`.

  ## Function groups

  ### Position

  * `solar_position/1` — right ascension, declination and distance
  * `solar_ecliptic_longitude/1` — apparent ecliptic longitude at a moment
  * `solar_ecliptic_longitude_after/2`, `estimate_prior_solar_ecliptic_longitude/2`
  * `sun_geometric_mean_longitude/1` — mean longitude from Julian centuries

  ### Time

  * `equation_of_time/1` — difference between apparent and mean solar time
  * `solar_noon_utc/2` — UTC solar noon for a given longitude

  ### Equinoxes and solstices

  * `equinox_and_solstice/2` — March/September equinox or June/December solstice

  ### Solar elevation

  * `solar_elevation/1` — zenith angle for geometric, civil, nautical,
    astronomical twilight or a custom elevation

  ## Time conventions

  Functions in this module accept either a **moment** (fractional days
  since epoch) or **Julian centuries** from J2000.0, as noted in each
  function's documentation. Use `Astro.Time.julian_centuries_from_moment/1`
  to convert between the two.
  """

  alias Astro.{Math, Time}

  import Time,
    only: [
      minutes_per_day: 0
    ]

  import Math,
    only: [
      deg: 1,
      mod: 2
    ]

  @minutes_per_degree 4.0

  # Equinox/solstice periodic terms from Meeus Table 27.C (24 terms).
  # Each row: amplitude, addend (degrees), multiplier (degrees per Julian century).

  @periodic24_terms """
  485  324.96   1934.136
  203  337.23  32964.467
  199  342.08     20.186
  182   27.85 445267.112
  156   73.14  45036.886
  136  171.52  22518.443
   77  222.54  65928.934
   74  296.72   3034.906
   70  243.58   9037.513
   58  119.81  33718.147
   52  297.17    150.678
   50   21.02   2281.226
   45  247.54  29929.562
   44  325.15  31555.956
   29   60.93   4443.417
   18  155.12  67555.328
   17  288.79   4562.452
   16  198.04  62894.029
   14  199.76  31436.921
   12   95.39  14577.848
   12  287.11  31931.756
   12  320.81  34777.259
    9  227.73   1222.114
    8   15.45  16859.074
  """

  @p24_parsed @periodic24_terms
              |> String.split("\n", trim: true)
              |> Enum.map(fn line ->
                line
                |> String.split()
                |> Enum.map(fn s ->
                  case Float.parse(s) do
                    {f, ""} -> f
                    {f, _} -> f
                  end
                end)
                |> List.to_tuple()
              end)

  @p24_amplitudes Enum.map(@p24_parsed, &elem(&1, 0))
  @p24_addends Enum.map(@p24_parsed, &elem(&1, 1))
  @p24_multipliers Enum.map(@p24_parsed, &elem(&1, 2))

  @solar_elevation %{
    geometric: 90.0,
    civil: 96.0,
    nautical: 102.0,
    astronomical: 108.0
  }

  @valid_solar_elevation Map.keys(@solar_elevation)

  @doc false
  def solar_position(t) do
    {:ok, {right_ascension, declination, distance_km}} =
      Astro.Ephemeris.sun_position_from_moment(t)

    # Callers expect right ascension in (-180, 180], the range of the
    # previous atan2-based result, so it can occupy a Geo.PointZ longitude.
    right_ascension =
      if right_ascension > 180.0, do: right_ascension - 360.0, else: right_ascension

    {right_ascension, declination, Math.km_to_au(distance_km)}
  end

  @doc false
  def solar_elevation(solar_elevation) when solar_elevation in @valid_solar_elevation do
    Map.get(@solar_elevation, solar_elevation)
  end

  def solar_elevation(solar_elevation) when is_number(solar_elevation) do
    solar_elevation
  end

  @doc """
  Returns the solar ecliptic longitude in degrees.

  ### Arguments

  * `t` is any moment in time expressed as a moment
    (fractional days since the epoch).

  ### Returns

  * the solar ecliptic longitude in degrees as a `float`,
    in the range 0..360.

  ### Notes

  The solar ecliptic longitude is the position of the Sun on the
  celestial sphere along the ecliptic. It is also an effective
  measure of the position of the Earth in its orbit around the Sun,
  taken as 0° at the moment of the vernal equinox.

  Since it is based on how far the Earth has moved in its orbit
  since the equinox, it is a measure of what time of the tropical
  year (the year of seasons) has elapsed, without the inaccuracies
  of a calendar date which is perturbed by leap years and calendar
  imperfections.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~D[2024-03-20])
      iex> Astro.Solar.solar_ecliptic_longitude(moment)
      359.87145169401623

  """
  def solar_ecliptic_longitude(t) do
    {:ok, {longitude, _latitude, _distance}} = Astro.Ephemeris.sun_ecliptic_position(t)
    longitude
  end

  @doc """
  Returns the moment (UT) of the first time at or after moment `t`
  when the solar ecliptic longitude will be `lambda` degrees.

  ### Arguments

  * `lambda` is the target solar ecliptic longitude in degrees.

  * `t` is any moment in time expressed as a moment
    (fractional days since the epoch).

  ### Returns

  * the moment (fractional days since the epoch) when
    the solar ecliptic longitude reaches `lambda` degrees.

  ### Examples

      # Find the June solstice (longitude 90°) in 2024
      iex> moment = Astro.Time.date_time_to_moment(~D[2024-05-22])
      iex> result = Astro.Solar.solar_ecliptic_longitude_after(90, moment)
      iex> {:ok, dt} = Astro.Time.date_time_from_moment(result)
      iex> dt.year
      2024
      iex> dt.month
      6

  """
  @spec solar_ecliptic_longitude_after(number(), Time.time()) :: Time.time()

  def solar_ecliptic_longitude_after(lambda, t) do
    rate = Time.mean_tropical_year() / deg(360)
    tau = t + rate * mod(lambda - solar_ecliptic_longitude(t), 360)
    a = max(t, tau - 5)
    b = tau + 5

    Math.invert_angular(&solar_ecliptic_longitude/1, lambda, a, b)
  end

  @doc """
  Returns an approximate moment at or before `t`
  when the solar ecliptic longitude just exceeded `lambda` degrees.

  ### Arguments

  * `lambda` is the target solar ecliptic longitude in degrees.

  * `t` is any moment in time expressed as a moment
    (fractional days since the epoch).

  ### Returns

  * the approximate moment (fractional days since the epoch)
    at or before `t` when the solar ecliptic longitude
    last exceeded `lambda` degrees.

  ### Examples

      # Estimate when the Sun last passed 90° before the June solstice
      iex> moment = Astro.Time.date_time_to_moment(~D[2024-06-21])
      iex> result = Astro.Solar.estimate_prior_solar_ecliptic_longitude(90, moment)
      iex> {:ok, dt} = Astro.Time.date_time_from_moment(result)
      iex> dt.year
      2024
      iex> dt.month
      6

  """
  def estimate_prior_solar_ecliptic_longitude(lambda, t) do
    rate = Time.mean_tropical_year() / deg(360)
    tau = t - rate * mod(solar_ecliptic_longitude(t) - lambda, 360)
    cap_delta = mod(solar_ecliptic_longitude(tau) - lambda + deg(180), 360) - deg(180)
    min(t, tau - rate * cap_delta)
  end

  @doc """
  Returns solar noon as minutes since midnight UTC.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  * `longitude` is the longitude in degrees of the
    location from which solar noon is to be measured.
    West is negative.

  ### Returns

  * solar noon as a `float` number of minutes since
    midnight UTC.

  ### Notes

  Solar noon is the moment when the Sun passes a location's
  meridian and reaches its highest position in the sky.
  In most cases it does not occur at 12:00 local time.

  ### Examples

      iex> Astro.Solar.solar_noon_utc(0.0, 151.2093)
      1328.2818354717708

  """
  @spec solar_noon_utc(float, Astro.longitude()) :: float()
  def solar_noon_utc(julian_centuries, longitude) do
    century_start = Time.julian_day_from_julian_centuries(julian_centuries)

    # first pass to yield approximate solar noon
    approx_tnoon = Time.julian_centuries_from_julian_day(century_start + longitude / 360.0)
    approx_eq_time = equation_of_time(approx_tnoon)
    approx_sol_noon = 720.0 + longitude * @minutes_per_degree - approx_eq_time

    # refinement using output of first pass
    tnoon =
      Time.julian_centuries_from_julian_day(
        century_start - 0.5 + approx_sol_noon / minutes_per_day()
      )

    eq_time = equation_of_time(tnoon)
    720.0 + longitude * @minutes_per_degree - eq_time
  end

  @doc """
  Returns the equation of time in minutes.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the discrepancy between apparent solar time and
    mean solar time in minutes as a `float`. A positive
    value means the sundial is ahead of the clock.

  ### Notes

  The equation of time describes the discrepancy between
  apparent solar time (which directly tracks the Sun's
  diurnal motion) and mean solar time (which tracks a
  theoretical mean Sun with uniform motion).

  During a year the equation of time ranges from about
  +16 min 33 s (around 3 November) to −14 min 6 s
  (around 11 February), with zeros near 15 April,
  13 June, 1 September, and 25 December.

  The two principal causes are the obliquity of the
  ecliptic (~23.44°) and the eccentricity of the
  Earth's orbit (~0.0167).

  ### Examples

      iex> Astro.Solar.equation_of_time(0.0)
      -3.244441990189671

  """
  @spec equation_of_time(float) :: float()
  def equation_of_time(julian_centuries) when is_float(julian_centuries) do
    moment = Time.moment_from_julian_centuries(julian_centuries)
    {:ok, {right_ascension, _dec, _dist}} = Astro.Ephemeris.sun_position_from_moment(moment)

    mean_longitude = sun_geometric_mean_longitude(julian_centuries)
    diff = mean_longitude - right_ascension
    diff = diff - 360.0 * Float.round(diff / 360.0, 0)
    diff * @minutes_per_degree
  end

  @doc """
  Returns the Sun's geometric mean longitude in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the mean solar longitude in degrees as a `float`,
    in the range 0..360.

  ### Notes

  Mean longitude is a convenient uniform measure of how
  far around its orbit a body has progressed since passing
  the reference direction. While mean longitude assumes
  constant speed, true longitude accounts for the body's
  actual speed which varies around its elliptical orbit.
  The difference between the two is the equation of the
  centre.

  ### Examples

      iex> Astro.Solar.sun_geometric_mean_longitude(0.0)
      280.46646

  """
  @spec sun_geometric_mean_longitude(float) :: float()
  def sun_geometric_mean_longitude(julian_centuries) do
    longitude = 280.46646 + julian_centuries * (36_000.76983 + 0.0003032 * julian_centuries)
    Math.mod(longitude, 360.0)
  end

  @doc """
  Returns the UTC datetime of an equinox or solstice.

  ### Arguments

  * `year` is a positive integer Gregorian year.

  * `event` is one of `:march`, `:june`, `:september`,
    or `:december` identifying the equinox or solstice.

  ### Returns

  * `{:ok, datetime}` where `datetime` is a `DateTime.t()`
    in UTC.

  ### Notes

  The `:march` and `:september` events are the equinoxes
  (Sun's ecliptic longitude 0° and 180° respectively).
  The `:june` and `:december` events are the solstices
  (ecliptic longitude 90° and 270°).

  ### Examples

      iex> {:ok, dt} = Astro.Solar.equinox_and_solstice(2024, :march)
      iex> dt.year
      2024
      iex> dt.month
      3
      iex> dt.day
      20

  """
  @spec equinox_and_solstice(pos_integer, :march | :june | :september | :december) ::
          {:ok, DateTime.t()}

  def equinox_and_solstice(year, event) when event in [:march, :june, :september, :december] do
    jde0 = initial_estimate(year, event)
    t = (jde0 - 2_451_545.0) / 36_525
    w = 35_999.373 * t - 2.47
    dl = 1 + 0.0334 * Math.cos(w) + 0.0007 * Math.cos(2.0 * w)
    s = periodic24(t)
    jde = jde0 + 0.00001 * s / dl

    {:ok, tdt} = Time.date_time_from_julian_days(jde)
    Time.utc_date_time_from_dynamical_date_time(tdt)
  end

  defp initial_estimate(year, event) do
    year = (year - 2000) / 1000

    equinox_and_solstice_solar_terms()
    |> Map.get(event)
    |> Enum.with_index()
    |> Enum.reduce(0, fn {term, i}, acc ->
      acc + term * :math.pow(year, i)
    end)
  end

  defp equinox_and_solstice_solar_terms do
    %{
      march: [2_451_623.80984, 365_242.37404, 0.05169, -0.00411, -0.00057],
      june: [2_451_716.56767, 365_241.62603, 0.00325, 0.00888, -0.00030],
      september: [2_451_810.21715, 365_242.01767, -0.11575, 0.00337, 0.00078],
      december: [2_451_900.05952, 365_242.74049, -0.06223, -0.00823, 0.00032]
    }
  end

  defp periodic24(t) do
    periodic24(t, @p24_amplitudes, @p24_addends, @p24_multipliers)
  end

  defp periodic24(_t, [], [], []) do
    0
  end

  defp periodic24(t, [a | rest_a], [b | rest_b], [c | rest_c]) do
    a * Math.cos(b + c * t) + periodic24(t, rest_a, rest_b, rest_c)
  end
end
