defmodule Astro do
  @moduledoc """
  Functions for basic astronomical observations such
  as sunrise, sunset, solstice, equinox, moonrise,
  moonset and moon phase.

  """

  alias Astro.Solar

  @type longitude :: float()
  @type latitude :: float()
  @type location :: {longitude, latitude} | Geo.Point.t() | Geo.PointZ.t()
  @type date :: Calendar.date() | Calendar.naive_datetime() | Calendar.datetime()
  @type options :: keyword()

  @doc """
  Calculates the sunrise for a given location and date.

  Sunrise is the moment when the upper limb of
  the sun appears on the horizon in the morning.

  ## Arguments

  * `location` is the latitude, longitude and
    optionally elevation for the desired sunrise
    time. It can be expressed as:

    * `{lng, lat}` - a tuple with longitude and latitude
      as floating point numbers. **Note** the order of the
      arguments.
    * a `Geo.Point.t` struct to represent a location without elevation
    * a `Geo.PointZ.t` struct to represent a location and elevation

  * `date` is a `Date.t`, `NaiveDateTime.t` or `DateTime.t`
    to indicate the date of the year in which
    the sunrise time is required.

  * `options` is a keyword list of options.

  ## Options

  * `solar_elevation` represents the type of sunrise
    required. The default is `:geometric` which equates to
    a solar elevation of 90°. In this case the calulation
    also accounts for refraction and elevation to return a
    result which accords with the eyes perception. Other
    solar elevations are:

    * `:civil` representing a solar elevation of 96.0°. At this
      point the sun is just below the horizon so there is
      generally enough natural light to carry out most
      outdoor activities.

    * `:nautical` representing a solar elevation of 102.0°
      This is the point at which the horizon is just barely visible
      and the moon and stars can still be used for navigation.

    * `:astronomical`representing a solar elevation of 108.0°.
      This is the point beyond which astronomical observation
      becomes impractical.

    * Any floating point number representing the desired
      solar elevation.

  * `:time_zone` is the time zone to in which the sunrise
    is requested. The default is `:default` in which
    the sunrise time is reported in the time zone of
    the requested location. Any other time zone name
    supported by the option `:time_zone_database` is
    acceptabe.

  * `:time_zone_database` represents the module that
    implements the `Calendar.TimeZoneDatabase` behaviour.
    The default is `Tzdata.TimeZoneDatabase`.

  ## Returns

  * a `DateTime.t` representing the time of sunrise in the
    requested timzone at the requested location or

  * `{:error, :time_zone_not_found}` if the requested
    time zone is unknown

  * `{:error, :no_time}` if for the requested date
    and location there is no sunrise. This can occur at
    very high latitudes during summer and winter.

  ## Examples
  ```
    # Sunrise in Sydney, Australia
    Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
    {:ok, #DateTime<2019-12-04 05:37:00.000000+11:00 AEDT Australia/Sydney>}

    # Sunrise in Alert, Nanavut, Canada
    Astro.sunrise({-62.3481, 82.5018}, ~D[2019-12-04])
    {:error, :no_time}
  ```

  """
  @spec sunrise(location, date, options) ::
          {:ok, DateTime.t()} | {:error, :time_zone_not_found | :no_time}

  def sunrise(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :rise)
    Solar.sun_rise_or_set(location, date, options)
  end

  @doc """
  Calculates the sunset for a given location and date.

  Sunset is the moment when the upper limb of
  the sun disappears below the horizon in the evening.

  ## Arguments

  * `location` is the latitude, longitude and
    optionally elevation for the desired sunrise
    time. It can be expressed as:

    * `{lng, lat}` - a tuple with longitude and latitude
      as floating point numbers. **Note** the order of the
      arguments.
    * a `Geo.Point.t` struct to represent a location without elevation
    * a `Geo.PointZ.t` struct to represent a location and elevation

  * `date` is a `Date.t`, `NaiveDateTime.t` or `DateTime.t`
    to indicate the date of the year in which
    the sunset time is required.

  * `options` is a keyword list of options.

  ## Options

  * `solar_elevation` represents the type of sunset
    required. The default is `:geometric` which equates to
    a solar elevation of 90°. In this case the calulation
    also accounts for refraction and elevation to return a
    result which accords with the eyes perception. Other
    solar elevations are:

    * `:civil` representing a solar elevation of 96.0°. At this
      point the sun is just below the horizon so there is
      generally enough natural light to carry out most
      outdoor activities.

    * `:nautical` representing a solar elevation of 102.0°
      This is the point at which the horizon is just barely visible
      and the moon and stars can still be used for navigation.

    * `:astronomical`representing a solar elevation of 108.0°.
      This is the point beyond which astronomical observation
      becomes impractical.

    * Any floating point number representing the desired
      solar elevation.

  * `:time_zone` is the time zone to in which the sunset
    is requested. The default is `:default` in which
    the sunset time is reported in the time zone of
    the requested location. Any other time zone name
    supported by the option `:time_zone_database` is
    acceptabe.

  * `:time_zone_database` represents the module that
    implements the `Calendar.TimeZoneDatabase` behaviour.
    The default is `Tzdata.TimeZoneDatabase`.

  ## Returns

  * a `DateTime.t` representing the time of sunset in the
    requested time zone at the requested location or

  * `{:error, :time_zone_not_found}` if the requested
    time zone is unknown

  * `{:error, :no_time}` if for the requested date
    and location there is no sunset. This can occur at
    very high latitudes during summer and winter.

  ## Examples
  ```
    # Sunset in Sydney, Australia
    Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
    {:ok, #DateTime<2019-12-04 19:53:00.000000+11:00 AEDT Australia/Sydney>}

    # Sunset in Alert, Nanavut, Canada
    Astro.sunset({-62.3481, 82.5018}, ~D[2019-12-04])
    {:error, :no_time}
  ```

  """
  @spec sunset(location, date, options) ::
          {:ok, DateTime.t()} | {:error, :time_zone_not_found | :no_time}

  def sunset(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :set)
    Solar.sun_rise_or_set(location, date, options)
  end

  @doc false
  def default_options do
    [
      solar_elevation: Solar.solar_elevation(:geometric),
      time_zone: :default,
      time_zone_database: Tzdata.TimeZoneDatabase
    ]
  end
end
