defmodule Astro do
  @moduledoc """
  Functions for basic astronomical observations such
  as sunrise, sunset, solstice, equinox, moonrise,
  moonset and moon phase.

  """

  alias Astro.{Solar, Utils}

  @type longitude :: float()
  @type latitude :: float()
  @type degrees :: float()
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

      # Sunrise in Sydney, Australia
      Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
      {:ok, #DateTime<2019-12-04 05:37:00.000000+11:00 AEDT Australia/Sydney>}

      # Sunrise in Alert, Nanavut, Canada
      Astro.sunrise({-62.3481, 82.5018}, ~D[2019-12-04])
      {:error, :no_time}

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

      # Sunset in Sydney, Australia
      Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
      {:ok, #DateTime<2019-12-04 19:53:00.000000+11:00 AEDT Australia/Sydney>}

      # Sunset in Alert, Nanavut, Canada
      Astro.sunset({-62.3481, 82.5018}, ~D[2019-12-04])
      {:error, :no_time}

  """
  @spec sunset(location, date, options) ::
          {:ok, DateTime.t()} | {:error, :time_zone_not_found | :no_time}

  def sunset(location, date, options \\ default_options()) when is_list(options) do
    options = Keyword.put(options, :rise_or_set, :set)
    Solar.sun_rise_or_set(location, date, options)
  end

  @doc """
  Returns the datetime in UTC for either the
  March or September equinox.

  ## Arguments

  * `year` is the gregorian year for which the equinox is
    to be calculated

  * `event` is either `:march` or `:september` indicating
    which of the two annual equinox datetimes is required

  ## Returns

  * `{:ok, datetime}` representing the UTC datetime of
    the equinox

  ## Examples

      iex> Astro.equinox 2019, :march
      {:ok, ~U[2019-03-20 21:58:06Z]}
      iex> Astro.equinox 2019, :september
      {:ok, ~U[2019-09-23 07:49:30Z]}

  ## Notes

  This equinox calculation is expected to be accurate
  to within 2 minutes for the years 1000 CE to 3000 CE.

  An equinox is commonly regarded as the instant of
  time when the plane of Earth's equator passes through
  the center of the Sun. This occurs twice each year:
  around 20 March and 23 September.

  In other words, it is the moment at which the
  center of the visible Sun is directly above the equator.

  """
  @spec equinox(Calendar.year, :march | :september) :: {:ok, DateTime.t()}
  def equinox(year, event) when event in [:march, :september] and year in 1000..3000 do
    Solar.equinox_and_solstice(year, event)
  end

  @doc """
  Returns the datetime in UTC for either the
  June or December solstice.

  ## Arguments

  * `year` is the gregorian year for which the solstice is
    to be calculated

  * `event` is either `:june` or `:december` indicating
    which of the two annual solstice datetimes is required

  ## Returns

  * `{:ok, datetime}` representing the UTC datetime of
    the solstice

  ## Examples

      iex> Astro.solstice 2019, :december
      {:ok, ~U[2019-12-22 04:18:57Z]}
      iex> Astro.solstice 2019, :june
      {:ok, ~U[2019-06-21 15:53:45Z]}

  ## Notes

  This solstice calculation is expected to be accurate
  to within 2 minutes for the years 1000 CE to 3000 CE.

  A solstice is an event occurring when the Sun appears
  to reach its most northerly or southerly excursion
  relative to the celestial equator on the celestial
  sphere. Two solstices occur annually, around June 21
  and December 21.

  The seasons of the year are determined by
  reference to both the solstices and the equinoxes.

  The term solstice can also be used in a broader
  sense, as the day when this occurs. The day of a
  solstice in either hemisphere has either the most
  sunlight of the year (summer solstice) or the least
  sunlight of the year (winter solstice) for any place
  other than the Equator.

  Alternative terms, with no ambiguity as to which
  hemisphere is the context, are "June solstice" and
  "December solstice", referring to the months in
  which they take place every year.

  """
  @spec solstice(Calendar.year, :june | :december) :: {:ok, DateTime.t()}
  def solstice(year, event) when event in [:june, :december] and year in 1000..3000 do
    Solar.equinox_and_solstice(year, event)
  end

  @doc """
  Returns solar noon for a
  given date and location as
  a UTC datetime

  ## Arguments

  * `location` is the latitude, longitude and
    optionally elevation for the desired solar noon
    time. It can be expressed as:

    * `{lng, lat}` - a tuple with longitude and latitude
      as floating point numbers. **Note** the order of the
      arguments.
    * a `Geo.Point.t` struct to represent a location without elevation
    * a `Geo.PointZ.t` struct to represent a location and elevation

  * `date` is any date in the Gregorian
    calendar (for example, `Calendar.ISO`)

  ## Returns

  * a UTC datetime representing solar noon
    at the given location for the given date

  ## Example

      iex> Astro.solar_noon {151.20666584, -33.8559799094}, ~D[2019-12-06]
      {:ok, ~U[2019-12-06 01:45:42Z]}

  ## Notes

  Solar noon is the moment when the Sun passes a
  location's meridian and reaches its highest position
  in the sky. In most cases, it doesn't happen at 12 o'clock.

  At solar noon, the Sun reaches its
  highest position in the sky as it passes the
  local meridian.

  """
  @spec solar_noon(Astro.location(), Calendar.date()) :: {:ok, DateTime.t()}
  def solar_noon(location, date) do
    %Geo.PointZ{coordinates: {longitude, _, _}} =
      Utils.normalize_location(location)

    julian_day =  Astro.Time.julian_day_from_date(date)
    julian_centuries = Astro.Time.julian_centuries_from_julian_day(julian_day)

    julian_centuries
    |> Solar.solar_noon_utc(-longitude)
    |> Astro.Time.datetime_from_date_and_minutes(date)
  end

  @doc """
  Returns solar longitude for a
  given date. Solar longitude is used
  to identify the seasons.

  ## Arguments

  * `date` is any date in the Gregorian
    calendar (for example, `Calendar.ISO`)

  ## Returns

  * a `float` number of degrees between 0 and
    360 representing the solar longitude
    on `date`

  ## Examples

      iex> Astro.sun_apparent_longitude ~D[2019-03-21]
      0.08035853207991295
      iex> Astro.sun_apparent_longitude ~D[2019-06-22]
      90.32130455695378
      iex> Astro.sun_apparent_longitude ~D[2019-09-23]
      179.68691978440197
      iex> Astro.sun_apparent_longitude ~D[2019-12-23]
      270.83941087483504

  ## Notes

  Solar longitude (the ecliptic longitude of the sun)
  in effect describes the position of the earth in its
  orbit, being zero at the moment of the vernal
  equinox.

  Since it is based on how far the earth has moved
  in its orbit since the equinox, it is a measure of
  what time of the tropical year (the year of seasons)
  we are in, but without the inaccuracies of a calendar
  date, which is perturbed by leap years and calendar
  imperfections.

  """
  @spec sun_apparent_longitude(Calendar.date()) :: degrees()
  def sun_apparent_longitude(date) do
    date
    |> Astro.Time.julian_day_from_date()
    |> Astro.Time.julian_centuries_from_julian_day()
    |> Solar.sun_apparent_longitude()
  end

  @doc """
  Returns the number of hours of daylight for a given
  location on a given date.

  ## Arguments

  * `location` is the latitude, longitude and
    optionally elevation for the desired hours of
    daylight. It can be expressed as:

    * `{lng, lat}` - a tuple with longitude and latitude
      as floating point numbers. **Note** the order of the
      arguments.
    * a `Geo.Point.t` struct to represent a location without elevation
    * a `Geo.PointZ.t` struct to represent a location and elevation

  * `date` is any date in the Gregorian
    calendar (for example, `Calendar.ISO`)

  ## Returns

  * `{:ok, time}` where `time` is a `Time.t()`

  ## Examples

      iex> Astro.hours_of_daylight {151.20666584, -33.8559799094}, ~D[2019-12-07]
      {:ok, ~T[14:18:45]}

      # No sunset in summer
      iex> Astro.hours_of_daylight {-62.3481, 82.5018}, ~D[2019-06-07]
      {:ok, ~T[23:59:59]}

      # No sunrise in winter
      iex> Astro.hours_of_daylight {-62.3481, 82.5018}, ~D[2019-12-07]
      {:ok, ~T[00:00:00]}

  ## Notes

  In latitudes above the polar circles (approximately
  +/- 66.5631 degrees) there will be no hours of daylight
  in winter and 24 hours of daylight in summer.

  """
  @spec hours_of_daylight(Astro.location(), Calendar.date()) :: {:ok, Time.t()}
  def hours_of_daylight(location, date) do
    with {:ok, sunrise} <- sunrise(location, date),
         {:ok, sunset} <- sunset(location, date) do
      seconds_of_sunlight = DateTime.diff(sunset, sunrise)
      {hours, minutes, seconds} = Astro.Time.seconds_to_hms(seconds_of_sunlight)
      Time.new(hours, minutes, seconds)
    else
      {:error, :no_time} ->
        if no_daylight_hours?(location, date) do
          Time.new(0, 0, 0)
        else
          Time.new(23, 59, 59)
        end
    end
  end

  @polar_circle_latitude 66.5631
  defp no_daylight_hours?(location, date) do
    %Geo.PointZ{coordinates: {_longitude, latitude, _elevation}} =
      Utils.normalize_location(location)

    cond do
      latitude >= @polar_circle_latitude and date.month in 10..12 or date.month in 1..3 -> true
      latitude <= -@polar_circle_latitude and date.month in 4..9 -> true
      true -> false
    end
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
