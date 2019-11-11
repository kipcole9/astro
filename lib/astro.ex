defmodule Astro do
  import Astro.Solar, only: [zenith: 1]
  import Astro.Time, only: [to_datetime: 2]
  import Astro.Guards

  def sunrise(location, date \\ Date.utc_today(), zenith \\ zenith(:geometric))

  def sunrise({lng, lat, alt}, date, zenith) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    sunrise(%Geo.PointZ{coordinates: {lng, lat, alt}}, date, zenith)
  end

  def sunrise({lng, lat}, date, zenith) when is_lat(lat) and is_lng(lng) do
    sunrise(%Geo.PointZ{coordinates: {lng, lat, 0.0}}, date, zenith)
  end

  def sunrise(%Geo.Point{coordinates: {lng, lat}}, date, zenith) when is_lat(lat) and is_lng(lng) do
    sunrise(%Geo.PointZ{coordinates: {lng, lat, 0.0}}, date, zenith)
  end

  def sunrise(%Geo.PointZ{} = location, date, zenith) do
    Astro.Solar.utc_sunrise(date, location, zenith)
    |> to_datetime(date)
  end

  def sunset(location, date \\ Date.utc_today(), zenith \\ zenith(:geometric))

  def sunset({lng, lat, alt}, date, zenith) when is_lat(lat) and is_lng(lng) and is_alt(alt) do
    sunset(%Geo.PointZ{coordinates: {lng, lat, alt}}, date, zenith)
  end

  def sunset({lng, lat}, date, zenith) when is_lat(lat) and is_lng(lng) do
    sunset(%Geo.PointZ{coordinates: {lng, lat, 0.0}}, date, zenith)
  end

  def sunset(%Geo.Point{coordinates: {lng, lat}}, date, zenith) when is_lat(lat) and is_lng(lng) do
    sunset(%Geo.PointZ{coordinates: {lng, lat, 0.0}}, date, zenith)
  end

  def sunset(%Geo.PointZ{} = location, date, zenith) do
    Astro.Solar.utc_sunset(date, location, zenith)
    |> to_datetime(date)
  end

end
