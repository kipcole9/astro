defmodule Astro.Solar do
  @moduledoc """
  Imeplements sunrise and sunset according to the
  US NOAA algorithm

  """

  alias Astro.{Utils, Earth, Time}

  @utc_zone "Etc/UTC"

  def sun_rise_or_set(location, date, options) when is_list(options) do
    options =
      Astro.default_options()
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
    utc_sunrise(utc_datetime, location, options)
  end

  def utc_sun_rise_or_set(utc_datetime, location, %{rise_or_set: :set} = options) do
    utc_sunset(utc_datetime, location, options)
  end

  @solar_elevation %{
    geometric: 90.0,
    civil: 96.0,
    nautical: 102.0,
    astronomical: 108.0
  }
  @valid_solar_elevation Map.keys(@solar_elevation)

  def solar_elevation(solar_elevation) when solar_elevation in @valid_solar_elevation do
    Map.get(@solar_elevation, solar_elevation)
  end

  def solar_elevation(solar_elevation) when is_number(solar_elevation) do
    solar_elevation
  end

  def utc_sunrise(date, %Geo.PointZ{} = geo_location, options) do
    solar_elevation =
      options
      |> Map.fetch!(:solar_elevation)
      |> solar_elevation()

    utc_sun_position(date, geo_location, solar_elevation, :sunrise)
  end

  def utc_sunset(date, %Geo.PointZ{} = geo_location, options) do
    solar_elevation =
      options
      |> Map.fetch!(:solar_elevation)
      |> solar_elevation()

    utc_sun_position(date, geo_location, solar_elevation, :sunset)
  end

  def utc_sun_position(date, %Geo.PointZ{coordinates: {lng, lat, alt}}, solar_elevation, mode) do
    adjusted_solar_elevation = Earth.adjusted_solar_elevation(solar_elevation, alt)

    utc_time_in_minutes =
      calculate_utc_sun_position(Time.ajd(date), lat, -lng, adjusted_solar_elevation, mode)

    Utils.mod(utc_time_in_minutes / 60.0, 24.0)
  end

  def calculate_utc_sun_position(julian_day, latitude, longitude, solar_elevation, mode) do
    julian_centuries = Time.julian_centuries_from_julian_day(julian_day)

    # first pass using solar noon
    noonmin = solar_noon_utc(julian_centuries, longitude)
    tnoon = Time.julian_centuries_from_julian_day(julian_day + noonmin / 1440.0)
    first_pass = approximate_utc_sun_position(tnoon, latitude, longitude, solar_elevation, mode)

    # refine using output of first pass
    trefinement = Time.julian_centuries_from_julian_day(julian_day + first_pass / 1440.0)
    approximate_utc_sun_position(trefinement, latitude, longitude, solar_elevation, mode)
  end

  def approximate_utc_sun_position(
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

  @doc """
  Returns the hour angle in radians
  """
  def sun_hour_angle_at_horizon(latitude, solar_dec, solar_elevation, mode) do
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
  """
  def solar_declination(julian_centuries) do
    correction = obliquity_correction(julian_centuries) |> Utils.to_radians
    lambda = sun_apparent_longitude(julian_centuries) |> Utils.to_radians
    sint = :math.sin(correction) * :math.sin(lambda)

    sint
    |> :math.asin()
    |> Utils.to_degrees
  end

  @doc """
  Returns the suns apparent longitude in degrees
  """
  def sun_apparent_longitude(julian_centuries) do
    true_longitude = sun_true_longitude(julian_centuries)
    omega = 125.04 - 1934.136 * julian_centuries
    true_longitude - 0.00569 - 0.00478 * :math.sin(Utils.to_radians(omega))
  end

  @doc """
  Returns the suns true longitude in degrees
  """
  def sun_true_longitude(julian_centuries) do
    sun_geometric_mean_longitude(julian_centuries) + sun_equation_of_center(julian_centuries)
  end

  @doc """
  Return the suns equation of time in degrees
  """
  def sun_equation_of_center(julian_centuries) do
    mrad = sun_geometric_mean_anomaly(julian_centuries) |> Utils.to_radians
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
  """
  def equation_of_time(julian_centuries) do
    epsilon = obliquity_correction(julian_centuries) |> Utils.to_radians
    sgml = sun_geometric_mean_longitude(julian_centuries) |> Utils.to_radians
    sgma = sun_geometric_mean_anomaly(julian_centuries) |> Utils.to_radians
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
  """
  def earth_orbit_eccentricity(julian_centuries) do
    0.016708634 - julian_centuries * (0.000042037 + 0.0000001267 * julian_centuries)
  end

  @doc """
  Returns the suns geometric mean anomoly in degrees
  """
  def sun_geometric_mean_anomaly(julian_centuries) do
    anomaly = 357.52911 + julian_centuries * (35999.05029 - 0.0001537 * julian_centuries)
    Utils.mod(anomaly, 360.0)
  end

  @doc """
  Returns the suns geometric mean longitude in degrees
  """
  def sun_geometric_mean_longitude(julian_centuries) do
    longitude = 280.46646 + julian_centuries * (36000.76983 + 0.0003032 * julian_centuries)
    Utils.mod(longitude, 360.0)
  end

  @doc """
  Returns the obliquity correction in degrees
  """
  def obliquity_correction(julian_centuries) do
    obliquity_of_ecliptic = mean_obliquity_of_ecliptic(julian_centuries)

    omega = 125.04 - 1934.136 * julian_centuries
    correction = obliquity_of_ecliptic + 0.00256 * :math.cos(Utils.to_radians(omega))
    Utils.mod(correction, 360.0)
  end

  @doc """
  Returns the mean obliquity of the ecliptic in degrees
  """
  def mean_obliquity_of_ecliptic(julian_centuries) do
    seconds =
      21.448 -
        julian_centuries * (46.8150 + julian_centuries * (0.00059 - julian_centuries * 0.001813))

    # in degrees
    23.0 + (26.0 + seconds / 60.0) / 60.0
  end
end
