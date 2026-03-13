defmodule Astro.Coordinates do
  @moduledoc """
  Coordinate transformations for high-precision lunar and solar
  position calculations.

  Provides:
  - Conversion of UTC `DateTime` to TDB seconds past J2000.0 (the time
    argument used by JPL ephemerides).
  - Conversion of TDB seconds back to UTC `DateTime`.
  - Rotation of ICRF/J2000 Cartesian coordinates to the true equator and
    equinox of date using IAU 1980 precession and nutation.
  - Conversion of equatorial Cartesian to spherical (RA, Dec, distance).
  - Greenwich Apparent Sidereal Time (GAST) for the topocentric iteration.

  ## Time scale convention

  JPL ephemeris data is in TDB (Barycentric Dynamical Time). For the
  purpose of rise/set calculations, TDB ≈ TT to within 2 ms; this
  difference is negligible and TDB is treated as TT here.

  ΔT = TT − UTC varies over time; see `Astro.Time.delta_t/1` for the
  unified computation.

  ## Reference

  Precession: Lieske et al. (1977), A&A 58, 1–16.
  Nutation:   IAU 1980 series, Wahr (1981), Meeus Ch.22 (top 17 terms).
  GAST:       Meeus Ch.12 with equation of the equinoxes.

  """

  alias Astro.Earth

  # J2000.0 Julian date (TT): 2000-01-01 12:00:00 TT
  @jd_j2000 2_451_545.0

  # Seconds per day
  @seconds_per_day 86_400.0

  # Arcseconds per degree
  @arcsec_per_deg 3600.0

  # ── Time conversions ─────────────────────────────────────────────────────────

  @doc """
  Converts a moment to dynamical time (TDB seconds past J2000.0).

  Delegates to `Astro.Time.dynamical_time_from_moment/1`.

  ### Arguments

  * `moment` is a moment (fractional days since epoch).

  ### Returns

  * TDB seconds past J2000.0 as a float.

  """
  defdelegate dynamical_time_from_moment(moment), to: Astro.Time

  @doc """
  Converts dynamical time back to a moment.

  Delegates to `Astro.Time.dynamical_time_to_moment/1`.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * A moment (fractional days since epoch) as a float.

  """
  defdelegate dynamical_time_to_moment(dynamical_time), to: Astro.Time

  @doc """
  Returns Julian centuries from J2000.0 for the given dynamical time.

  Delegates to `Astro.Time.julian_centuries_from_dynamical_time/1`.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * Julian centuries from J2000.0 as a float.

  """
  defdelegate julian_centuries_from_dynamical_time(dynamical_time), to: Astro.Time

  # ── Precession and nutation (IAU 1980) ───────────────────────────────────────

  @doc """
  Rotates a J2000.0 ICRF Cartesian vector to the true equator
  and equinox of date, applying IAU 1980 precession and nutation.

  The precession matrix uses Lieske (1977) angles and the nutation
  uses the top 17 terms of the IAU 1980 series via `Astro.Earth.nutation/1`.

  ### Arguments

  * `{x, y, z}` is a Cartesian position vector in the ICRF/J2000
    frame, in any consistent unit (typically kilometers).

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{x', y', z'}` in the true equator and equinox of date frame,
    in the same units as the input.

  """
  @spec icrf_to_true_equator({float(), float(), float()}, float()) ::
          {float(), float(), float()}
  def icrf_to_true_equator({x, y, z}, dynamical_time) do
    t = julian_centuries_from_dynamical_time(dynamical_time)

    # Precession angles (Lieske 1977), arcseconds → radians
    zeta_a = arcsec_to_rad(2306.2181 * t + 1.39656 * t * t - 0.000139 * t * t * t)
    theta_a = arcsec_to_rad(2004.3109 * t - 0.85330 * t * t - 0.000217 * t * t * t)
    z_a = arcsec_to_rad(2306.2181 * t + 3.04480 * t * t + 0.000510 * t * t * t)

    # Precession matrix P (Meeus Ch.21) in standard math convention:
    # P = Rz(zA) · Ry(-θA) · Rz(ζA)
    {x1, y1, z1} = rot_z({x, y, z}, zeta_a)
    {x2, y2, z2} = rot_y({x1, y1, z1}, -theta_a)
    {x3, y3, z3} = rot_z({x2, y2, z2}, z_a)

    # Nutation
    {d_psi, d_eps, eps0} = Earth.nutation(t)
    # true obliquity (radians)
    eps = eps0 + d_eps

    # Nutation rotation N = Rx(-ε) · Rz(-Δψ) · Rx(ε0)
    {x4, y4, z4} = rot_x({x3, y3, z3}, eps0)
    {x5, y5, z5} = rot_z({x4, y4, z4}, -d_psi)
    {x6, y6, z6} = rot_x({x5, y5, z5}, -eps)

    {x6, y6, z6}
  end

  # ── Spherical coordinates ────────────────────────────────────────────────────

  @doc """
  Converts equatorial Cartesian coordinates to spherical coordinates.

  ### Arguments

  * `{x, y, z}` is an equatorial Cartesian position vector in
    kilometers.

  ### Returns

  * `{ra_deg, dec_deg, distance_km}` where right ascension is
    in degrees in the range [0, 360), declination is in degrees
    in the range [-90, 90], and distance is in kilometers.

  """
  @spec cartesian_to_spherical({float(), float(), float()}) ::
          {float(), float(), float()}
  def cartesian_to_spherical({x, y, z}) do
    dist = :math.sqrt(x * x + y * y + z * z)
    dec_rad = :math.asin(z / dist)
    ra_rad = :math.atan2(y, x)
    ra_deg = ra_rad * 180.0 / :math.pi()
    ra_deg = if ra_deg < 0.0, do: ra_deg + 360.0, else: ra_deg
    dec_deg = dec_rad * 180.0 / :math.pi()
    {ra_deg, dec_deg, dist}
  end

  # ── Greenwich Apparent Sidereal Time ─────────────────────────────────────────

  @doc """
  Computes Greenwich Apparent Sidereal Time (GAST) in degrees.

  GMST is computed from UT1 (≈ UTC) using Meeus equation 12.4,
  then corrected by the equation of the equinoxes (Δψ · cos ε)
  to obtain GAST.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0. ΔT is
    subtracted internally to recover UT1 for the sidereal
    rotation rate.

  ### Returns

  * GAST in degrees, normalized to the range [0, 360).

  """
  @spec gast(float()) :: float()
  def gast(dynamical_time) do
    # GMST must be computed from UT1 (≈ UTC), not TDB.
    # dynamical_time is TDB seconds past J2000.0; subtract ΔT to recover UTC seconds.
    jd_tt = dynamical_time / @seconds_per_day + @jd_j2000
    year = 2000.0 + (jd_tt - @jd_j2000) / 365.25
    dt = Astro.Time.delta_t(year)
    jd_utc = (dynamical_time - dt) / @seconds_per_day + @jd_j2000

    # Julian centuries in UT1 — for the quadratic/cubic polynomial terms.
    t_ut = (jd_utc - @jd_j2000) / 36_525.0

    # Greenwich Mean Sidereal Time (degrees), Meeus eq 12.4.
    # The sidereal rotation rate 360.98564736629°/day must multiply elapsed
    # UT1 days, not TDB days. Using TDB here introduces a fixed 0.289° error
    # (= 360.986 × ΔT/86400) equivalent to ~1.15 minutes in rise/set time.
    gmst =
      280.46061837 +
        360.98564736629 * (jd_utc - @jd_j2000) +
        0.000387933 * t_ut * t_ut -
        t_ut * t_ut * t_ut / 38_710_000.0

    gmst = :math.fmod(gmst, 360.0)
    gmst = if gmst < 0.0, do: gmst + 360.0, else: gmst

    # Equation of the equinoxes: Δψ · cos(ε), converted to degrees.
    # Nutation uses TDB centuries — consistent with the ephemeris frame.
    t_tdb = julian_centuries_from_dynamical_time(dynamical_time)
    {dpsi, _deps, eps0} = Earth.nutation(t_tdb)
    eq_eq = dpsi * :math.cos(eps0) * 180.0 / :math.pi()

    gast = gmst + eq_eq
    gast = :math.fmod(gast, 360.0)
    if gast < 0.0, do: gast + 360.0, else: gast
  end

  # ── Rotation helpers ─────────────────────────────────────────────────────────

  # Right-handed rotation about the X axis by angle `a` (radians).
  # Rx(a) = [[1,0,0],[0,cos,-sin],[0,sin,cos]]
  defp rot_x({x, y, z}, a) do
    ca = :math.cos(a)
    sa = :math.sin(a)
    {x, ca * y - sa * z, sa * y + ca * z}
  end

  # Right-handed rotation about the Y axis by angle `a` (radians).
  # Ry(a) = [[cos,0,sin],[0,1,0],[-sin,0,cos]]
  defp rot_y({x, y, z}, a) do
    ca = :math.cos(a)
    sa = :math.sin(a)
    {ca * x + sa * z, y, -sa * x + ca * z}
  end

  # Right-handed rotation about the Z axis by angle `a` (radians).
  # Rz(a) = [[cos,-sin,0],[sin,cos,0],[0,0,1]]
  defp rot_z({x, y, z}, a) do
    ca = :math.cos(a)
    sa = :math.sin(a)
    {ca * x - sa * y, sa * x + ca * y, z}
  end

  defp arcsec_to_rad(arcsec) do
    arcsec / @arcsec_per_deg * :math.pi() / 180.0
  end
end
