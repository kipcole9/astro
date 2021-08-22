defmodule Astro.Earth do
  @moduledoc """
  Constants and astronomical calculations
  related to the earth.

  """

  import Astro.Math, only: [to_radians: 1, to_degrees: 1]

  @geometric_solar_elevation 90.0
  @refraction 34.0 / 60.0
  @solar_radius 16.0 / 60.0
  @meters_per_kilometer 1000.0
  @obliquity to_radians(23.4397)
  @earth_radius 6356.9

  @doc """
  Returns an estimate of the effect of refraction
  applied to the calculation of sunrise and
  sunset times.

  Sunrise actually occurs before the sun truly
  reaches the horizon because earth's atmosphere
  refracts the Sun's image. At the horizon, the average
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

  """
  def refraction do
    @refraction
  end

  @doc """
  Returns the suns apparent radius at sunrise/sunset.

  Unlike most other solar measurements, sunrise occurs
  when the Sun's upper limb, rather than its center,
  appears to cross the horizon. The apparent radius of
  the Sun at the horizon is 16 arcminutes.

  """
  def solar_radius do
    @solar_radius
  end

  @doc """
  Returns the radius of the earth in kilometers
  """
  def earth_radius do
    @earth_radius
  end

  @doc """
  Returns the obliquity of the earth
  """
  def obliquity do
    @obliquity
  end

  @doc """
  Adjusts the solar elevation to account
  for the elevation of the requested location

  ## Arguments

  * `elevation` is elevation in meters

  ## Returns

  * The solar elevation angle adjusted for the elevation

  """
  def elevation_adjustment(elevation) do
    :math.acos(earth_radius() / (earth_radius() + elevation / @meters_per_kilometer))
    |> to_degrees
  end

  @doc """
  Adjusts the solar elevation to be the apparent angle
  at sunrise if the requested angle is `:geometric`
  (or 90°)

  ## Arguments

  * `solar_elevation` is the requested solar elevation
    in degress. It will be 90° for sunrise and sunset.

  * `elevation` is elevation in meters

  ## Returns

  * The solar elevation angle adjusted for refraction,
    elevation and solar radius.

  """
  def adjusted_solar_elevation(@geometric_solar_elevation = solar_elevation, elevation) do
    solar_elevation + solar_radius() + refraction() + elevation_adjustment(elevation)
  end

  def adjusted_solar_elevation(_solar_elevation, _elevation) do
    @geometric_solar_elevation
  end

end
