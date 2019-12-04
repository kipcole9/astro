defmodule Astro.Earth do
  import Astro.Utils

  @geometric_solar_elevation 90.0
  @refraction 34 / 60.0
  @solar_radius 16 / 60.0
  @meters_per_kilometer 1000.0

  # Radius in km
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

  def elevation_adjustment(elevation) do
    :math.acos(earth_radius() / (earth_radius() + elevation / @meters_per_kilometer))
    |> to_degrees
  end

  def adjusted_solar_elevation(@geometric_solar_elevation = solar_elevation, elevation) do
    solar_elevation + solar_radius() + refraction() + elevation_adjustment(elevation)
  end

  def adjusted_solar_elevation(_solar_elevation, _elevation) do
    @geometric_solar_elevation
  end
end
