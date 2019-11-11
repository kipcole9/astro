defmodule Astro.Location do
  @moduledoc """
  Defines a location with attributes relevant to
  astronomical calculations.

  * `lng` is terrestrial longitude in degress

  * `lat` is terrestrial latitudes in degrees

  * `elevation` is elevation above mean sea level in metres

  * `offset` is the offset of a standard time zone expressed as
    a fraction of a day after UTC

  * `zone` is the offset from UTC calculated from the `lng`
    of the location
  """

  defstruct lng: 0.0, lat: 0.0, elevation: 0.0, zone: "Etc/UTC", offset: 0.0
  alias Astro.Time
  import Astro.Guards

  def new(lng, lat, elevation \\ 0.0) when is_lat(lat) and is_lng(lng) and is_number(elevation) do
    zone = TzWorld.timezone_at(%Geo.Point{coordinates: {lng, lat}})
    new(lng, lat, elevation, zone)
  end

  def new(lng, lat, elevation, zone)
      when is_lat(lat) and is_lng(lng) and is_number(elevation) and is_binary(zone) do
    %__MODULE__{lng: lng, lat: lat, elevation: elevation, offset: Time.offset(lng), zone: zone}
  end
end
