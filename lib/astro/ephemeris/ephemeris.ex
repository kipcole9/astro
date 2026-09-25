defmodule Astro.Ephemeris do
  @moduledoc """
  Computes the apparent geocentric positions of the Moon and the Sun from a
  JPL DE440s (or compatible) SPK binary ephemeris kernel.

  The SPK file provides positions in ICRF/J2000 Cartesian coordinates (km).
  This module chains the available segments to produce each body's position
  relative to the Earth's centre, then applies IAU 1980 precession and
  nutation to yield apparent geocentric right ascension, declination and
  distance in the true equator and equinox of date.

  ## Segment chaining (DE440s)

  `de440s.bsp` supplies, among others:

  * body 301, the Moon, relative to body 3, the Earth-Moon barycentre (EMB).

  * body 399, the Earth, relative to body 3.

  The Moon relative to the Earth is then Moon/EMB − Earth/EMB.

  The compact ephemeris bundled with the library omits body 399, which
  `Astro.Ephemeris.Kernel` reconstructs from body 301 — the two are exact
  scalar multiples of one another. Chaining is unaffected.

  ## Setup

  The kernel is loaded when the application starts, from the path that
  `Astro.Ephemeris.Downloader.ephemeris_path/0` resolves, and the position
  functions read it from there:

      {:ok, {right_ascension, declination, distance}} =
        Astro.Ephemeris.moon_position(~U[2024-06-21 12:00:00Z])

  ## Accuracy

  Position accuracy is limited by the ephemeris itself: DE440 achieves
  sub-centimetre accuracy for the Moon relative to current-epoch laser
  ranging data. The dominant remaining error sources for rise and set timing
  are:

  * the atmospheric refraction model, about 1 arcminute or 2 seconds of time
    near the horizon.

  * topocentric correction residuals at high solar-altitude latitudes.

  This is a 10–100× improvement over the truncated Chapront series used in
  Meeus that was the core of the Astro 1.x library.

  """

  alias Astro.Ephemeris.Kernel
  alias Astro.Coordinates

  # NAIF body IDs
  @moon_id 301
  @earth_id 399
  @emb_id 3
  @sun_id 10
  @ssb_id 0

  @doc """
  Computes the apparent geocentric position of the Moon for the given
  datetime.

  Chains the Moon/EMB and Earth/EMB segments from the loaded JPL
  ephemeris, then applies IAU 1980 precession and nutation to
  produce coordinates in the true equator and equinox of date.

  ### Arguments

  * `date_time` is a `DateTime` in any time zone (converted
    internally to a moment and then to dynamical time).

  ### Returns

  * `{:ok, {ra_deg, dec_deg, distance_km}}` where right ascension
    is in degrees in the range [0, 360), declination is in degrees
    in the range [-90, 90], and distance is in kilometers.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> {:ok, {right_ascension, declination, distance}} =
      ...>   Astro.Ephemeris.moon_position(~U[2024-06-21 12:00:00Z])
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {262.9343, -28.0371, 382267}

  """
  @doc since: "2.0.0"
  @spec moon_position(DateTime.t()) ::
          {:ok, {right_ascension :: Astro.angle(), float(), float()}} | {:error, term()}

  def moon_position(%DateTime{} = date_time) do
    date_time
    |> Astro.Time.date_time_to_moment()
    |> Astro.Time.dynamical_time_from_moment()
    |> moon_position_dt()
  end

  @doc """
  Computes the apparent geocentric position of the Moon for the given
  dynamical time.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{:ok, {ra_deg, dec_deg, distance_km}}` where right ascension
    is in degrees in the range [0, 360), declination is in degrees
    in the range [-90, 90], and distance is in kilometers.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> {:ok, {right_ascension, declination, distance}} = Astro.Ephemeris.moon_position_dt(0.0)
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {222.4504, -10.9001, 402449}

  """
  @spec moon_position_dt(float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_position_dt(dynamical_time) do
    with {:ok, seg_moon} <- Kernel.find_segment(@moon_id, @emb_id, dynamical_time),
         {:ok, seg_earth} <- Kernel.find_segment(@earth_id, @emb_id, dynamical_time) do
      {mx, my, mz} = Kernel.position(seg_moon, dynamical_time)
      {ex, ey, ez} = Kernel.position(seg_earth, dynamical_time)

      # Moon relative to Earth (geocentric), ICRF/J2000 Cartesian (km)
      geo = {mx - ex, my - ey, mz - ez}

      # Rotate to true equator and equinox of date (precession + nutation)
      apparent = Coordinates.icrf_to_true_equator(geo, dynamical_time)

      # Convert to spherical coordinates
      {ra, dec, dist} = Coordinates.cartesian_to_spherical(apparent)
      {:ok, {ra, dec, dist}}
    end
  end

  @doc """
  Computes the apparent geocentric position of the Sun for the given
  datetime.

  Chains the Sun/SSB, EMB/SSB and Earth/EMB segments from the loaded
  JPL ephemeris (Sun/SSB − EMB/SSB + Earth/EMB), then applies
  IAU 1980 precession and nutation.

  ### Arguments

  * `date_time` is a `DateTime` in any time zone.

  ### Returns

  * `{:ok, {ra_deg, dec_deg, distance_km}}` where right ascension
    is in degrees in the range [0, 360), declination is in degrees
    in the range [-90, 90], and distance is in kilometers.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> {:ok, {right_ascension, declination, distance}} =
      ...>   Astro.Ephemeris.sun_position(~U[2024-06-21 12:00:00Z])
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {90.6638, 23.4325, 152035789}

  """
  @spec sun_position(DateTime.t()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position(%DateTime{} = date_time) do
    dynamical_time =
      date_time
      |> Astro.Time.date_time_to_moment()
      |> Astro.Time.dynamical_time_from_moment()

    sun_position_dt(dynamical_time)
  end

  @doc """
  Computes the apparent geocentric position of the Sun for the given
  dynamical time.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{:ok, {ra_deg, dec_deg, distance_km}}` where right ascension
    is in degrees in the range [0, 360), declination is in degrees
    in the range [-90, 90], and distance is in kilometers.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> {:ok, {right_ascension, declination, distance}} = Astro.Ephemeris.sun_position_dt(0.0)
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {281.2947, -23.0353, 147098431}

  """
  @spec sun_position_dt(float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position_dt(dynamical_time) do
    with {:ok, seg_sun} <- Kernel.find_segment(@sun_id, @ssb_id, dynamical_time),
         {:ok, seg_emb} <- Kernel.find_segment(@emb_id, @ssb_id, dynamical_time),
         {:ok, seg_earth} <- Kernel.find_segment(@earth_id, @emb_id, dynamical_time) do
      {sx, sy, sz} = Kernel.position(seg_sun, dynamical_time)
      {bx, by, bz} = Kernel.position(seg_emb, dynamical_time)
      {ex, ey, ez} = Kernel.position(seg_earth, dynamical_time)

      # Sun relative to Earth (geocentric), ICRF/J2000 Cartesian (km):
      #   Sun/SSB − (EMB/SSB − Earth/EMB) = Sun/SSB − EMB/SSB + Earth/EMB
      geo = {sx - bx + ex, sy - by + ey, sz - bz + ez}

      apparent = Coordinates.icrf_to_true_equator(geo, dynamical_time)
      {ra, dec, dist} = Coordinates.cartesian_to_spherical(apparent)
      {:ok, {ra, dec, dist}}
    end
  end

  @doc """
  Returns the equatorial horizontal parallax for a given geocentric
  distance.

  Computed as `asin(R_earth / distance)` using the WGS-84
  equatorial radius of 6378.137 km.

  ### Arguments

  * `distance_km` is the geocentric distance in kilometers.

  ### Returns

  * The equatorial horizontal parallax in degrees.

  ### Examples

      iex> Astro.Ephemeris.equatorial_horizontal_parallax(384_400.0) |> Float.round(6)
      0.950721

  """
  @spec equatorial_horizontal_parallax(float()) :: float()
  def equatorial_horizontal_parallax(distance_km) do
    # WGS-84 equatorial radius
    r_earth_km = 6378.137
    :math.asin(r_earth_km / distance_km) * 180.0 / :math.pi()
  end
end
