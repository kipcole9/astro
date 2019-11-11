defmodule Astro.Earth do
  import Astro.Utils

  @geometric_zenith 90.0
  @refraction 34 / 60.0
  @solar_radius 16 / 60.0

  # Radius in km
  @earth_radius 6356.9

  def refraction do
    @refraction
  end

  def solar_radius do
    @solar_radius
  end

  def earth_radius do
    @earth_radius
  end

  def elevation_adjustment(elevation) do
    :math.acos(earth_radius() / (earth_radius() + elevation / 1000.0))
    |> to_degrees
  end

  def adjusted_zenith(@geometric_zenith = zenith, elevation) do
    zenith + solar_radius() + refraction() + elevation_adjustment(elevation)

  end

  def adjusted_zenith(_zenith, _elevation) do
    @geometric_zenith
  end
end
