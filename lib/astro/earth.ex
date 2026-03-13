defmodule Astro.Earth do
  @moduledoc """
  Earth constants, nutation, and elevation-related corrections
  for rise/set calculations.

  This module provides physical and geometric constants for the
  Earth (equatorial radius, atmospheric refraction, apparent solar
  radius, mean obliquity) together with the IAU 1980 nutation
  series and elevation adjustments used by the rise/set algorithms
  in `Astro.Solar.SunRiseSet` and `Astro.Lunar.MoonRiseSet`.

  ## Function groups

  ### Physical constants

  * `earth_radius/0` — equatorial radius in kilometers
  * `obliquity_j2000/0` — mean obliquity of the ecliptic at J2000.0

  ### Optical constants

  * `refraction/0` — standard atmospheric refraction at the horizon
  * `solar_radius/0` — apparent solar semi-diameter at the horizon

  ### Nutation

  * `nutation/1` — IAU 1980 nutation in longitude and obliquity (17-term)

  ### Observer geometry

  * `horizon_distance/1` — geometric distance to the horizon
  * `elevation_adjustment/1` — dip angle correction for observer elevation
  * `adjusted_solar_elevation/2` — combined refraction, radius and elevation correction

  """
  alias Astro.Time

  import Astro.Math, only: [to_degrees: 1]

  @meters_per_kilometer 1000.0

  @doc false
  def meters_per_kilometer, do: @meters_per_kilometer

  @geometric_solar_elevation 90.0

  # 34 arc minutes in degrees
  @refraction 34.0 / 60.0

  # 16 arc minutes in degrees
  @solar_radius 16.0 / 60.0

  # Mean obliquity in degrees
  @obliquity 23.4397

  # Arcseconds per degree
  @arcsec_per_deg 3600.0

  @doc false
  def arcsec_per_deg, do: @arcsec_per_deg

  # Equatorial radius in kilometers
  @earth_radius 6_378.1366
  @earth_radius_m @earth_radius * @meters_per_kilometer

  @doc """
  Returns an estimate of the effect of refraction
  (in degrees) applied to the calculation of sunrise and
  sunset times.

  Sunrise actually occurs before the Sun truly
  reaches the horizon because earth's atmosphere
  refracts the sun's image. At the horizon, the average
  amount of refraction is 34 arcminutes, though this
  amount varies based on atmospheric conditions.

  This effect is especially powerful for objects
  that appear close to the horizon, such as the
  rising or setting sun, because the light rays
  enter the earth's atmosphere at a particularly
  shallow angle. Because of refraction, the sun
  may be seen for several minutes before it actually
  rises in the morning and after it sets in the
  evening.

  The refraction angle is calculated using the formula
  from [Meeus](https://www.amazon.com/dp/0943396611) (2nd edition, chapter 15):

  ```
  R = 1 / tan(0° + 7.31 / (0° + 4.4)) ≈ 34 arcminutes = 0.5667°
  ```
  The [Astronomical Almanac](https://www.amazon.com/Astronomical-Almanac-2023-Comprehensive-Events/dp/B0BGZLFPF4/ref=sr_1_1)
  uses the same value.

  """
  @spec refraction :: Astro.degrees()
  def refraction do
    @refraction
  end

  @doc """
  Returns the Sun's apparent radius in degrees
  at sunrise/sunset.

  Unlike most other solar measurements, sunrise occurs
  when the Sun's upper limb, rather than its center,
  appears to cross the horizon. The apparent radius of
  the Sun at the horizon is 16 arc minutes.

  """
  @spec solar_radius :: Astro.degrees()
  def solar_radius do
    @solar_radius
  end

  @doc """
  Returns the Earth's equatorial radius in kilometers.

  This value is the [IAU](https://iau-a3.gitlab.io/NSFA/NSFA_cbe.html#EarthRadius2009)
  current best estimate and the recommended value for
  astronomical calculations.

  """
  @spec earth_radius :: Astro.kilometers()
  def earth_radius do
    @earth_radius
  end

  @doc false
  def earth_radius_m do
    @earth_radius_m
  end

  @doc """
  Returns the geometric distance to the horizon in meters.

  Uses the exact formula `√(h² + 2Rh)` where `h` is the
  observer's elevation and `R` is the Earth's equatorial
  radius. Atmospheric refraction is not included.

  ### Arguments

  * `observer_elevation_m` is the observer's elevation above
    sea level in meters. Defaults to `0.0`.

  ### Returns

  * The distance to the geometric horizon in meters.

  """
  def horizon_distance(observer_elevation_m \\ 0.0) do
    # Distance to the geometric horizon in metres (standard formula).
    # approximation is d = sqrt(2 * R * h)  (without refraction, the pure geometric distance)
    # exact formula is d = √(h² + 2Rh)
    :math.sqrt(
      observer_elevation_m * observer_elevation_m + 2 * @earth_radius_m * observer_elevation_m
    )
  end

  @doc """
  Returns the mean [obliquity](https://en.wikipedia.org/wiki/Axial_tilt)
  of the [ecliptic](https://en.wikipedia.org/wiki/Ecliptic) at
  [epoch](https://en.wikipedia.org/wiki/Epoch_(astronomy)) J2000.0.

  Obliquity, or axial tilt, is the angle between the
  Earth's rotational axis and its orbital axis, which is
  the line perpendicular to its orbital plane.

  The rotational axis of Earth, for example, is the imaginary
  line that passes through both the North Pole and South Pole,
  whereas the Earth's orbital axis is the line perpendicular
  to the imaginary plane through which the Earth moves as it
  revolves around the Sun. The Earth's obliquity or axial tilt
  is the angle between these two lines.

  See [Astronomical Algorithms](https://www.amazon.com/dp/0943396611) Chapter 22.

  ### Returns

  * The mean obliquity as a float angle in degrees
    at j2000.

  """
  @spec obliquity_j2000 :: Astro.angle()
  def obliquity_j2000 do
    @obliquity
  end

  @doc """
  Computes IAU 1980 [nutation](https://en.wikipedia.org/wiki/Astronomical_nutation#:~:text=Earth's%20nutation,-Learn%20more&text=Nutation%20(N)%20of%20the%20Earth,spherical%20figure%20of%20the%20Earth.))
  in longitude and obliquity, and the mean obliquity.

  ### Arguments

  * `julian_century` is any astronomical Julian century such
    as returned from `Astro.Time.julian_centuries_from_julian_day/1`.

  ### Returns

  * `{delta_psi_rad, delta_eps_rad, eps0_rad}` representing
    the longitude, obliquity and mean obliquity.

  """
  @spec nutation(c :: Time.julian_centuries()) :: {float(), float(), float()}
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

  @doc """
  Adjusts the solar elevation to account
  for the elevation of the requested location.

  ### Arguments

  * `elevation` is the observer's elevation in meters.

  ### Returns

  * The solar elevation angle adjusted for the observer's
    elevation.

  """
  def elevation_adjustment(elevation) do
    :math.acos(earth_radius() / (earth_radius() + elevation / @meters_per_kilometer))
    |> to_degrees
  end

  @doc """
  Adjusts the solar elevation to be the apparent angle
  at sunrise if the requested angle is `:geometric`
  (or 90°).

  ### Arguments

  * `solar_elevation` is the requested solar elevation
    in degrees. It will be 90° for sunrise and sunset.

  * `elevation` is elevation in meters

  ### Returns

  * The solar elevation angle which, if solar elevation is
    exactly 90.0 degrees, is adjusted for refraction,
    elevation and solar radius.

  """
  def adjusted_solar_elevation(@geometric_solar_elevation = solar_elevation, elevation) do
    solar_elevation + solar_radius() + refraction() + elevation_adjustment(elevation)
  end

  def adjusted_solar_elevation(solar_elevation, elevation) do
    solar_elevation + elevation_adjustment(elevation)
  end
end
