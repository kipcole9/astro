defmodule Astro.Ephemeris do
  @moduledoc """
  Computes the geocentric position of the Moon using a JPL DE440s (or
  compatible) SPK binary ephemeris kernel.

  The SPK file provides positions in ICRF/J2000 Cartesian coordinates (km).
  This module chains the available segments to produce the Moon's position
  relative to the Earth's centre, then applies IAU 1980 precession and
  nutation to yield apparent geocentric RA, Dec, and distance in the true
  equator and equinox of date.

  ## Segment chaining (DE440s)

  `de440s.bsp` supplies:
    - Body 301 (Moon) relative to body 3 (Earth-Moon Barycenter, EMB)
    - Body 399 (Earth) relative to body 3 (EMB)

  Moon relative to Earth = Moon/EMB − Earth/EMB.

  ## Setup

  Load the kernel once at application startup and pass it to all calls:

      {:ok, kernel} = Astro.Ephemeris.Kernel.load("priv/de440s.bsp")
      {:ok, {ra, dec, dist}} = Astro.Ephemeris.moon_position(kernel, utc_dt)

  ## Accuracy

  Position accuracy is limited by the ephemeris itself: DE440 achieves
  sub-centimetre accuracy for the Moon relative to current-epoch laser
  ranging data. The dominant remaining error sources for rise/set timing are:
  - Atmospheric refraction model (~1 arcmin, ~2 s of time near horizon)
  - Topocentric correction residuals at high solar-altitude latitudes

  This represents a 10–100× improvement over the truncated Chapront series
  used by in Meeus.
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
  Computes the apparent geocentric position of the Moon for the given UTC
  datetime.

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}` in the true equator and
  equinox of date (mean equinox with nutation applied), or `{:error, reason}`.

  `ra_deg` is in [0, 360), `dec_deg` in [-90, 90].
  """
  @doc since: "2.0.0"
  @spec moon_position(DateTime.t()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}

  def moon_position(%DateTime{} = utc_date_time) do
    utc_date_time
    |> Astro.Time.date_time_to_moment()
    |> Astro.Time.dynamical_time_from_moment()
    |> moon_position_dt()
  end

  @doc """
  Computes the apparent geocentric position of the Moon for the given
  dynamical time (TDB seconds past J2000.0).

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}`.
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
  Computes the apparent geocentric position of the Sun for the given UTC
  datetime.

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}` in the true equator and
  equinox of date, or `{:error, reason}`.

  ## Segment chaining (DE440s)

  `de440s.bsp` supplies:
    - Body 10 (Sun) relative to body 0 (Solar System Barycenter, SSB)
    - Body 3  (EMB) relative to body 0 (SSB)
    - Body 399 (Earth) relative to body 3 (EMB)

  Sun relative to Earth = Sun/SSB − EMB/SSB + Earth/EMB.
  """
  @spec sun_position(DateTime.t()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position(%DateTime{} = utc_date_time) do
    dynamical_time =
      utc_date_time
      |> Astro.Time.date_time_to_moment()
      |> Astro.Time.dynamical_time_from_moment()

    sun_position_dt(dynamical_time)
  end

  @doc """
  Computes the apparent geocentric position of the Sun for the given
  dynamical time (TDB seconds past J2000.0).

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}`.
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
  Returns the equatorial horizontal parallax (degrees) for the given
  geocentric distance in km.

  π = asin(R_earth / distance)
  where R_earth = 6378.137 km (WGS-84 equatorial radius).
  """
  @spec equatorial_horizontal_parallax(float()) :: float()
  def equatorial_horizontal_parallax(distance_km) do
    # WGS-84 equatorial radius
    r_earth_km = 6378.137
    :math.asin(r_earth_km / distance_km) * 180.0 / :math.pi()
  end
end
