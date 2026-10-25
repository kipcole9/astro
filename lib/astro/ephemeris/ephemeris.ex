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

  alias Astro.Coordinates
  alias Astro.Ephemeris.Kernel

  # NAIF body IDs
  @moon_id 301
  @earth_id 399
  @emb_id 3
  @sun_id 10
  @ssb_id 0

  # Light time is only needed to about 1% for a sub-milliarcsecond
  # position, so it is estimated rather than taken from a second
  # ephemeris evaluation. The Moon's varies by ±7% about its mean,
  # which moves the Moon by under 0.05″.
  @moon_light_time_s 1.282
  @au_light_time_s 499.004784
  @seconds_per_day 86_400.0

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
      {262.932, -28.0416, 382267}

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
      {222.4436, -10.8979, 402449}

  """
  @spec moon_position_dt(float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_position_dt(dynamical_time) do
    with {:ok, geo} <- moon_geocentric_cartesian(dynamical_time - @moon_light_time_s) do
      apparent = Coordinates.icrf_to_true_equator(geo, dynamical_time)
      {:ok, Coordinates.cartesian_to_spherical(apparent)}
    end
  end

  @doc """
  Computes the apparent geocentric position of the Sun for the given
  datetime.

  Chains the Sun/SSB, EMB/SSB and Earth/EMB segments from the loaded
  JPL ephemeris (Sun/SSB − EMB/SSB − Earth/EMB), corrects for light
  time and aberration, then applies IAU 1980 precession and nutation.

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
      {90.6564, 23.4368, 152026542}

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
      {281.2776, -23.0325, 147103733}

  """
  @spec sun_position_dt(float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position_dt(dynamical_time) do
    with {:ok, geo} <- sun_geocentric_cartesian(dynamical_time - sun_light_time(dynamical_time)) do
      apparent = Coordinates.icrf_to_true_equator(geo, dynamical_time)
      {:ok, Coordinates.cartesian_to_spherical(apparent)}
    end
  end

  # ── Ecliptic position functions ───────────────────────────────────────────────

  @doc """
  Computes the apparent geocentric ecliptic position of the Sun for the
  given dynamical time.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{:ok, {longitude_deg, latitude_deg, distance_km}}` where longitude
    is in degrees in the range [0, 360) and latitude is in degrees
    in the range [-90, 90].

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> {:ok, {longitude, latitude, distance}} = Astro.Ephemeris.sun_ecliptic_position_dt(0.0)
      iex> {Float.round(longitude, 4), Float.round(latitude, 6), round(distance)}
      {280.3682, 2.38e-4, 147103733}

  """
  @spec sun_ecliptic_position_dt(float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_ecliptic_position_dt(dynamical_time) do
    with {:ok, geo} <- sun_geocentric_cartesian(dynamical_time - sun_light_time(dynamical_time)) do
      nutation = nutation_at(dynamical_time)
      apparent = Coordinates.icrf_to_true_equator(geo, dynamical_time, nutation)
      ecliptic = Coordinates.true_equator_to_ecliptic(apparent, dynamical_time, nutation)
      {:ok, Coordinates.cartesian_to_ecliptic_spherical(ecliptic)}
    end
  end

  @doc """
  Computes the apparent geocentric ecliptic position of the Sun for the
  given moment.

  ### Arguments

  * `moment` is a moment (fractional days since epoch).

  ### Returns

  * `{:ok, {longitude_deg, latitude_deg, distance_km}}`.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~U[2024-06-21 12:00:00Z])
      iex> {:ok, {longitude, latitude, distance}} = Astro.Ephemeris.sun_ecliptic_position(moment)
      iex> {Float.round(longitude, 4), Float.round(latitude, 4), round(distance)}
      {90.6022, -0.0002, 152026542}

  """
  @spec sun_ecliptic_position(Astro.Time.moment()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_ecliptic_position(moment) do
    moment
    |> Astro.Time.dynamical_time_from_moment()
    |> sun_ecliptic_position_dt()
  end

  @doc """
  Computes the apparent geocentric ecliptic position of the Moon for the
  given dynamical time.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{:ok, {longitude_deg, latitude_deg, distance_km}}` where longitude
    is in degrees in the range [0, 360) and latitude is in degrees
    in the range [-90, 90].

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> {:ok, {longitude, latitude, distance}} = Astro.Ephemeris.moon_ecliptic_position_dt(0.0)
      iex> {Float.round(longitude, 4), Float.round(latitude, 4), round(distance)}
      {223.3149, 5.1709, 402449}

  """
  @spec moon_ecliptic_position_dt(float()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_ecliptic_position_dt(dynamical_time) do
    with {:ok, geo} <- moon_geocentric_cartesian(dynamical_time - @moon_light_time_s) do
      nutation = nutation_at(dynamical_time)
      apparent = Coordinates.icrf_to_true_equator(geo, dynamical_time, nutation)
      ecliptic = Coordinates.true_equator_to_ecliptic(apparent, dynamical_time, nutation)
      {:ok, Coordinates.cartesian_to_ecliptic_spherical(ecliptic)}
    end
  end

  @doc """
  Computes the apparent geocentric ecliptic position of the Moon for the
  given moment.

  ### Arguments

  * `moment` is a moment (fractional days since epoch).

  ### Returns

  * `{:ok, {longitude_deg, latitude_deg, distance_km}}`.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~U[2024-06-21 12:00:00Z])
      iex> {:ok, {longitude, latitude, distance}} = Astro.Ephemeris.moon_ecliptic_position(moment)
      iex> {Float.round(longitude, 4), Float.round(latitude, 4), round(distance)}
      {263.7436, -4.7566, 382267}

  """
  @spec moon_ecliptic_position(Astro.Time.moment()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_ecliptic_position(moment) do
    moment
    |> Astro.Time.dynamical_time_from_moment()
    |> moon_ecliptic_position_dt()
  end

  # ── Moment-based equatorial wrappers ────────────────────────────────────────

  @doc """
  Computes the apparent geocentric equatorial position of the Sun for
  the given moment.

  ### Arguments

  * `moment` is a moment (fractional days since epoch).

  ### Returns

  * `{:ok, {ra_deg, dec_deg, distance_km}}`.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~U[2024-06-21 12:00:00Z])
      iex> {:ok, {right_ascension, declination, distance}} = Astro.Ephemeris.sun_position_from_moment(moment)
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {90.6564, 23.4368, 152026542}

  """
  @spec sun_position_from_moment(Astro.Time.moment()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def sun_position_from_moment(moment) do
    moment
    |> Astro.Time.dynamical_time_from_moment()
    |> sun_position_dt()
  end

  @doc """
  Computes the apparent geocentric equatorial position of the Moon for
  the given moment.

  ### Arguments

  * `moment` is a moment (fractional days since epoch).

  ### Returns

  * `{:ok, {ra_deg, dec_deg, distance_km}}`.

  * `{:error, reason}` if a required ephemeris segment is not found.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~U[2024-06-21 12:00:00Z])
      iex> {:ok, {right_ascension, declination, distance}} = Astro.Ephemeris.moon_position_from_moment(moment)
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {262.932, -28.0416, 382267}

  """
  @spec moon_position_from_moment(Astro.Time.moment()) ::
          {:ok, {float(), float(), float()}} | {:error, term()}
  def moon_position_from_moment(moment) do
    moment
    |> Astro.Time.dynamical_time_from_moment()
    |> moon_position_dt()
  end

  # ── Coverage ────────────────────────────────────────────────────────────────

  @doc """
  Checks that the loaded ephemeris covers the Sun and the Moon over a
  span of moments.

  The loaded ephemeris covers one continuous span of years, so a span
  is covered when both of its ends are.

  ### Arguments

  * `from` is the first moment (fractional days since epoch) of the span.

  * `to` is the last moment of the span. The default is `from`, which
    checks a single moment.

  ### Returns

  * `:ok` if the ephemeris covers the whole span.

  * `{:error, :not_found}` if either end lies outside the ephemeris.

  ### Examples

      iex> Astro.Ephemeris.check_coverage(Astro.Time.date_time_to_moment(~D[2024-06-21]))
      :ok

      iex> Astro.Ephemeris.check_coverage(Astro.Time.date_time_to_moment(~D[1000-01-01]))
      {:error, :not_found}

  """
  @doc since: "2.8.0"
  @spec check_coverage(Astro.Time.moment(), Astro.Time.moment() | nil) ::
          :ok | {:error, :not_found}
  def check_coverage(from, to \\ nil) do
    with :ok <- covered(from) do
      covered(to || from)
    end
  end

  # A moment is covered when the segments the Sun's and the Moon's
  # positions read are found, at the times they read them: the same
  # lookups `sun_position_dt/1` and `moon_position_dt/1` make, without
  # evaluating a position, which took two full apparent positions (about
  # 23 µs) a moment.
  defp covered(moment) do
    dynamical_time = Astro.Time.dynamical_time_from_moment(moment)

    with {:ok, _sun} <- sun_segments(dynamical_time - sun_light_time(dynamical_time)),
         {:ok, _moon} <- moon_segments(dynamical_time - @moon_light_time_s) do
      :ok
    end
  end

  # ── Parallax ────────────────────────────────────────────────────────────────

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
    r_earth_km = 6378.137
    :math.asin(r_earth_km / distance_km) * 180.0 / :math.pi()
  end

  # ── Private geocentric Cartesian helpers ────────────────────────────────────

  # Light time plus annual aberration is, to first order, the geometric
  # geocentric vector evaluated one light-time earlier. The Earth-Sun
  # distance comes from the almanac series in the mean anomaly, good to
  # 1e-4 AU, which is 0.05 s of light time.
  defp sun_light_time(dynamical_time) do
    mean_anomaly = (357.529 + 0.98560028 * dynamical_time / @seconds_per_day) * :math.pi() / 180.0

    distance_au =
      1.00014 - 0.01671 * :math.cos(mean_anomaly) - 0.00014 * :math.cos(2.0 * mean_anomaly)

    distance_au * @au_light_time_s
  end

  defp moon_geocentric_cartesian(dynamical_time) do
    with {:ok, {seg_moon, seg_earth}} <- moon_segments(dynamical_time) do
      {mx, my, mz} = Kernel.position(seg_moon, dynamical_time)
      {ex, ey, ez} = Kernel.position(seg_earth, dynamical_time)
      {:ok, {mx - ex, my - ey, mz - ez}}
    end
  end

  defp sun_geocentric_cartesian(dynamical_time) do
    with {:ok, {seg_sun, seg_emb, seg_earth}} <- sun_segments(dynamical_time) do
      {sx, sy, sz} = Kernel.position(seg_sun, dynamical_time)
      {bx, by, bz} = Kernel.position(seg_emb, dynamical_time)
      {ex, ey, ez} = Kernel.position(seg_earth, dynamical_time)
      {:ok, {sx - bx - ex, sy - by - ey, sz - bz - ez}}
    end
  end

  # The nutation at a dynamical time, found once for both rotations an
  # ecliptic position makes: to the true equator, and on to the ecliptic.
  defp nutation_at(dynamical_time) do
    dynamical_time |> Coordinates.julian_centuries_from_dynamical_time() |> Astro.Earth.nutation()
  end

  # The segments the Moon's and the Sun's geocentric positions are chained
  # from, found at the time they are read. A position and the coverage of a
  # moment both ask here, so they cannot disagree on what is covered.
  defp moon_segments(dynamical_time) do
    with {:ok, seg_moon} <- Kernel.find_segment(@moon_id, @emb_id, dynamical_time),
         {:ok, seg_earth} <- Kernel.find_segment(@earth_id, @emb_id, dynamical_time) do
      {:ok, {seg_moon, seg_earth}}
    end
  end

  defp sun_segments(dynamical_time) do
    with {:ok, seg_sun} <- Kernel.find_segment(@sun_id, @ssb_id, dynamical_time),
         {:ok, seg_emb} <- Kernel.find_segment(@emb_id, @ssb_id, dynamical_time),
         {:ok, seg_earth} <- Kernel.find_segment(@earth_id, @emb_id, dynamical_time) do
      {:ok, {seg_sun, seg_emb, seg_earth}}
    end
  end
end
