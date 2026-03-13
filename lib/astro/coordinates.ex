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

  ΔT = TT − UTC varies over time. For 1972–2025 we use IERS-observed
  annual values with linear interpolation; for dates beyond 2025 we
  extrapolate at the recent growth rate (~0.15 s/year). This is accurate
  to < 0.5 s for historical dates and < 2 s through ~2040.

  ## Reference

  Precession: Lieske et al. (1977), A&A 58, 1–16.
  Nutation:   IAU 1980 series, Wahr (1981), Meeus Ch.22 (top 17 terms).
  GAST:       Meeus Ch.12 with equation of the equinoxes.
  ΔT:         IERS Bulletin A/B observed values, 1972–2025.
  """

  alias Astro.Earth

  # IERS-observed ΔT values (TT − UT1 ≈ TT − UTC to within 0.9 s),
  # one value per year at the year midpoint (July 1), 1972–2025.
  # Source: IERS Earth Orientation Parameters, Bulletin A/B.
  @delta_t_table %{
    1972 => 42.23, 1973 => 43.37, 1974 => 44.49, 1975 => 45.48,
    1976 => 46.46, 1977 => 47.52, 1978 => 48.53, 1979 => 49.59,
    1980 => 50.54, 1981 => 51.38, 1982 => 52.17, 1983 => 52.96,
    1984 => 53.79, 1985 => 54.34, 1986 => 54.87, 1987 => 55.32,
    1988 => 55.82, 1989 => 56.30, 1990 => 56.86, 1991 => 57.57,
    1992 => 58.31, 1993 => 59.12, 1994 => 59.98, 1995 => 60.78,
    1996 => 61.63, 1997 => 62.29, 1998 => 62.97, 1999 => 63.47,
    2000 => 63.83, 2001 => 64.09, 2002 => 64.30, 2003 => 64.47,
    2004 => 64.57, 2005 => 64.69, 2006 => 64.85, 2007 => 65.15,
    2008 => 65.46, 2009 => 65.78, 2010 => 66.07, 2011 => 66.32,
    2012 => 66.60, 2013 => 66.91, 2014 => 67.28, 2015 => 67.64,
    2016 => 68.10, 2017 => 68.59, 2018 => 68.97, 2019 => 69.22,
    2020 => 69.36, 2021 => 69.36, 2022 => 69.18, 2023 => 69.04,
    2024 => 69.18, 2025 => 69.30
  }

  @delta_t_first_year 1972
  @delta_t_last_year 2025
  # Linear extrapolation rate beyond the table (seconds/year).
  @delta_t_extrap_rate 0.15

  # J2000.0 Julian date (TT): 2000-01-01 12:00:00 TT
  @jd_j2000 2_451_545.0

  # Seconds per day
  @seconds_per_day 86_400.0

  # Arcseconds per degree
  @arcsec_per_deg 3600.0

  # ── Time conversions ─────────────────────────────────────────────────────────

  @doc """
  Converts a moment to dynamical time. Delegates to `Astro.Time.dynamical_time_from_moment/1`.
  """
  defdelegate dynamical_time_from_moment(moment), to: Astro.Time

  @doc """
  Converts dynamical time to a moment. Delegates to `Astro.Time.dynamical_time_to_moment/1`.
  """
  defdelegate dynamical_time_to_moment(dynamical_time), to: Astro.Time

  @doc """
  Returns Julian centuries from J2000.0 for the given dynamical time.
  Delegates to `Astro.Time.julian_centuries_from_dynamical_time/1`.
  """
  defdelegate julian_centuries_from_dynamical_time(dynamical_time), to: Astro.Time

  # ── Precession and nutation (IAU 1980) ───────────────────────────────────────

  @doc """
  Rotates a J2000.0 ICRF Cartesian vector `{x, y, z}` to the true equator
  and equinox of date, applying IAU 1980 precession and nutation.

  Returns `{x', y', z'}` in the same units as the input.
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
  Converts equatorial Cartesian `{x, y, z}` (km) to spherical coordinates.

  Returns `{ra_deg, dec_deg, distance_km}` where RA is in [0, 360).
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

  Includes the equation of the equinoxes (nutation in RA).
  `dynamical_time` is TDB seconds past J2000.0.
  """
  @spec gast(float()) :: float()
  def gast(dynamical_time) do
    # GMST must be computed from UT1 (≈ UTC), not TDB.
    # dynamical_time is TDB seconds past J2000.0; subtract ΔT to recover UTC seconds.
    jd_tt = dynamical_time / @seconds_per_day + @jd_j2000
    year = jd_to_decimal_year(jd_tt)
    dt = delta_t(year)
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

  # ── ΔT computation ──────────────────────────────────────────────────────────

  @doc """
  Returns ΔT (TT − UTC) in seconds for the given decimal year.

  For 1972–2025 uses IERS-observed annual values with linear interpolation.
  For dates before 1972 or after 2025, extrapolates from the nearest
  table boundary at the recent growth rate.

  ## Examples

      iex> Astro.Coordinates.delta_t(2000.0)
      63.83

      iex> Astro.Coordinates.delta_t(2024.5)  # interpolated
      69.24

  """
  @spec delta_t(float()) :: float()
  def delta_t(year) when is_number(year) do
    cond do
      year <= @delta_t_first_year ->
        # Before table: extrapolate backwards from first entry
        @delta_t_table[@delta_t_first_year] + @delta_t_extrap_rate * (year - @delta_t_first_year)

      year >= @delta_t_last_year ->
        # After table: extrapolate forward from last entry
        @delta_t_table[@delta_t_last_year] + @delta_t_extrap_rate * (year - @delta_t_last_year)

      true ->
        # Interpolate between floor and ceiling year entries
        y0 = trunc(year)
        y1 = y0 + 1
        frac = year - y0
        v0 = @delta_t_table[y0]
        v1 = @delta_t_table[y1]
        v0 + frac * (v1 - v0)
    end
  end

  # Converts a Julian Date to a decimal year (approximate, for ΔT lookup).
  defp jd_to_decimal_year(jd) do
    2000.0 + (jd - @jd_j2000) / 365.25
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
