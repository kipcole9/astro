defmodule Astro.Solar do
  @moduledoc """
  Implements sunrise and sunset according to the
  US NOAA algorithm which is based upon
  [Astronomical Algorithms](https://www.amazon.com/Astronomical-Algorithms-Jean-Meeus/dp/0943396352)
  by Jean Meeus.

  """

  alias Astro.{Utils, Earth, Time}

  @solar_elevation %{
    geometric: 90.0,
    civil: 96.0,
    nautical: 102.0,
    astronomical: 108.0
  }

  @doc false
  def sun_rise_or_set(location, date, options) when is_list(options) do
    options =
      Astro.default_options()
      |> Keyword.merge(options)
      |> Map.new()

    sun_rise_or_set(location, date, options)
  end

  @doc false
  def sun_rise_or_set(%Geo.PointZ{} = location, %Date{} = date, options) do
    with {:ok, naive_datetime} <-
           NaiveDateTime.new(date.year, date.month, date.day, 0, 0, 0, {0, 0}, date.calendar) do
      sun_rise_or_set(location, naive_datetime, options)
    end
  end

  @doc false
  def sun_rise_or_set(%Geo.PointZ{} = location, %NaiveDateTime{} = datetime, options) do
    %{time_zone_database: time_zone_database} = options

    with {:ok, iso_datetime} <- NaiveDateTime.convert(datetime, Calendar.ISO),
         {:ok, time_zone} <- Time.timezone_at(location),
         {:ok, utc_datetime} <- DateTime.from_naive(iso_datetime, time_zone, time_zone_database) do
      sun_rise_or_set(location, utc_datetime, options)
    end
  end

  @doc false
  def sun_rise_or_set(%Geo.PointZ{} = location, %DateTime{} = datetime, options) do
    with {:ok, iso_datetime} <-
           DateTime.convert(datetime, Calendar.ISO),
         {:ok, adjusted_datetime} <-
           Time.antimeridian_adjustment(location, iso_datetime, options),
         {:ok, moment_of_rise_or_set} <-
           utc_sun_rise_or_set(adjusted_datetime, location, options),
         {:ok, utc_rise_or_set} <-
           Time.moment_to_datetime(moment_of_rise_or_set, adjusted_datetime),
         {:ok, adjusted_rise_or_set} <-
           Time.adjust_for_wraparound(utc_rise_or_set, location, options),
         {:ok, local_rise_or_set} <-
           Time.datetime_in_requested_zone(adjusted_rise_or_set, location, options) do
      DateTime.convert(local_rise_or_set, datetime.calendar)
    end
  end

  @doc false
  def sun_rise_or_set(location, datetime, options) do
    Utils.normalize_location(location)
    |> sun_rise_or_set(datetime, options)
  end

  defp utc_sun_rise_or_set(utc_datetime, location, %{rise_or_set: :rise} = options) do
    utc_sunrise(utc_datetime, location, options)
  end

  defp utc_sun_rise_or_set(utc_datetime, location, %{rise_or_set: :set} = options) do
    utc_sunset(utc_datetime, location, options)
  end

  defp utc_sunrise(date, %Geo.PointZ{} = geo_location, options) do
    solar_elevation =
      options
      |> Map.fetch!(:solar_elevation)
      |> solar_elevation()

    utc_sun_position(date, geo_location, solar_elevation, :sunrise)
  end

  defp utc_sunset(date, %Geo.PointZ{} = geo_location, options) do
    solar_elevation =
      options
      |> Map.fetch!(:solar_elevation)
      |> solar_elevation()

    utc_sun_position(date, geo_location, solar_elevation, :sunset)
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
  Returns the UTC time of sun's position
  for a given location as a float time-of-day.

  ## Arguments

  * `date` is a `DateTime.t()` in the UTC
    time zone

  * `location` is any `GeoPointZ.t()`
    location

  * `solar_elevation` is the required solar
    elevation in degrees (90 degrees for sunrise
    and sunset)

  * `mode` is `:sunrise` or `:sunset`

  ## Returns

  * `{:ok, moment}` where `moment` is float
    representing the number of hours after
    midnight for sunrise or sunset or

  * `{:error, :no_time}` if there is no
    sunrise/sunset for the given date at the
    given location. This can occur for very
    high latitudes in winter and summer.

  ## Notes

  This implementation is based on equations from
  [Astronomical Algorithms](https://www.amazon.com/astronomical-algorithms-jean-meeus/dp/0943396611),
  by Jean Meeus. The sunrise and sunset results are
  theoretically accurate to within a minute for
  locations between +/- 72° latitude, and within
  10 minutes outside of those latitudes. However, due to
  variations in atmospheric composition, temperature,
  pressure and conditions, observed values may vary from
  calculations.

  """
  @spec utc_sun_position(DateTime.t(), GeoPointZ.t(), float(), :sunrise | :sunset) ::
    {:ok, float} | {:error, :no_time}

  def utc_sun_position(date, %Geo.PointZ{coordinates: {lng, lat, alt}}, solar_elevation, mode) do
    adjusted_solar_elevation = Earth.adjusted_solar_elevation(solar_elevation, alt)

    with {:ok, utc_time_in_minutes} <-
           calculate_utc_sun_position(Time.ajd(date), lat, -lng, adjusted_solar_elevation, mode) do
      {:ok, Utils.mod(utc_time_in_minutes / 60.0, 24.0)}
    end
  end

  defp calculate_utc_sun_position(julian_day, latitude, longitude, solar_elevation, mode) do
    julian_centuries = Time.julian_centuries_from_julian_day(julian_day)

    # first pass using solar noon
    noonmin = solar_noon_utc(julian_centuries, longitude)
    tnoon = Time.julian_centuries_from_julian_day(julian_day + noonmin / 1440.0)
    first_pass = approximate_utc_sun_position(tnoon, latitude, longitude, solar_elevation, mode)

    # refine using output of first pass
    trefinement = Time.julian_centuries_from_julian_day(julian_day + first_pass / 1440.0)

    position =
      approximate_utc_sun_position(trefinement, latitude, longitude, solar_elevation, mode)

    {:ok, position}
  rescue
    ArithmeticError ->
      {:error, :no_time}
  end

  defp approximate_utc_sun_position(
        approx_julian_centuries,
        latitude,
        longitude,
        solar_elevation,
        mode
      ) do
    eq_time = equation_of_time(approx_julian_centuries)
    solar_dec = solar_declination(approx_julian_centuries)
    hour_angle = sun_hour_angle_at_horizon(latitude, solar_dec, solar_elevation, mode)

    delta = longitude - Utils.to_degrees(hour_angle)
    time_delta = delta * 4.0
    720.0 + time_delta - eq_time
  end

  defp sun_hour_angle_at_horizon(latitude, solar_dec, solar_elevation, mode) do
    lat_r = Utils.to_radians(latitude)
    solar_dec_r = Utils.to_radians(solar_dec)
    solar_elevation_r = Utils.to_radians(solar_elevation)

    hour_angle =
      :math.acos(
        :math.cos(solar_elevation_r) / (:math.cos(lat_r) * :math.cos(solar_dec_r)) -
          :math.tan(lat_r) * :math.tan(solar_dec_r)
      )

    if mode == :sunset do
      -hour_angle
    else
      hour_angle
    end
  end

  @doc """
  Returns the solar declination in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * the solar declination in degrees as
    a `float`

  ## Notes

  The solar declination is the angle between
  the direction of the center of the solar
  disk measured from Earth's center and the
  equatorial plane

  """
  def solar_declination(julian_centuries) do
    correction = obliquity_correction(julian_centuries) |> Utils.to_radians()
    lambda = sun_apparent_longitude(julian_centuries) |> Utils.to_radians()
    sint = :math.sin(correction) * :math.sin(lambda)

    sint
    |> :math.asin()
    |> Utils.to_degrees()
  end

  @doc """
  Returns the suns apparent longitude in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * equation of the center in degrees
    as a `float`

  ## Notes

  The apparent longitude is the sun's celestial
  longitude corrected for aberration and nutation
  as opposed to mean longitude

  """
  def sun_apparent_longitude(julian_centuries) do
    true_longitude = sun_true_longitude(julian_centuries)
    omega = 125.04 - 1934.136 * julian_centuries
    true_longitude - 0.00569 - 0.00478 * :math.sin(Utils.to_radians(omega))
  end

  @doc """
  Returns the suns true longitude in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * the suns true longitude in degrees
    as a `float`

  ## Notes

  In celestial mechanics true longitude is the
  ecliptic longitude at which an orbiting body
  could actually be found if its inclination
  were zero.

  Together with the inclination and the ascending
  node, the true longitude can tell us the precise
  direction from the central object at which the
  body would be located at a particular time.

  """
  def sun_true_longitude(julian_centuries) do
    sun_geometric_mean_longitude(julian_centuries) + sun_equation_of_center(julian_centuries)
  end

  @doc """
  Return the sun's equation of the center in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * equation of the center in degrees
    as a `float`

  ## Notes

  In two-body, Keplerian orbital mechanics, the equation
  of the center is the angular difference between the
  actual position of a body in its elliptical orbit and
  the position it would occupy if its motion were uniform,
  in a circular orbit of the same period.

  It is defined as the difference true anomaly, ν,
  minus mean anomaly, M, and is typically expressed a
  function of mean anomaly, M, and orbital eccentricity, e.

  """
  def sun_equation_of_center(julian_centuries) do
    mrad = sun_geometric_mean_anomaly(julian_centuries) |> Utils.to_radians()
    sinm = :math.sin(mrad)
    sin2m = :math.sin(2 * mrad)
    sin3m = :math.sin(3 * mrad)

    sinm * (1.914602 - julian_centuries * (0.004817 + 0.000014 * julian_centuries)) +
      sin2m * (0.019993 - 0.000101 * julian_centuries) +
      sin3m * 0.000289
  end

  def solar_noon_utc(julian_centuries, longitude) do
    century_start = Time.julian_day_from_julian_centuries(julian_centuries)

    # first pass to yield approximate solar noon
    approx_tnoon = Time.julian_centuries_from_julian_day(century_start + longitude / 360.0)
    approx_eq_time = equation_of_time(approx_tnoon)
    approx_sol_noon = 720.0 + longitude * 4.0 - approx_eq_time

    # refinement using output of first pass
    tnoon = Time.julian_centuries_from_julian_day(century_start - 0.5 + approx_sol_noon / 1440.0)
    eq_time = equation_of_time(tnoon)
    720.0 + longitude * 4.0 - eq_time
  end

  @doc """
  Returns the euation of time in minutes

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * The discrepency between apparent time and
    mean solar time in minutes as a `float`.

  ## Notes

  The equation of time describes the discrepancy between
  two kinds of solar time. The word equation is used in
  the medieval sense of "reconcile a difference". The two
  times that differ are the apparent solar time, which
  directly tracks the diurnal motion of the Sun, and mean
  solar time, which tracks a theoretical mean Sun with uniform
  motion. Apparent solar time can be obtained by measurement
  of the current position (hour angle) of the Sun, as
  indicated (with limited accuracy) by a sundial. Mean solar
  time, for the same place, would be the time indicated by a steady
  clock set so that over the year its differences from apparent
  solar time would have a mean of zero.

  During a year the equation of time varies as shown on the
  graph; its change from one year to the next is slight.
  Apparent time, and the sundial, can be ahead (fast) by as
  much as 16 min 33 s (around 3 November), or behind (slow) by
  as much as 14 min 6 s (around 11 February). The equation of
  time has zeros near 15 April, 13 June, 1 September, and
  25 December. Ignoring very slow changes in the Earth's
  orbit and rotation, these events are repeated at the same
  times every tropical year. However, due to the non-integral
  number of days in a year, these dates can vary by a day or
  so from year to year.

  The graph of the equation of time is closely approximated by
  the sum of two sine curves, one with a period of a year and
  one with a period of half a year. The curves reflect two
  astronomical effects, each causing a different non-uniformity
  in the apparent daily motion of the Sun relative to the stars:

  * the obliquity of the ecliptic (the plane of the Earth's annual
    orbital motion around the Sun), which is inclined by about 23.44
    degrees relative to the plane of the Earth's equator; and

  * the eccentricity of the Earth's orbit around the Sun, which is
    about 0.0167.

  The equation of time is constant only for a planet with zero axial
  tilt and zero orbital eccentricity. On Mars the difference between
  sundial time and clock time can be as much as 50 minutes, due to
  the considerably greater eccentricity of its orbit. The planet
  Uranus, which has an extremely large axial tilt, has an equation
  of time that makes its days start and finish several hours earlier
  or later depending on where it is in its orbit.

  """
  def equation_of_time(julian_centuries) when is_float(julian_centuries) do
    epsilon = obliquity_correction(julian_centuries) |> Utils.to_radians()
    sgml = sun_geometric_mean_longitude(julian_centuries) |> Utils.to_radians()
    sgma = sun_geometric_mean_anomaly(julian_centuries) |> Utils.to_radians()
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

    Utils.to_degrees(eq_time) * 4.0
  end

  @doc """
  Returns the unitness earth orbit eccentricity

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * a unitless value of eccentricity as a `float`.
    A value of `0` is a circular orbit, values
    between `0` and `1` form an elliptic orbit,
    `1` is a parabolic escape orbit, and greater
    than `1` is a hyperbola

  ## Notes

  The orbital eccentricity of earth - and any astronomical
  object - is a dimensionless parameter that determines
  the amount by which its orbit around another body
  deviates from a perfect circle. The term derives
  its name from the parameters of conic sections, as
  every Kepler orbit is a conic section.

  """
  def earth_orbit_eccentricity(julian_centuries) do
    0.016708634 - julian_centuries * (0.000042037 + 0.0000001267 * julian_centuries)
  end

  @doc """
  Returns the suns geometric mean anomoly in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * the mean anomoly in degrees as a `float`

  ## Notes

  In celestial mechanics, the mean anomaly is the
  fraction of an elliptical orbit's period that has
  elapsed since the orbiting body passed periapsis,
  expressed as an angle which can be used in calculating
  the position of that body in the classical two-body
  problem.

  It is the angular distance from the pericenter
  which a fictitious body would have if it moved
  in a circular orbit, with constant speed, in the same
  orbital period as the actual body in its elliptical orbit

  """
  def sun_geometric_mean_anomaly(julian_centuries) do
    anomaly = 357.52911 + julian_centuries * (35999.05029 - 0.0001537 * julian_centuries)
    Utils.mod(anomaly, 360.0)
  end

  @doc """
  Returns the suns geometric mean longitude in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * the mean solar longitude in degrees as a float

  ## Notes

  Mean longitude, like mean anomaly, does not measure
  an angle between any physical objects. It is simply
  a convenient uniform measure of how far around its orbit
  a body has progressed since passing the reference
  direction. While mean longitude measures a mean position
  and assumes constant speed, true longitude measures the
  actual longitude and assumes the body has moved with its
  actual speed, which varies around its elliptical orbit.

  The difference between the two is known as the equation
  of the center.

  """
  def sun_geometric_mean_longitude(julian_centuries) do
    longitude = 280.46646 + julian_centuries * (36000.76983 + 0.0003032 * julian_centuries)
    Utils.mod(longitude, 360.0)
  end

  @doc """
  Returns the obliquity correction in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * the obliquity correction in
    degrees as a `float`

  """
  def obliquity_correction(julian_centuries) do
    obliquity_of_ecliptic = mean_obliquity_of_ecliptic(julian_centuries)

    omega = 125.04 - 1934.136 * julian_centuries
    correction = obliquity_of_ecliptic + 0.00256 * :math.cos(Utils.to_radians(omega))
    Utils.mod(correction, 360.0)
  end

  @doc """
  Returns the mean obliquity of the ecliptic in degrees

  ## Arguments

  * `julian_centuries` is the any moment
    in time expressed as julian centuries

  ## Returns

  * the mean obliquity of the ecliptic in
    degrees as a `float`

  ## Notes

  Obliquity, also known as tilt, is the angle between
  the rotation access of the earth from the orbital
  plane of the earth around the sun.

  Earth's obliquity angle is measured from the imaginary
  line that runs perpendicular to another imaginary line;
  Earth's ecliptic plane or orbital plane
  .
  At the moment, Earth's obliquity is about 23.4 degrees
  and decreasing. We say 'at the moment' because the
  obliquity changes over time, although very, very slowly.

  """
  def mean_obliquity_of_ecliptic(julian_centuries) do
    seconds =
      21.448 -
        julian_centuries * (46.8150 + julian_centuries * (0.00059 - julian_centuries * 0.001813))

    # in degrees
    23.0 + (26.0 + seconds / 60.0) / 60.0
  end
end
