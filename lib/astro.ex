defmodule Astro do
  alias Astro.Solar

  def sunrise(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :rise)
    Solar.sun_rise_or_set(location, date, options)
  end

  def sunset(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :set)
    Solar.sun_rise_or_set(location, date, options)
  end

  def default_options do
    [
      solar_elevation: Solar.solar_elevation(:geometric),
      time_zone: :default,
      time_zone_database: Tzdata.TimeZoneDatabase
    ]
  end
end
