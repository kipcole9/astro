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

      {:ok, kernel} = Spk.Kernel.load("priv/de440s.bsp")
      {:ok, {ra, dec, dist}} = Jpl.Ephemeris.moon_position(kernel, utc_dt)

  ## Accuracy

  Position accuracy is limited by the ephemeris itself: DE440 achieves
  sub-centimetre accuracy for the Moon relative to current-epoch laser
  ranging data. The dominant remaining error sources for rise/set timing are:
  - Atmospheric refraction model (~1 arcmin, ~2 s of time near horizon)
  - Topocentric correction residuals at high solar-altitude latitudes

  This represents a 10–100× improvement over the truncated Chapront series
  used by the `astro` library.
  """

  alias Astro.Ephemeris.Kernel
  alias Astro.Coordinates

  # NAIF body IDs
  @moon_id  301
  @earth_id 399
  @emb_id     3
  @sun_id    10
  @ssb_id     0

  @doc """
  Computes the apparent geocentric position of the Moon for the given UTC
  datetime.

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}` in the true equator and
  equinox of date (mean equinox with nutation applied), or `{:error, reason}`.

  `ra_deg` is in [0, 360), `dec_deg` in [-90, 90].
  """
  @spec moon_position(Kernel.t(), DateTime.t()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_position(kernel, %DateTime{} = utc_dt) do
    et = Coordinates.utc_to_et(utc_dt)
    moon_position_et(kernel, et)
  end

  @doc """
  Computes the apparent geocentric position of the Moon for the given TDB
  epoch `et` (seconds past J2000.0).

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}`.
  """
  @spec moon_position_et(Kernel.t(), float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_position_et(kernel, et) do
    with {:ok, seg_moon}  <- Kernel.find_segment(kernel, @moon_id, @emb_id, et),
         {:ok, seg_earth} <- Kernel.find_segment(kernel, @earth_id, @emb_id, et) do
      {mx, my, mz} = Kernel.position(kernel, seg_moon,  et)
      {ex, ey, ez} = Kernel.position(kernel, seg_earth, et)

      # Moon relative to Earth (geocentric), ICRF/J2000 Cartesian (km)
      geo = {mx - ex, my - ey, mz - ez}

      # Rotate to true equator and equinox of date (precession + nutation)
      apparent = Coordinates.icrf_to_true_equator(geo, et)

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
  @spec sun_position(Kernel.t(), DateTime.t()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position(kernel, %DateTime{} = utc_dt) do
    et = Coordinates.utc_to_et(utc_dt)
    sun_position_et(kernel, et)
  end

  @doc """
  Computes the apparent geocentric position of the Sun for the given TDB
  epoch `et` (seconds past J2000.0).

  Returns `{:ok, {ra_deg, dec_deg, distance_km}}`.
  """
  @spec sun_position_et(Kernel.t(), float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position_et(kernel, et) do
    with {:ok, seg_sun}   <- Kernel.find_segment(kernel, @sun_id,   @ssb_id, et),
         {:ok, seg_emb}   <- Kernel.find_segment(kernel, @emb_id,   @ssb_id, et),
         {:ok, seg_earth} <- Kernel.find_segment(kernel, @earth_id, @emb_id, et) do
      {sx, sy, sz} = Kernel.position(kernel, seg_sun,   et)
      {bx, by, bz} = Kernel.position(kernel, seg_emb,   et)
      {ex, ey, ez} = Kernel.position(kernel, seg_earth, et)

      # Sun relative to Earth (geocentric), ICRF/J2000 Cartesian (km):
      #   Sun/SSB − (EMB/SSB − Earth/EMB) = Sun/SSB − EMB/SSB + Earth/EMB
      geo = {sx - bx + ex, sy - by + ey, sz - bz + ez}

      apparent = Coordinates.icrf_to_true_equator(geo, et)
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
