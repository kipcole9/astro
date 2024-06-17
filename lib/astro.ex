defmodule Astro do
  @moduledoc """
  Functions for basic astronomical observations such
  as sunrise, sunset, solstice, equinox, moonrise,
  moonset and moon phase.

  """

  alias Astro.{Solar, Lunar, Location, Time, Math, Guards}

  import Astro.Math, only: [
    sin: 1,
    cos: 1,
    atan_r: 2,
    tan: 1,
    mod: 2,
    to_degrees: 1
  ]

  import Astro.Solar, only: [
    obliquity_correction: 1
  ]

  @type longitude :: float()
  @type latitude :: float()
  @type altitude :: float()
  @type degrees :: float()

  @type angle() :: number()
  @type meters() :: number()
  @type phase() :: angle()

  @type location :: {longitude, latitude} | Geo.Point.t() | Geo.PointZ.t()
  @type date :: Calendar.date() | Calendar.datetime()
  @type options :: keyword()

  defguard is_lunar_phase(phase) when phase >= 0.0 and phase <= 360.0

  @doc """
  Returns a tuple `{azimuth, altitude}` for a given
  date time and location.

  ## Arguments

  * `location` is the latitude, longitude and
    optionally elevation for the desired sunrise
    azimuth and altitude. It can be expressed as:

    * `{lng, lat}` - a tuple with longitude and latitude
      as floating point numbers. **Note** the order of the
      arguments.
    * a `Geo.Point.t` struct to represent a location without elevation
    * a `Geo.PointZ.t` struct to represent a location and elevation

  * `date_time` is a `DateTime` any struct that meets the
    requirements of `t:Calendar.datetime`.

  ## Returns

  * a tuple of the format `{azimith, altitude}` which are
    expressed in float degrees.

  ## Example

      iex> {:ok, date_time} = DateTime.new(~D[2023-05-17], ~T[12:47:00], "Australia/Sydney")
      iex> location = {151.1637781, -33.5145852}
      iex> {_azimuth, _altitude} = Astro.sun_azimuth_elevation(location, date_time)

  """

  # Use https://midcdmz.nrel.gov/solpos/spa.html for validation
  # current implementation is approx 1 degree at variance with
  # that calculator.

  @doc since: "0.11.0"
  @spec sun_azimuth_elevation(location(), Calendar.datetime()) :: {azimuth :: float, altitude :: float}

  def sun_azimuth_elevation(location, unquote(Guards.datetime()) = date_time) do
    _ = calendar

    %Geo.PointZ{coordinates: {right_ascension, declination, _distance}} =
      sun_position_at(date_time)

    %Geo.PointZ{coordinates: {_longitude, latitude, _altitude}} =
      Location.normalize_location(location)

    local_sidereal_time =
      Time.local_sidereal_time(location, date_time)

    hour_angle =
      mod(local_sidereal_time - right_ascension, 360.0)

    altitude =
      :math.asin(sin(declination) * sin(latitude) + cos(declination) * cos(latitude) * cos(hour_angle))
      |> to_degrees

    a =
      :math.acos((sin(declination) - sin(altitude) * sin(latitude)) / (cos(altitude) * cos(latitude)))
      |> to_degrees()

    azimuth =
      if sin(hour_angle) < 0.0, do: a, else: 360.0 - a

    {azimuth, altitude}
  end

  @doc """
  Returns a `t:Geo.PointZ` containing
  the right ascension and declination of
  the sun at a given date or date time.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  ## Returns

  * a `t:Geo.PointZ` struct with coordinates
    `{right_ascension, declination, distance}` with properties
    `%{reference: :celestial, object: :sun}`.
    `distance` is in meters.

  ## Example

      iex> Astro.sun_position_at(~D[1992-10-13])
      %Geo.PointZ{
        coordinates: {-161.6185428539835, -7.785325031528879, 149169604711.3518},
        properties: %{object: :sun, reference: :celestial},
        srid: nil
      }

  """
  @doc since: "0.6.0"
  @spec sun_position_at(date()) :: Geo.PointZ.t()

  def sun_position_at(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Solar.solar_position()
    |> convert_distance_to_m()
    |> Location.normalize_location()
    |> Map.put(:properties, %{reference: :celestial, object: :sun})
  end

  def sun_position_at(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Solar.solar_position()
    |> convert_distance_to_m()
    |> Location.normalize_location()
    |> Map.put(:properties, %{reference: :celestial, object: :sun})
  end

  defp convert_distance_to_m({lng, lat, alt}) do
    {lng, lat, Math.au_to_m(alt)}
  end

  @doc """
  Returns a `t:Geo.PointZ` containing
  the right ascension and declination of
  the moon at a given date or date time.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  ## Returns

  * a `t:Geo.PointZ` struct with coordinates
    `{right_ascension, declination, distance}` with properties
    `%{reference: :celestial, object: :moon}`
    `distance` is in meters.

  ## Example

      iex> Astro.moon_position_at(~D[1992-04-12]) |> Astro.Location.round(6)
      %Geo.PointZ{
        coordinates: {134.697888, 13.765243, 5.511320224169038e19},
        properties: %{object: :moon, reference: :celestial},
        srid: nil
      }

  """
  @doc since: "0.6.0"
  @spec moon_position_at(date()) :: Geo.PointZ.t()

  def moon_position_at(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.lunar_position()
    |> convert_distance_to_m()
    |> Location.normalize_location()
    |> Map.put(:properties, %{reference: :celestial, object: :moon})
  end

  def moon_position_at(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.lunar_position()
    |> convert_distance_to_m()
    |> Location.normalize_location()
    |> Map.put(:properties, %{reference: :celestial, object: :moon})
  end

  @doc """
  Returns the illumination of the moon
  as a fraction for a given date or date time.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  ## Returns

  * a `float` value between `0.0` and `1.0`
    representing the fractional illumination of
    the moon.

  ## Example

      iex> Astro.illuminated_fraction_of_moon_at(~D[2017-03-16])
      0.8884442367681415

      iex> Astro.illuminated_fraction_of_moon_at(~D[1992-04-12])
      0.6786428237168787

  """
  @doc since: "0.6.0"
  @spec illuminated_fraction_of_moon_at(date()) :: number()

  def illuminated_fraction_of_moon_at(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.illuminated_fraction_of_moon()
  end

  def illuminated_fraction_of_moon_at(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.illuminated_fraction_of_moon()
  end

  @doc """
  Returns the date time of the new
  moon before a given date or date time.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  ## Returns

  * `{:ok, date_time}` at which the new moon occurs or

  * `{:error, {module, reason}}`

  ## Example

      iex> Astro.date_time_new_moon_before ~D[2021-08-23]
      {:ok, ~U[2021-08-08 13:49:07.000000Z]}

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_before(date()) ::
    {:ok, Calendar.datetime()}, {:error, {module(), String.t}}

  def date_time_new_moon_before(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.date_time_new_moon_before()
    |> Time.date_time_from_moment()
  end

  def date_time_new_moon_before(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.date_time_new_moon_before()
    |> Time.date_time_from_moment()
  end

  @doc """
  Returns the date time of the new
  moon at or after a given date or
  date time.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  ## Returns

  * `{:ok, date_time}` at which the new moon occurs or

  * `{:error, {module, reason}}`

  ## Example

      iex> Astro.date_time_new_moon_at_or_after ~D[2021-08-23]
      {:ok, ~U[2021-09-07 00:50:43.000000Z]}

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_at_or_after(date) ::
    {:ok, Calendar.datetime()}, {:error, {module(), String.t}}

  def date_time_new_moon_at_or_after(unquote(Guards.datetime()) = datetime) do
    _ = calendar

    datetime
    |> Time.date_time_to_moment()
    |> Lunar.date_time_new_moon_at_or_after()
    |> Time.date_time_from_moment()
  end

  def date_time_new_moon_at_or_after(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.date_time_new_moon_at_or_after()
    |> Time.date_time_from_moment()
  end

  @doc """
  Returns the lunar phase as a
  float number of degrees at a given
  date or date time.

  ## Arguments

  * `date_time` is a `DateTime`, `Date` or
    a `moment` which is a float number of days
    since `0000-01-01`

  ## Returns

  * the lunar phase as a float number of
    degrees.

  ## Example

      iex> Astro.lunar_phase_at ~U[2021-08-22 12:01:02.170362Z]
      180.00001498208536

      iex> Astro.lunar_phase_at(~U[2021-07-10 01:18:25.422335Z])
      0.021567106773019873

  """

  @doc since: "0.5.0"
  @spec lunar_phase_at(date()) :: phase()

  def lunar_phase_at(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.lunar_phase_at()
  end

  def lunar_phase_at(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.lunar_phase_at()
  end

  @doc """
  Returns the moon phase as a UTF8 binary
  representing an emoji of the moon phase.

  ## Arguments

  * `phase` is a moon phase between `0.0` and `360.0`

  ## Returns

  * A single grapheme string representing the [Unicode
    moon phase emoji](https://unicode-table.com/en/sets/moon/)

  ## Examples

      iex> Astro.lunar_phase_emoji 0
      "🌑"
      iex> Astro.lunar_phase_emoji 45
      "🌒"
      iex> Astro.lunar_phase_emoji 90
      "🌓"
      iex> Astro.lunar_phase_emoji 135
      "🌔"
      iex> Astro.lunar_phase_emoji 180
      "🌕"
      iex> Astro.lunar_phase_emoji 245
      "🌖"
      iex> Astro.lunar_phase_emoji 270
      "🌗"
      iex> Astro.lunar_phase_emoji 320
      "🌘"
      iex> Astro.lunar_phase_emoji 360
      "🌑"

      iex> ~U[2021-08-22 12:01:02.170362Z]
      ...> |> Astro.lunar_phase_at()
      ...> |> Astro.lunar_phase_emoji()
      "🌕"

  """
  @emoji_base 0x1f310
  @emoji_phase_count 8
  @emoji_phase (360.0 / @emoji_phase_count)

  @spec lunar_phase_emoji(phase()) :: String.t()
  def lunar_phase_emoji(360) do
    lunar_phase_emoji(0)
  end

  def lunar_phase_emoji(phase) when is_lunar_phase(phase) do
    offset = ceil(phase / @emoji_phase + 0.5)
    :unicode.characters_to_binary([offset + @emoji_base])
  end

  @doc """
  Returns the date time of a given
  lunar phase at or before a given
  date time or date.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0` and
    `3660`

  ## Returns

  * `{:ok, date_time}` at which the phase occurs or

  * `{:error, {module, reason}}`

  ## Example

      iex> Astro.date_time_lunar_phase_at_or_before(~D[2021-08-01], Astro.Lunar.new_moon())
      {:ok, ~U[2021-07-10 01:15:33.000000Z]}

  """

  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_before(date(), Astro.phase()) ::
      {:ok, Calendar.datetime()}, {:error, {module(), String.t}}

  def date_time_lunar_phase_at_or_before(unquote(Guards.datetime()) = date_time, phase) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.date_time_lunar_phase_at_or_before(phase)
    |> Time.date_time_from_moment()
  end

  def date_time_lunar_phase_at_or_before(unquote(Guards.date()) = date, phase) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.date_time_lunar_phase_at_or_before(phase)
    |> Time.date_time_from_moment()
  end

  @doc """
  Returns the date time of a given
  lunar phase at or after a given
  date time or date.

  ## Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0.0` and
    `360.0`

  ## Returns

  * `{:ok, date_time}` at which the phase occurs or

  * `{:error, {module, reason}}`

  ## Example

      iex> Astro.date_time_lunar_phase_at_or_after(~D[2021-08-01], Astro.Lunar.full_moon())
      {:ok, ~U[2021-08-22 12:01:02.000000Z]}

  """

  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_after(date(), Astro.phase()) ::
    {:ok, Calendar.datetime()}, {:error, {module(), String.t}}

  def date_time_lunar_phase_at_or_after(unquote(Guards.datetime()) = date_time, phase) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.date_time_lunar_phase_at_or_after(phase)
    |> Time.date_time_from_moment()
  end

  def date_time_lunar_phase_at_or_after(unquote(Guards.date()) = date, phase) do
    _ = calendar

    date
    |> Date.to_gregorian_days()
    |> Lunar.date_time_lunar_phase_at_or_after(phase)
    |> Time.date_time_from_moment()
  end

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
    * a `t:Geo.Point.t/0` struct to represent a location without elevation
    * a `t:Geo.PointZ.t/0` struct to represent a location and elevation

  * `date` is a `t:Date`, `t:NaiveDateTime` or `t:DateTime`
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

      * `:astronomical` representing a solar elevation of 108.0°.
        This is the point beyond which astronomical observation
        becomes impractical.

      * Any floating point number representing the desired
        solar elevation.

  * `:time_zone` is the time zone in which the sunrise
    is requested. The default is `:default` in which
    the sunrise time is reported in the time zone of
    the requested location. `:utc` can be specified or any
    other time zone name supported by the option
    `:time_zone_database` is acceptabe.

  * `:time_zone_database` represents the module that
    implements the `Calendar.TimeZoneDatabase` behaviour.
    The default is the configured Elixir time zone database or
    one of `Tzdata.TimeZoneDatabase` or `Tz.TimeZoneDatabase`
    depending upon which dependency is configured.

  * `:time_zone_resolver` is a 1-arity function that resolves the
    time zone name for a given location. The function will receive
    a `%Geo.Point{cordinates: {lng, lat}}` struct and is expected to
    return either `{:ok, time_zone_name}` or `{:error, :time_zone_not_found}`.
    The default is `TzWorld.timezone_at/1` if `:tz_world` is
    configured.

  ## Returns

  * a `t:DateTime.t/0` representing the time of sunrise in the
    requested timzone at the requested location.

  * `{:error, :time_zone_not_found}` if the requested
    time zone is unknown.

  * `{:error, :time_zone_not_resolved}` if it is not possible
    to resolve a time zone name from the location. This can happen
    if `:tz_world` is not configured as a dependency and no
    `:time_zone_resolver` option is specified.

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
          {:ok, DateTime.t()} | {:error, :time_zone_not_found | :time_zone_not_resolved | :no_time}

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

  * `date` is a `t:Date`, `t:NaiveDateTime` or `t:DateTime`
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

  * `:time_zone` is the time zone in which the sunset
    is requested. The default is `:default` in which
    the sunrise time is reported in the time zone of
    the requested location. `:utc` can be specified or any
    other time zone name supported by the option
    `:time_zone_database` is acceptabe.

  * `:time_zone_database` represents the module that
    implements the `Calendar.TimeZoneDatabase` behaviour.
    The default is the configured Elixir time zone database or
    one of `Tzdata.TimeZoneDatabase` or `Tz.TimeZoneDatabase`
    depending upon which dependency is configured.

  * `:time_zone_resolver` is a 1-arity function that resolves the
    time zone name for a given location. The function will receive
    a `%Geo.Point{cordinates: {lng, lat}}` struct and is expected to
    return either `{:ok, time_zone_name}` or `{:error, :time_zone_not_found}`.
    The default is `TzWorld.timezone_at/1` if `:tz_world` is
    configured.

  ## Returns

  * a `t:DateTime.t/0` representing the time of sunset in the
    requested time zone at the requested location.

  * `{:error, :time_zone_not_found}` if the requested
    time zone is unknown.

  * `{:error, :time_zone_not_resolved}` if it is not possible
    to resolve a time zone name from the location. This can happen
    if `:tz_world` is not configured as a dependency and no
    `:time_zone_resolver` option is specified.

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
          {:ok, DateTime.t()} | {:error, :time_zone_not_found | :time_zone_not_resolved | :no_time}

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
  @spec equinox(Calendar.year(), :march | :september) :: {:ok, DateTime.t()}
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
  @spec solstice(Calendar.year(), :june | :december) :: {:ok, DateTime.t()}
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
    %Geo.PointZ{coordinates: {longitude, _, _}} = Location.normalize_location(location)

    julian_day = Time.julian_day_from_date(date)
    julian_centuries = Time.julian_centuries_from_julian_day(julian_day)

    julian_centuries
    |> Solar.solar_noon_utc(-longitude)
    |> Time.datetime_from_date_and_minutes(date)
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
    |> Time.julian_day_from_date()
    |> Time.julian_centuries_from_julian_day()
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
  @spec hours_of_daylight(Astro.location(), Calendar.date()) :: {:ok, Elixir.Time.t()}
  def hours_of_daylight(location, date) do
    with {:ok, sunrise} <- sunrise(location, date),
         {:ok, sunset} <- sunset(location, date) do
      seconds_of_sunlight = DateTime.diff(sunset, sunrise)
      {hours, minutes, seconds} = Time.seconds_to_hms(seconds_of_sunlight)
      Elixir.Time.new(hours, minutes, seconds)
    else
      {:error, :no_time} ->
        if no_daylight_hours?(location, date) do
          Elixir.Time.new(0, 0, 0)
        else
          Elixir.Time.new(23, 59, 59)
        end
    end
  end

  @polar_circle_latitude 66.5631
  defp no_daylight_hours?(location, date) do
    %Geo.PointZ{coordinates: {_longitude, latitude, _elevation}} =
      Location.normalize_location(location)

    cond do
      (latitude >= @polar_circle_latitude and date.month in 10..12) or date.month in 1..3 -> true
      latitude <= -@polar_circle_latitude and date.month in 4..9 -> true
      true -> false
    end
  end

  @doc """

  beta and lambda in degrees
  """
  @spec declination(Time.moment(), Astro.angle(), Astro.angle()) :: Astro.angle()
  def declination(t, beta, lambda) do
    julian_centuries = Time.julian_centuries_from_moment(t)
    epsilon = obliquity_correction(julian_centuries)

    :math.asin(sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda))
    |> Math.to_degrees
    |> mod(360.0)
  end

  @doc """
  beta and lambda in degrees
  """
  @spec right_ascension(Time.moment(), Astro.angle(), Astro.angle()) :: Astro.angle()
  def right_ascension(t, beta, lambda) do
    julian_centuries = Time.julian_centuries_from_moment(t)
    epsilon = obliquity_correction(julian_centuries)

    # omega = (125.04 - (1_934.136 * julian_centuries))
    # adjusted_epsilon = (epsilon + 0.00256 * cos(omega))

    atan_r(sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon), cos(lambda))
    |> Math.to_degrees()
  end

  @doc false
  def default_options do
    default_time_zone_db =
      cond do
        Application.get_env(:elixir, :time_zone_database) -> Application.get_env(:elixir, :time_zone_database)
        Code.ensure_loaded?(Tzdata.TimeZoneDatabase) -> Tzdata.TimeZoneDatabase
        Code.ensure_loaded?(Tz.TimeZoneDatabase) -> Tz.TimeZoneDatabase
      end

    [
      solar_elevation: Solar.solar_elevation(:geometric),
      time_zone: :default,
      time_zone_database: default_time_zone_db
    ]
  end

end
