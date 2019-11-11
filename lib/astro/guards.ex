defmodule Astro.Guards do
  defguard is_lat(lat) when is_number(lat) and lat >= -90.0 and lat <= 90.0
  defguard is_lng(lng) when is_number(lng) and lng >= -180.0 and lng <= 180.0
  defguard is_alt(alt) when is_number(alt)
end
