defmodule Astro.Solar do
  @moduledoc """
  Solar position, orbital mechanics, and equinox/solstice calculations.

  ## Two sources of the Sun's position

  The Sun's apparent position comes from one of two sources:

  * **The JPL DE440s ephemeris**, read by `Astro.Ephemeris`. It is a
    numerical integration of the solar system, accurate to well under
    a milliarcsecond, but it covers a limited span of years (1900–2100
    for the file bundled with Astro).

  * **Analytical series**, computed in this module. They describe the
    Earth's orbit with a mean motion, the equation of the centre and a
    sum of periodic perturbations. They are less accurate (about 1″
    near the present) but give a position for any date.

  The analytical series work from the Earth's orbital elements:
  `sun_geometric_mean_longitude/1`, `sun_geometric_mean_anomaly/1`,
  `earth_orbit_eccentricity/1` and `sun_equation_of_center/1`.

  For sunrise and sunset calculations see `Astro.Solar.SunRiseSet`.

  ## Function groups

  ### Position

  * `solar_position/1` — right ascension, declination and distance
  * `solar_ecliptic_longitude/1` — apparent ecliptic longitude at a moment
  * `solar_ecliptic_longitude_after/2`, `estimate_prior_solar_ecliptic_longitude/2`

  ### Analytical series

  * `analytical_solar_ecliptic_position/1` — apparent ecliptic longitude, latitude and distance
  * `analytical_solar_position/1` — apparent right ascension, declination and distance

  ### Orbital elements

  * `sun_geometric_mean_longitude/1`, `sun_geometric_mean_anomaly/1`
  * `earth_orbit_eccentricity/1`, `sun_equation_of_center/1`

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

  alias Astro.{Earth, Math, Time}

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

  # Annual aberration constant in degrees (20.4898″ at 1 AU).
  @aberration_constant 20.4898 / 3600.0

  # Periodic terms of the Sun's longitude (Bretagnon and Simon, as given in
  # Calendrical Calculations). Each row: coefficient, addend in degrees,
  # multiplier in degrees per Julian century.
  @sun_longitude_terms """
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
                       |> String.split("\n", trim: true)
                       |> Enum.map(fn line ->
                         [coefficient, addend, multiplier] =
                           line
                           |> String.split()
                           |> Enum.map(fn field ->
                             {value, ""} = Float.parse(field)
                             value
                           end)

                         {coefficient, addend, multiplier}
                       end)

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
    {right_ascension, declination, distance} = apparent_sun_position(t)

    # Callers expect right ascension in (-180, 180], the range of the
    # previous atan2-based result, so it can occupy a Geo.PointZ longitude.
    right_ascension =
      if right_ascension > 180.0, do: right_ascension - 360.0, else: right_ascension

    {right_ascension, declination, distance}
  end

  # ── Choosing the source ───────────────────────────────────────────────────────
  #
  # The Sun's apparent position comes from the JPL ephemeris where the loaded
  # kernel covers the moment, and from the analytical series everywhere
  # else. Every position in this module goes through these two functions,
  # so the choice is made in one place. Distances are in astronomical units.

  defp apparent_sun_position(t) do
    case Astro.Ephemeris.sun_position_from_moment(t) do
      {:ok, {right_ascension, declination, distance_km}} ->
        {right_ascension, declination, Math.km_to_au(distance_km)}

      {:error, :not_found} ->
        analytical_solar_position(t)
    end
  end

  defp apparent_sun_ecliptic_position(t) do
    case Astro.Ephemeris.sun_ecliptic_position(t) do
      {:ok, {longitude, latitude, distance_km}} ->
        {longitude, latitude, Math.km_to_au(distance_km)}

      {:error, :not_found} ->
        analytical_solar_ecliptic_position(t)
    end
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

  The longitude comes from the JPL ephemeris where the loaded kernel
  covers `t`, and from `analytical_solar_ecliptic_position/1`, accurate
  to about 1″ near the present, everywhere else. Calendars that count
  months by the Sun's longitude, such as the Chinese and Japanese
  lunisolar calendars, find their solar terms for dates of any era this
  way.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~D[2024-03-20])
      iex> Astro.Solar.solar_ecliptic_longitude(moment)
      359.87140902027863

      iex> moment = Astro.Time.date_time_to_moment(~D[1000-06-01])
      iex> Astro.Solar.solar_ecliptic_longitude(moment) |> Float.round(4)
      69.5902

  """
  def solar_ecliptic_longitude(t) do
    {longitude, _latitude, _distance} = apparent_sun_ecliptic_position(t)
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
      1328.2818354717704

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
    {right_ascension, _declination, _distance} = apparent_sun_position(moment)

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
  Returns the Sun's geometric mean anomaly in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the mean anomaly in degrees as a `float`,
    in the range 0..360.

  ### Notes

  The mean anomaly is the angle the Earth would have moved through
  since perihelion if it travelled its orbit at a constant speed
  (Meeus, *Astronomical Algorithms*, equation 25.3). It grows
  uniformly with time, which makes it the natural argument for the
  equation of the centre.

  ### Examples

      iex> Astro.Solar.sun_geometric_mean_anomaly(0.0)
      357.52911

  """
  @spec sun_geometric_mean_anomaly(Time.julian_centuries()) :: float()
  def sun_geometric_mean_anomaly(julian_centuries) do
    anomaly = 357.52911 + julian_centuries * (35_999.05029 - 0.0001537 * julian_centuries)
    Math.mod(anomaly, 360.0)
  end

  @doc """
  Returns the eccentricity of the Earth's orbit.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the eccentricity as a unitless `float`. Zero is a circle and values
    between 0 and 1 are ellipses; the Earth's is about 0.0167 and slowly
    decreasing (Meeus, *Astronomical Algorithms*, equation 25.4).

  ### Examples

      iex> Astro.Solar.earth_orbit_eccentricity(0.0)
      0.016708634

  """
  @spec earth_orbit_eccentricity(Time.julian_centuries()) :: float()
  def earth_orbit_eccentricity(julian_centuries) do
    0.016708634 - julian_centuries * (0.000042037 + 0.0000001267 * julian_centuries)
  end

  @doc """
  Returns the Sun's equation of the centre in degrees.

  ### Arguments

  * `julian_centuries` is any moment in time expressed
    as Julian centuries from J2000.0.

  ### Returns

  * the equation of the centre in degrees as a `float`.

  ### Notes

  The equation of the centre is the difference between the true
  anomaly, where the Earth actually is on its ellipse, and the mean
  anomaly, where it would be at a constant speed. Adding it to the mean
  longitude gives the true longitude. This is the series of Meeus,
  *Astronomical Algorithms*, chapter 25, in the mean anomaly.

  ### Examples

      iex> Astro.Solar.sun_equation_of_center(0.0)
      -0.08430148943719645

  """
  @spec sun_equation_of_center(Time.julian_centuries()) :: float()
  def sun_equation_of_center(julian_centuries) do
    anomaly = Math.to_radians(sun_geometric_mean_anomaly(julian_centuries))

    :math.sin(anomaly) * (1.914602 - julian_centuries * (0.004817 + 0.000014 * julian_centuries)) +
      :math.sin(2 * anomaly) * (0.019993 - 0.000101 * julian_centuries) +
      :math.sin(3 * anomaly) * 0.000289
  end

  # ── Analytical series ─────────────────────────────────────────────────────────

  @doc """
  Returns the Sun's apparent geocentric ecliptic position from analytical
  series.

  The longitude is the Sun's true geometric longitude from the 49-term
  series of Bretagnon and Simon (as given in *Calendrical Calculations*),
  corrected for aberration and for the nutation in longitude of
  `Astro.Earth.nutation/1`. Over 1900–2100 it agrees with the JPL DE440s
  ephemeris to about 1″ RMS and 3.3″ at most. The latitude is taken as
  zero, since the Sun's never exceeds about 1.2″, and the distance is the
  radius vector of the Keplerian ellipse.

  ### Arguments

  * `t` is a moment (fractional days since the epoch).

  ### Returns

  * `{longitude, latitude, distance}` where `longitude` is in degrees in
    the range 0 to 360, `latitude` is `0.0` and `distance` is in
    astronomical units.

  ### Examples

      iex> {longitude, latitude, distance} =
      ...>   Astro.Solar.analytical_solar_ecliptic_position(Astro.Time.j2000())
      iex> {Float.round(longitude, 4), latitude, Float.round(distance, 6)}
      {280.369, 0.0, 0.983308}

  """
  @doc since: "2.10.0"
  @spec analytical_solar_ecliptic_position(Time.moment()) :: {float(), float(), float()}
  def analytical_solar_ecliptic_position(t) do
    {longitude, distance, _true_obliquity} = analytical_sun(t)
    {longitude, 0.0, distance}
  end

  @doc """
  Returns the Sun's apparent geocentric right ascension, declination and
  distance from analytical series.

  The ecliptic position of `analytical_solar_ecliptic_position/1` is
  rotated to the equator with the true obliquity of the ecliptic by
  `Astro.Coordinates.ecliptic_to_equatorial/3`.

  ### Arguments

  * `t` is a moment (fractional days since the epoch).

  ### Returns

  * `{right_ascension, declination, distance}` where `right_ascension`
    is in degrees in the range 0 to 360, `declination` is in degrees and
    `distance` is in astronomical units.

  ### Examples

      iex> {right_ascension, declination, distance} =
      ...>   Astro.Solar.analytical_solar_position(Astro.Time.j2000())
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), Float.round(distance, 6)}
      {281.2785, -23.0327, 0.983308}

  """
  @doc since: "2.10.0"
  @spec analytical_solar_position(Time.moment()) :: {float(), float(), float()}
  def analytical_solar_position(t) do
    {longitude, distance, true_obliquity} = analytical_sun(t)

    {right_ascension, declination} =
      Astro.Coordinates.ecliptic_to_equatorial(longitude, 0.0, true_obliquity)

    {right_ascension, declination, distance}
  end

  # The Sun's apparent longitude in degrees, its distance in astronomical
  # units and the true obliquity in degrees, sharing one evaluation of the
  # nutation.
  defp analytical_sun(t) do
    julian_centuries = Time.julian_centuries_from_moment(t)
    {delta_psi, delta_epsilon, mean_obliquity} = Earth.nutation(julian_centuries)

    apparent_longitude =
      sun_true_longitude_series(julian_centuries) + sun_aberration(julian_centuries) +
        Math.to_degrees(delta_psi)

    {Math.mod(apparent_longitude, 360.0), sun_radius_vector(julian_centuries),
     Math.to_degrees(mean_obliquity + delta_epsilon)}
  end

  # The Sun's true geometric longitude referred to the mean equinox of
  # date: a mean motion plus the periodic terms.
  defp sun_true_longitude_series(julian_centuries) do
    periodic =
      Enum.reduce(@sun_longitude_terms, 0.0, fn {coefficient, addend, multiplier}, sum ->
        sum + coefficient * Math.sin(addend + multiplier * julian_centuries)
      end)

    282.7771834 + 36_000.76953744 * julian_centuries + 0.000005729577951308232 * periodic
  end

  # Annual aberration, which displaces the Sun by about −20.5″ in longitude
  # in the direction of the Earth's motion.
  defp sun_aberration(julian_centuries) do
    0.0000974 * Math.cos(177.63 + 35_999.01848 * julian_centuries) - 0.005575
  end

  # The radius vector of the Keplerian ellipse in astronomical units
  # (Meeus, Astronomical Algorithms, equation 25.5), with the true anomaly
  # as the mean anomaly plus the equation of the centre.
  defp sun_radius_vector(julian_centuries) do
    eccentricity = earth_orbit_eccentricity(julian_centuries)

    true_anomaly =
      sun_geometric_mean_anomaly(julian_centuries) + sun_equation_of_center(julian_centuries)

    1.000001018 * (1.0 - eccentricity * eccentricity) /
      (1.0 + eccentricity * Math.cos(true_anomaly))
  end

  # ── Deprecated ────────────────────────────────────────────────────────────────

  @doc false
  @deprecated "Use Astro.Solar.solar_ecliptic_longitude/1, which takes a moment, instead"
  @spec sun_apparent_longitude(Time.julian_centuries()) :: float()
  def sun_apparent_longitude(julian_centuries) do
    apparent_longitude(julian_centuries)
  end

  @doc false
  @deprecated "Use Astro.Solar.solar_position/1, which takes a moment, instead"
  @spec solar_declination(Time.julian_centuries()) :: float()
  def solar_declination(julian_centuries) do
    moment = Time.moment_from_julian_centuries(julian_centuries)
    {_right_ascension, declination, _distance} = apparent_sun_position(moment)
    declination
  end

  @doc false
  @deprecated "Use Astro.Solar.solar_ecliptic_longitude/1 for the Sun's apparent longitude instead"
  @spec sun_true_longitude(Time.julian_centuries()) :: float()
  def sun_true_longitude(julian_centuries) do
    true_longitude(julian_centuries)
  end

  @doc false
  @deprecated "Use Astro.Earth.nutation/1, which returns the obliquity in radians, instead"
  @spec obliquity_correction(Time.julian_centuries()) :: float()
  def obliquity_correction(julian_centuries) do
    {_delta_psi, delta_epsilon, mean_obliquity} = Earth.nutation(julian_centuries)
    Math.to_degrees(mean_obliquity + delta_epsilon)
  end

  @doc false
  @deprecated "Use Astro.Earth.nutation/1, which returns the obliquity in radians, instead"
  @spec mean_obliquity_of_ecliptic(Time.julian_centuries()) :: float()
  def mean_obliquity_of_ecliptic(julian_centuries) do
    {_delta_psi, _delta_epsilon, mean_obliquity} = Earth.nutation(julian_centuries)
    Math.to_degrees(mean_obliquity)
  end

  defp apparent_longitude(julian_centuries) do
    julian_centuries
    |> Time.moment_from_julian_centuries()
    |> solar_ecliptic_longitude()
  end

  # The geometric longitude referred to the mean equinox of date: the
  # apparent longitude without nutation and with aberration restored.
  defp true_longitude(julian_centuries) do
    moment = Time.moment_from_julian_centuries(julian_centuries)
    {longitude, _latitude, distance} = apparent_sun_ecliptic_position(moment)
    {delta_psi, _delta_epsilon, _mean_obliquity} = Earth.nutation(julian_centuries)
    aberration = @aberration_constant / distance
    Math.mod(longitude - Math.to_degrees(delta_psi) + aberration, 360.0)
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
