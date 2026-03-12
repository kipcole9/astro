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

  ΔT = TT − UTC. We use a fixed estimate of 69.2 seconds, consistent with
  IERS Bulletin A observed values for 2020–2030. This is more accurate than
  the Calendrical Calculations polynomial (which yields ~75 s for 2026).

  ## Reference

  Precession: Lieske et al. (1977), A&A 58, 1–16.
  Nutation:   IAU 1980 series, Wahr (1981), Meeus Ch.22 (top 17 terms).
  GAST:       Meeus Ch.12 with equation of the equinoxes.
  """

  # ΔT = TT − UTC in seconds (IERS observed, best estimate 2020–2030).
  # Revisit if using this module outside that range.
  @delta_t_seconds 69.2

  # J2000.0 Julian date (TT): 2000-01-01 12:00:00 TT
  @jd_j2000 2_451_545.0

  # Julian date of Unix epoch (1970-01-01 00:00:00 UTC)
  @jd_unix_epoch 2_440_587.5

  # Seconds per day
  @seconds_per_day 86_400.0

  # Arcseconds per degree
  @arcsec_per_deg 3600.0

  # ── Time conversions ─────────────────────────────────────────────────────────

  @doc """
  Converts a UTC `DateTime` to TDB seconds past J2000.0.

  This is the `et` (ephemeris time) argument expected by the SPK kernel.
  """
  @spec utc_to_et(DateTime.t()) :: float()
  def utc_to_et(%DateTime{} = utc_dt) do
    unix_seconds = DateTime.to_unix(utc_dt, :millisecond) / 1000.0
    jd_utc = @jd_unix_epoch + unix_seconds / @seconds_per_day
    jd_tt = jd_utc + @delta_t_seconds / @seconds_per_day
    (jd_tt - @jd_j2000) * @seconds_per_day
  end

  @doc """
  Converts TDB seconds past J2000.0 back to a UTC `DateTime`,
  rounded to the nearest minute.
  """
  @spec et_to_utc(float()) :: DateTime.t()
  def et_to_utc(et) do
    jd_tt = et / @seconds_per_day + @jd_j2000
    jd_utc = jd_tt - @delta_t_seconds / @seconds_per_day
    unix_float = (jd_utc - @jd_unix_epoch) * @seconds_per_day
    unix_seconds = round(unix_float)
    DateTime.from_unix!(unix_seconds, :second)
  end

  @doc """
  Returns Julian centuries from J2000.0 for the given ET (TDB seconds past J2000).
  """
  @spec julian_centuries(float()) :: float()
  def julian_centuries(et) do
    et / (@seconds_per_day * 36_525.0)
  end

  # ── Precession and nutation (IAU 1980) ───────────────────────────────────────

  @doc """
  Rotates a J2000.0 ICRF Cartesian vector `{x, y, z}` to the true equator
  and equinox of date, applying IAU 1980 precession and nutation.

  Returns `{x', y', z'}` in the same units as the input.
  """
  @spec icrf_to_true_equator({float(), float(), float()}, float()) ::
          {float(), float(), float()}
  def icrf_to_true_equator({x, y, z}, et) do
    t = julian_centuries(et)

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
    {d_psi, d_eps, eps0} = nutation(t)
    # true obliquity (radians)
    eps = eps0 + d_eps

    # Nutation rotation N = Rx(-ε) · Rz(-Δψ) · Rx(ε0)
    {x4, y4, z4} = rot_x({x3, y3, z3}, eps0)
    {x5, y5, z5} = rot_z({x4, y4, z4}, -d_psi)
    {x6, y6, z6} = rot_x({x5, y5, z5}, -eps)

    {x6, y6, z6}
  end

  @doc """
  Computes IAU 1980 nutation in longitude and obliquity, and the mean obliquity.

  Returns `{delta_psi_rad, delta_eps_rad, eps0_rad}`.

  `c` is Julian centuries from J2000.0.
  """
  @spec nutation(c :: Astro.Time.julian_centuries) :: {float(), float(), float()}
  def nutation(c) do
    # Fundamental arguments (degrees, Meeus Ch.22)
    d = 297.85036 + 445_267.111480 * c - 0.0019142 * c * c + c * c * c / 189_474.0
    m = 357.52772 + 35_999.050340 * c - 0.0001603 * c * c - c * c * c / 300_000.0
    mp = 134.96298 + 477_198.867398 * c + 0.0086972 * c * c + c * c * c / 56_250.0
    f = 93.27191 + 483_202.017538 * c - 0.0036825 * c * c + c * c * c / 327_270.0
    om = 125.04452 - 1_934.136261 * c + 0.0020708 * c * c + c * c * c / 450_000.0

    # Top 17 terms of the IAU 1980 nutation series.
    # Format: {D, M, M', F, Om, dpsi_s (0.0001"), deps_c (0.0001")}
    terms = [
      {0, 0, 0, 0, 1, -171_996.0, 92_025.0},
      {-2, 0, 0, 2, 2, -13_187.0, 5_736.0},
      {0, 0, 0, 2, 2, -2_274.0, 977.0},
      {0, 0, 0, 0, 2, 2_062.0, -895.0},
      {0, 1, 0, 0, 0, 1_426.0, 54.0},
      {0, 0, 1, 0, 0, 712.0, -7.0},
      {-2, 1, 0, 2, 2, -517.0, 224.0},
      {0, 0, 0, 2, 1, -386.0, 200.0},
      {0, 0, 1, 2, 2, -301.0, 129.0},
      {-2, -1, 0, 2, 2, 217.0, -95.0},
      {-2, 0, 1, 0, 0, -158.0, 0.0},
      {-2, 0, 0, 2, 1, 129.0, -70.0},
      {0, 0, -1, 2, 2, 123.0, -53.0},
      {2, 0, 0, 0, 0, 63.0, 0.0},
      {0, 0, 1, 0, 1, 63.0, -33.0},
      {2, 0, -1, 2, 2, -59.0, 26.0},
      {0, 0, -1, 0, 1, -58.0, 32.0}
    ]

    {dpsi_units, deps_units} =
      Enum.reduce(terms, {0.0, 0.0}, fn {td, tm, tmp, tf, tom, ds, dc}, {acc_psi, acc_eps} ->
        arg_deg = td * d + tm * m + tmp * mp + tf * f + tom * om
        arg_rad = :math.pi() / 180.0 * arg_deg
        {acc_psi + ds * :math.sin(arg_rad), acc_eps + dc * :math.cos(arg_rad)}
      end)

    # Convert from 0.0001 arcseconds to radians
    dpsi = dpsi_units * 0.0001 / @arcsec_per_deg * :math.pi() / 180.0
    deps = deps_units * 0.0001 / @arcsec_per_deg * :math.pi() / 180.0

    # Mean obliquity of the ecliptic (Meeus eq 22.2), arcseconds → radians
    eps0_arcsec = 84_381.448 - 46.8150 * c - 0.00059 * c * c + 0.001813 * c * c * c
    eps0 = eps0_arcsec / @arcsec_per_deg * :math.pi() / 180.0

    {dpsi, deps, eps0}
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
  `et` is TDB seconds past J2000.0.
  """
  @spec gast(float()) :: float()
  def gast(et) do
    # GMST must be computed from UT1 (≈ UTC), not TDB.
    # et is TDB seconds past J2000.0; subtract ΔT to recover UTC seconds.
    jd_utc = (et - @delta_t_seconds) / @seconds_per_day + @jd_j2000

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
    t_tdb = julian_centuries(et)
    {dpsi, _deps, eps0} = nutation(t_tdb)
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
