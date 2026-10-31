defmodule Astro.Location do
  @moduledoc false

  import Astro.Guards

  def new(lng, lat, alt \\ 0.0) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    %Geo.PointZ{coordinates: {lng, lat, alt}}
  end

  @doc """
  Normalizes a location into a `t:Geo.PointZ.t/0` struct.

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

  @doc """
  Validates a location and normalizes it into a `t:Geo.PointZ.t/0`.

  Returns `{:ok, point}` for a `{longitude, latitude}` or
  `{longitude, latitude, elevation}` tuple, a `t:Geo.Point.t/0` or a
  `t:Geo.PointZ.t/0` whose longitude is within ±180° and latitude
  within ±90°, and `{:error, :invalid_location}` for anything else.
  """
  def validate_location({lng, lat, alt} = location)
      when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    {:ok, normalize_location(location)}
  end

  def validate_location({lng, lat} = location) when is_lat(lat) and is_lng(lng) do
    {:ok, normalize_location(location)}
  end

  def validate_location(%Geo.Point{coordinates: {lng, lat}} = location)
      when is_lat(lat) and is_lng(lng) do
    {:ok, normalize_location(location)}
  end

  def validate_location(%Geo.PointZ{coordinates: {lng, lat, alt}} = location)
      when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    {:ok, location}
  end

  def validate_location(_location) do
    {:error, :invalid_location}
  end

  def round(%Geo.PointZ{coordinates: {lng, lat, alt}} = location, precision \\ 5) do
    coordinates =
      {Float.round(lng, precision), Float.round(lat, precision), Float.round(alt, precision)}

    Map.put(location, :coordinates, coordinates)
  end
end
