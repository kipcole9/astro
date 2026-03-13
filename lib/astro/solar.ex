defmodule Astro.Solar do
  @moduledoc """
  Solar position, orbital mechanics, and equinox/solstice calculations.

  This module implements the analytical (polynomial + periodic-term)
  algorithms from Jean Meeus' *Astronomical Algorithms* for the Sun's
  geometric and apparent position, declination, equation of time, and
  equinox/solstice events.

  For sunrise and sunset calculations see `Astro.Solar.SunRiseSet`,
  which uses the JPL DE440s ephemeris rather than the Meeus
  approximations in this module.

  ## Function groups

  ### Position

  * `solar_position/1` — right ascension, declination and distance
  * `solar_declination/1` — declination from Julian centuries
  * `solar_distance/1` — Earth–Sun distance in AU
  * `solar_ecliptic_longitude/1` — ecliptic longitude at a moment
  * `solar_ecliptic_longitude_after/2`, `estimate_prior_solar_ecliptic_longitude/2`

  ### Apparent longitude and related

  * `sun_apparent_longitude/1` — apparent longitude (nutation + aberration corrected)
  * `sun_apparent_longitude_alt/1` — higher-precision 49-term series (Meeus Table 25.D)
  * `sun_true_longitude/1`, `sun_equation_of_center/1`
  * `sun_geometric_mean_longitude/1`, `sun_geometric_mean_anomaly/1`
  * `aberration/1`

  ### Time and geometry

  * `equation_of_time/1` — difference between apparent and mean solar time
  * `solar_noon_utc/2` — UTC solar noon for a given longitude
  * `earth_orbit_eccentricity/1`
  * `obliquity_correction/1`, `mean_obliquity_of_ecliptic/1`

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

  alias Astro.{Math, Time, Earth}

  import Time,
    only: [
      minutes_per_day: 0,
      julian_centuries_from_moment: 1
    ]

  import Math,
    only: [
      sin: 1,
      cos: 1,
      sigma: 2,
      deg: 1,
      mod: 2
    ]

  @minutes_per_degree 4.0

  # Apparent longitude periodic terms from Meeus Table 25.D (49 terms).
  # Each row: coefficient, addend (degrees), multiplier (degrees per Julian century).
  # Parsed at compile time into three parallel lists for use in sun_apparent_longitude_alt/1.

  @sun_apparent_longitude_terms """
  403406  270.54861      0.9287892
  195207  340.19128  35999.1376958
  119433   63.91854  35999.4089666
  112392  331.26220  35998.7287385
    3891  317.843    71998.20261
    2819   86.631    71998.4403
    1721  240.052    36000.35726
     660  310.26     71997.4812
     350  247.23     32964.4678
     334  260.87       -19.4410
     314  297.82    445267.1117
     268  343.14     45036.8840
     242  166.79         3.1008
     234   81.53     22518.4434
     158    3.50       -19.9739
     132  132.75     65928.9345
     129  182.95      9038.0293
     114  162.03      3034.7684
      99   29.8      33718.148
      93  266.4       3034.448
      86  249.2      -2280.773
      78  157.6      29929.992
      72  257.8      31556.493
      68  185.1        149.588
      64   69.9       9037.750
      46    8.0     107997.405
      38  197.1      -4444.176
      37  250.4        151.771
      32   65.3      67555.316
      29  162.7      31556.080
      28  341.5      -4561.540
      27  291.6     107996.706
      27   98.5       1221.655
      25  146.7      62894.167
      24  110.0      31437.369
      21    5.2      14578.298
      21  342.6     -31931.757
      20  230.9      34777.243
      18  256.1       1221.999
      17   45.3      62894.511
      14  242.9      -4442.039
      13  115.2     107997.909
      13  151.8        119.066
      13  285.3      16859.071
      12   53.3         -4.578
      10  126.6      26895.292
      10  205.7        -39.127
      10   85.9      12297.536
      10  146.1      90073.778
  """

  @sal_parsed @sun_apparent_longitude_terms
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

  @sal_coefficients Enum.map(@sal_parsed, &elem(&1, 0))
  @sal_addends Enum.map(@sal_parsed, &elem(&1, 1))
  @sal_multipliers Enum.map(@sal_parsed, &elem(&1, 2))

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

  @doc false
  def solar_position(t) do
    julian_centuries = julian_centuries_from_moment(t)
    apparent_longitude = sun_apparent_longitude(julian_centuries)
    declination = solar_declination(julian_centuries)
    distance = solar_distance(julian_centuries)
    right_ascension = Astro.right_ascension(t, 0.0, apparent_longitude)

    {right_ascension, declination, distance}
  end

  @doc false
  def solar_distance(julian_centuries) do
    eccentricity = earth_orbit_eccentricity(julian_centuries)
    mean_solar_anomaly = sun_geometric_mean_anomaly(julian_centuries)
    true_anomaly = mean_solar_anomaly + julian_centuries

    1.000001018 * (1.0 - eccentricity * eccentricity) / (1 + eccentricity * cos(true_anomaly))
  end

  @valid_solar_elevation Map.keys(@solar_elevation)

  @doc false
  def solar_elevation(solar_elevation) when solar_elevation in @valid_solar_elevation do
    Map.get(@solar_elevation, solar_elevation)
  end

  def solar_elevation(solar_elevation) when is_number(solar_elevation) do
    solar_elevation
  end

  @doc """
  Returns the solar declination in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the solar declination in degrees as a `float`.

  ### Notes

  The solar declination is the angle between the direction
  of the centre of the solar disk measured from Earth's
  centre and the equatorial plane. It ranges from approximately
  +23.44° at the June solstice to −23.44° at the December
  solstice, and is 0° at the equinoxes.

  ### Examples

      iex> Astro.Solar.solar_declination(0.0)
      ...> |> Float.round(4)
      -23.0325

  """
  @spec solar_declination(float) :: float()
  def solar_declination(julian_centuries) do
    correction = obliquity_correction(julian_centuries)
    lambda = sun_apparent_longitude(julian_centuries)
    sint = Math.sin(correction) * Math.sin(lambda)

    sint
    |> :math.asin()
    |> Math.to_degrees()
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
      359.87362951019264

  """
  def solar_ecliptic_longitude(t) do
    c = Time.julian_centuries_from_moment(t)
    sun_apparent_longitude(c)
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
  Returns the Sun's apparent longitude in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the Sun's apparent longitude in degrees as a `float`,
    in the range 0..360.

  ### Notes

  The apparent longitude is the Sun's celestial longitude
  corrected for aberration and nutation, as opposed to
  mean longitude.

  An equinox is the instant when the Sun's apparent
  geocentric longitude is 0° (northward equinox) or
  180° (southward equinox).

  ### Examples

      iex> Astro.Solar.sun_apparent_longitude(0.0)
      280.3725548788095

  """
  @spec sun_apparent_longitude(Time.julian_centuries()) :: float()
  def sun_apparent_longitude(julian_centuries) do
    true_longitude = sun_true_longitude(julian_centuries)
    omega = omega(julian_centuries)

    (true_longitude - 0.00569 - 0.00478 * :math.sin(Math.to_radians(omega)))
    |> Math.mod(360)
  end

  defp omega(julian_centuries) do
    125.04 - 1934.136 * julian_centuries
  end

  @doc false
  @spec sun_apparent_longitude_alt(Time.julian_centuries()) :: Time.season()
  def sun_apparent_longitude_alt(julian_centuries) do
    lambda =
      deg(282.7771834) + deg(36000.76953744) * julian_centuries +
        deg(0.000005729577951308232) *
          sigma(
            [@sal_coefficients, @sal_addends, @sal_multipliers],
            fn [x, y, z] -> x * sin(y + z * julian_centuries) end
          )

    {nutation, _, _} = Earth.nutation(julian_centuries)
    mod(lambda + aberration(julian_centuries) + nutation, 360.0)
  end

  @doc false
  @spec aberration(Time.moment()) :: Astro.angle()
  def aberration(c) do
    deg(0.0000974) * cos(deg(177.63) + deg(35999.01848) * c) - deg(0.005575)
  end

  @doc """
  Returns the Sun's true longitude in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the Sun's true longitude in degrees as a `float`.

  ### Notes

  In celestial mechanics, true longitude is the ecliptic
  longitude at which an orbiting body could actually be
  found if its inclination were zero. It is the sum of the
  geometric mean longitude and the equation of the centre.

  ### Examples

      iex> Astro.Solar.sun_true_longitude(0.0)
      280.38215851056276

  """
  @spec sun_true_longitude(float) :: float()
  def sun_true_longitude(julian_centuries) do
    sun_geometric_mean_longitude(julian_centuries) + sun_equation_of_center(julian_centuries)
  end

  @doc """
  Returns the Sun's equation of the centre in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the equation of the centre in degrees as a `float`.

  ### Notes

  In two-body Keplerian orbital mechanics, the equation
  of the centre is the angular difference between the
  actual position of a body in its elliptical orbit and
  the position it would occupy if its motion were uniform,
  in a circular orbit of the same period. It is defined
  as the difference between the true anomaly ν and the
  mean anomaly M.

  ### Examples

      iex> Astro.Solar.sun_equation_of_center(0.0)
      -0.08430148943719645

  """
  @spec sun_equation_of_center(float) :: float()
  def sun_equation_of_center(julian_centuries) do
    mrad = sun_geometric_mean_anomaly(julian_centuries) |> Math.to_radians()
    sinm = :math.sin(mrad)
    sin2m = :math.sin(2 * mrad)
    sin3m = :math.sin(3 * mrad)

    sinm * (1.914602 - julian_centuries * (0.004817 + 0.000014 * julian_centuries)) +
      sin2m * (0.019993 - 0.000101 * julian_centuries) +
      sin3m * 0.000289
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
      1328.3378566361976

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
      -3.3012588023605938

  """
  @spec equation_of_time(float) :: float()
  def equation_of_time(julian_centuries) when is_float(julian_centuries) do
    epsilon = obliquity_correction(julian_centuries) |> Math.to_radians()
    sgml = sun_geometric_mean_longitude(julian_centuries) |> Math.to_radians()
    sgma = sun_geometric_mean_anomaly(julian_centuries) |> Math.to_radians()
    eoe = earth_orbit_eccentricity(julian_centuries)

    y = :math.tan(epsilon / 2.0)
    y = y * y

    sin2l0 = :math.sin(2.0 * sgml)
    sin4l0 = :math.sin(4.0 * sgml)
    cos2l0 = :math.cos(2.0 * sgml)
    sinm = :math.sin(sgma)
    sin2m = :math.sin(2.0 * sgma)

    eq_time =
      y * sin2l0 - 2.0 * eoe * sinm + 4.0 * eoe * y * sinm * cos2l0 - 0.5 * y * y * sin4l0 -
        1.25 * eoe * eoe * sin2m

    Math.to_degrees(eq_time) * 4.0
  end

  @doc """
  Returns the Earth's orbital eccentricity.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * a unitless value of eccentricity as a `float`.
    A value of 0 is a circular orbit, values between
    0 and 1 form an elliptic orbit, 1 is a parabolic
    escape orbit, and greater than 1 is a hyperbola.
    Earth's current eccentricity is approximately 0.0167.

  ### Examples

      iex> Astro.Solar.earth_orbit_eccentricity(0.0)
      0.016708634

  """
  @spec earth_orbit_eccentricity(float) :: float()
  def earth_orbit_eccentricity(julian_centuries) do
    0.016708634 - julian_centuries * (0.000042037 + 0.0000001267 * julian_centuries)
  end

  @doc """
  Returns the Sun's geometric mean anomaly in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the mean anomaly in degrees as a `float`,
    in the range 0..360.

  ### Notes

  In celestial mechanics, the mean anomaly is the fraction
  of an elliptical orbit's period that has elapsed since the
  orbiting body passed periapsis, expressed as an angle. It is
  the angular distance from the pericentre which a fictitious
  body would have if it moved in a circular orbit, with constant
  speed, in the same orbital period as the actual body in its
  elliptical orbit.

  ### Examples

      iex> Astro.Solar.sun_geometric_mean_anomaly(0.0)
      357.52911

  """
  @spec sun_geometric_mean_anomaly(float) :: float()
  def sun_geometric_mean_anomaly(julian_centuries) do
    anomaly = 357.52911 + julian_centuries * (35999.05029 - 0.0001537 * julian_centuries)
    Math.mod(anomaly, 360.0)
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
    longitude = 280.46646 + julian_centuries * (36000.76983 + 0.0003032 * julian_centuries)
    Math.mod(longitude, 360.0)
  end

  @doc """
  Returns the corrected obliquity of the ecliptic in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the corrected obliquity of the ecliptic in degrees
    as a `float`.

  ### Notes

  The corrected obliquity accounts for the nutation in
  obliquity (a short-period oscillation), in addition
  to the mean obliquity which changes slowly over
  millennia.

  ### Examples

      iex> Astro.Solar.obliquity_correction(0.0)
      23.437821291789415

  """
  @spec obliquity_correction(float) :: float()
  def obliquity_correction(julian_centuries) do
    obliquity_of_ecliptic = mean_obliquity_of_ecliptic(julian_centuries)

    omega = omega(julian_centuries)
    correction = obliquity_of_ecliptic + 0.00256 * :math.cos(Math.to_radians(omega))
    Math.mod(correction, 360.0)
  end

  @doc """
  Returns the mean obliquity of the ecliptic in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the mean obliquity of the ecliptic in degrees
    as a `float`.

  ### Notes

  Obliquity is the angle between the Earth's rotational
  axis and the perpendicular to its orbital plane. Earth's
  current mean obliquity is about 23.44° and decreasing
  very slowly over millennia. This function returns the
  mean value without the short-period nutation correction;
  see `obliquity_correction/1` for the corrected value.

  ### Examples

      iex> Astro.Solar.mean_obliquity_of_ecliptic(0.0)
      23.43929111111111

  """
  @spec mean_obliquity_of_ecliptic(float) :: float()
  def mean_obliquity_of_ecliptic(julian_centuries) do
    seconds =
      21.448 -
        julian_centuries * (46.8150 + julian_centuries * (0.00059 - julian_centuries * 0.001813))

    # in degrees
    23.0 + (26.0 + seconds / 60.0) / 60.0
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
