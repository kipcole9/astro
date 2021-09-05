defmodule Astro.Guards do
  defguard is_lat(lat) when is_number(lat) and lat >= -90.0 and lat <= 90.0
  defguard is_lng(lng) when is_number(lng) and lng >= -180.0 and lng <= 180.0
  defguard is_alt(alt) when is_number(alt)

  def datetime do
    quote do
      %{
        year: _,
        month: _,
        day: _,
        hour: _,
        minute: _,
        second: _,
        microsecond: _,
        time_zone: _,
        zone_abbr: _,
        utc_offset: _,
        std_offset: _,
        calendar: var!(calendar)
      }
    end
  end

  @doc false
  def naivedatetime do
    quote do
      %{
        year: _,
        month: _,
        day: _,
        hour: _,
        minute: _,
        second: _,
        microsecond: _,
        calendar: var!(calendar)
      }
    end
  end

  @doc false
  def date do
    quote do
      %{
        year: _,
        month: _,
        day: _,
        calendar: var!(calendar)
      }
    end
  end

  @doc false
  def time do
    quote do
      %{
        hour: _,
        minute: _,
        second: _,
        microsecond: _
      }
    end
  end
end
