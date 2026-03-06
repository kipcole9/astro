defmodule Astro.Earth do
  @moduledoc """
  Constants and astronomical calculations
  related to the Earth.

  """
  alias Astro.Time

  import Astro.Math, only: [to_radians: 1, to_degrees: 1, poly: 2, deg: 1, sin: 1]

  @geometric_solar_elevation 90.0

  # 34 arc minutes in degrees
  @refraction 34.0 / 60.0

  # 16 arc minutes in degrees
  @solar_radius 16.0 / 60.0

  @meters_per_kilometer 1000.0
  @obliquity to_radians(23.4397)
  @earth_radius 6_378.1366

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
  The [Astronomical Almanac](https://www.amazon.com/Astronomical-Almanac-2023-Comprehensive-Events/dp/B0BGZLFPF4/ref=sr_1_1) uses the same
  value.

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

  @doc """
  Returns the mean [obliquity](https://en.wikipedia.org/wiki/Axial_tilt)
  of the [ecliptic](https://en.wikipedia.org/wiki/Ecliptic) at
  [epoch](https://en.wikipedia.org/wiki/Epoch_(astronomy)) J2000.0.

  Obliquity, or axial tilt, is the angle between an the
  earth's rotational axis and its orbital axis, which is
  the line perpendicular to its orbital plane.

  The rotational axis of Earth, for example, is the imaginary
  line that passes through both the North Pole and South Pole,
  whereas the Earth's orbital axis is the line perpendicular
  to the imaginary plane through which the Earth moves as it
  revolves around the Sun. The Earth's obliquity or axial tilt
  is the angle between these two lines.

  See [Astronomical Algorithms](https://www.amazon.com/dp/0943396611) Chapter 22.

  """
  @spec obliquity :: Astro.radians()
  def obliquity do
    @obliquity
  end

  @doc """
  Returns the [nutation](https://en.wikipedia.org/wiki/Astronomical_nutation#:~:text=Earth's%20nutation,-Learn%20more&text=Nutation%20(N)%20of%20the%20Earth,spherical%20figure%20of%20the%20Earth.)
  correction at a given time.

  Nutation is the variation over time of the orientation of the
  axis of rotation of the Earth due primarily to gravitational
  forces of the Moon acting upon the spinning Earth.

  ### Arguments

  * `julian_century` is any astronomical Julian century such
    as returned from `Astro.Time.julian_centuries_from_julian_day/1`.

  ### Returns

  * `nutation`, a float angle in degrees.

  """
  @spec nutation(Time.julian_centuries()) :: Astro.angle()
  def nutation(julian_centuries) do
    a = poly(julian_centuries, Enum.map([124.90, -1934.134, 0.002063], &deg/1))
    b = poly(julian_centuries, Enum.map([201.11, 72001.5377, 0.00057], &deg/1))
    deg(-0.004778) * sin(a) + deg(-0.0003667) * sin(b)
  end

  @doc """
  Adjusts the solar elevation to account
  for the elevation of the requested location.

  ### Arguments

  * `elevation` is elevation in meters.

  ### Returns

  * The solar elevation angle adjusted for the elevation.

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
    in degress. It will be 90° for sunrise and sunset.

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
