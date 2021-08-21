defmodule Astro.Utils do
  @moduledoc false
  import Astro.Guards

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
end
