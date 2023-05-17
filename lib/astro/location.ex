defmodule Astro.Location do
  @moduledoc false

  import Astro.Guards

  def new(lng, lat, alt \\ 0.0) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    %Geo.PointZ{coordinates: {lng, lat, alt}}
  end

  @doc """
  Normalizes a location into a `t:Geo.PointZ` struct.

  """
  def normalize_location({lng, lat, alt}) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    %Geo.PointZ{coordinates: {lng, lat, alt}}
  end

  def normalize_location({lng, lat}) when is_lat(lat) and is_lng(lng) do
    %Geo.PointZ{coordinates: {lng, lat, 0.0}}
  end

  def normalize_location(%Geo.Point{coordinates: {lng, lat}}) when is_lat(lat) and is_lng(lng) do
    %Geo.PointZ{coordinates: {lng, lat, 0.0}}
  end

  def normalize_location(%Geo.PointZ{coordinates: {lng, lat, alt}} = location)
      when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    location
  end

  def round(%Geo.PointZ{coordinates: {lng, lat, alt}} = location, precision \\ 5) do
    coordinates = {Float.round(lng, precision), Float.round(lat, precision), Float.round(alt, precision)}
    Map.put(location, :coordinates, coordinates)
  end
end
