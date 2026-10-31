defmodule Astro do
  @moduledoc """
  High-level API for common astronomical observations.

  This module is the primary public interface for the Astro library. It
  provides sunrise and sunset, moonrise and moonset, equinoxes and
  solstices, lunar phases, crescent visibility, and the positions of the
  sun and moon. Functions accept standard Elixir dates and date times.
  Those that can fail, such as the rise and set times, return
  `{:ok, value}` or `{:error, reason}`. The positions and phases, which
  cannot fail, return their value directly.

  For lower-level access see `Astro.Solar`, `Astro.Lunar`, `Astro.Time`,
  `Astro.Earth` and `Astro.Ephemeris`.

  How accurate the results are, inside and outside the JPL ephemeris and
  far from the present, is described in the [accuracy guide](accuracy.md).

  ## Specifying a location

  A location is a `{longitude, latitude}` tuple (note the order, which
  matches `Geo.Point`), a `Geo.Point` struct, or a `Geo.PointZ` struct
  that also carries an elevation in metres.

  * Longitude is positive east and negative west, in degrees.

  * Latitude is positive north and negative south, in degrees.

  ## Time zone resolution

  The rise and set functions (`sunrise/3`, `sunset/3`, `moonrise/3` and
  `moonset/3`) return a `DateTime` in the local time zone of the
  location, resolved with `TzWorld` when it is a dependency. These
  options override that:

  * `:time_zone` is a time zone name, `:utc`, or `:default` to resolve
    the time zone from the location.

  * `:time_zone_database` is the time zone database module, such as
    `Tz.TimeZoneDatabase`.

  * `:time_zone_resolver` is a 1-arity function that receives a
    `Geo.Point` and returns `{:ok, time_zone_name}`.

  ## Function groups

  ### Solar

  * `sunrise/3` and `sunset/3` return the local times of sunrise and
    sunset.

  * `solar_noon/2` returns the solar noon for a location and date.

  * `hours_of_daylight/2` and `duration_of_daylight/2` return the length
    of the day.

  * `sun_position_at/1` returns the sun's right ascension, declination
    and distance.

  * `sun_azimuth_elevation/2` returns the sun's azimuth and elevation at
    a date time.

  * `sun_apparent_longitude/1` returns the sun's apparent ecliptic
    longitude.

  ### Lunar

  * `moonrise/3` and `moonset/3` return the local times of moonrise and
    moonset.

  * `moon_position_at/1` returns the moon's right ascension, declination
    and distance.

  * `illuminated_fraction_of_moon_at/1` returns the fraction of the moon
    that is illuminated.

  * `lunar_phase_at/1` returns the phase angle, from 0° to 360°.

  * `lunar_phase_emoji/1` returns the emoji for a phase angle.

  ### New moon and phase searches

  * `date_time_new_moon_before/1`, `date_time_new_moon_at_or_after/1` and
    `date_time_new_moon_nearest/1` find new moons.

  * `date_time_lunar_phase_at_or_before/2` and
    `date_time_lunar_phase_at_or_after/2` find any phase.

  ### Crescent visibility

  * `new_visible_crescent/4` predicts the visibility of the new crescent
    moon.

  ### Equinoxes and solstices

  * `equinox/3` returns the March or September equinox.

  * `solstice/3` returns the June or December solstice.

  """

  alias Astro.{Guards, Location, Lunar, Math, Solar, Time}

  import Astro.Math,
    only: [
      sin: 1,
      cos: 1,
      mod: 2,
      to_degrees: 1
    ]

  @type longitude :: float()
  @type latitude :: float()
  @type altitude :: float()
  @type degrees :: float()
  @type radians :: float()

  @type angle() :: number()
  @type meters() :: number()
  @type astronomical_units() :: number()
  @type kilometers() :: number()
  @type phase() :: angle()

  @type location ::
          {longitude, latitude}
          | {longitude, latitude, altitude}
          | Geo.Point.t()
          | Geo.PointZ.t()
  @type date :: Calendar.date() | Calendar.datetime()
  @type options :: keyword()

  @seconds_per_day 86_400

  @emoji_base 0x1F310
  @emoji_phase_count 8
  @emoji_phase 360.0 / @emoji_phase_count

  # Selects the preferred time zone database at compile time based on
  # which implementation (`:tz` or `:tzdata`) is loaded — `:tz` is
  # preferred when both are (it is also what astro's own dev and test
  # environments use; `:tzdata` is not a dependency but is detected
  # when a consumer loads it). The `:elixir` `:time_zone_database`
  # application config still takes precedence at runtime — see
  # `default_options/0`.
  @compile_time_time_zone_db (cond do
                                Code.ensure_loaded?(Tz.TimeZoneDatabase) ->
                                  Tz.TimeZoneDatabase

                                Code.ensure_loaded?(Tzdata.TimeZoneDatabase) ->
                                  Tzdata.TimeZoneDatabase

                                true ->
                                  nil
                              end)

  @doc """
  Guards that a value is a lunar phase angle.

  ### Arguments

  * `phase` is the value to test.

  ### Returns

  * `true` if `phase` is a number from 0.0 to 360.0 inclusive, otherwise
    `false`.

  ### Examples

      iex> require Astro
      iex> Astro.is_lunar_phase(90.0)
      true
      iex> Astro.is_lunar_phase(400.0)
      false

  """
  defguard is_lunar_phase(phase) when phase >= 0.0 and phase <= 360.0

  @doc """
  Returns the Sun's azimuth and elevation as seen from a location at a
  date time.

  Azimuth and elevation are the Sun's horizontal coordinates: its
  direction around the horizon and its height above it. They are
  calculated from the Sun's apparent right ascension α and
  declination δ (see `sun_position_at/1`) and the local hour angle
  H, the local apparent sidereal time less α, by the transformation
  of Meeus, *Astronomical Algorithms*, chapter 13:

      tan A = sin H / (cos H sin φ − tan δ cos φ)
      sin h = sin φ sin δ + cos φ cos δ cos H

  where φ is the observer's latitude, A is measured from the south
  and is returned measured from the north, and h is the elevation.

  The position is geocentric and airless: it omits the Sun's parallax
  (at most 8.8″) and atmospheric refraction, which raises the Sun by
  about 34′ at the horizon and by less than 1′ above an elevation of
  45°.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0`.
    Longitude comes first. An elevation does not change the result.

  * `date_time` is a `t:DateTime.t/0`, or any map that meets
    `t:Calendar.datetime/0`.

  ### Returns

  * `{azimuth, elevation}` in degrees. Azimuth is measured clockwise
    from north, from 0° to 360°, and elevation above the horizon, from
    −90° to 90°.

  ### Accuracy

  Inside the loaded JPL ephemeris the Sun's apparent position is
  accurate to a small fraction of an arcsecond, so the result is
  limited by what it leaves out: for the reference case of NREL's
  solar position algorithm (Golden, Colorado, 2003-10-17 19:30:30
  UTC) it agrees to 0.05″ in azimuth and is 0.87′ lower, the
  refraction NREL includes.
  Outside the ephemeris the analytical series agree with JPL to 0.8″
  RMS in azimuth and 0.6″ in elevation. The [accuracy guide](accuracy.md)
  gives the details.

  ### Examples

      iex> {azimuth, elevation} =
      ...>   Astro.sun_azimuth_elevation({151.20666584, -33.8559799094}, ~U[2019-12-04 02:00:00Z])
      iex> {Float.round(azimuth, 4), Float.round(elevation, 4)}
      {343.3379, 77.8643}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 12 (sidereal time) and chapter 13 (transformation of
    coordinates).

  * Ibrahim Reda and Afshin Andreas, [Solar position algorithm for
    solar radiation applications](https://doi.org/10.1016/j.solener.2003.12.003),
    *Solar Energy* 76 (2004), 577–589.

  * [Horizontal coordinate system](https://en.wikipedia.org/wiki/Horizontal_coordinate_system),
    Wikipedia.

  """
  @doc since: "0.11.0"
  @spec sun_azimuth_elevation(location(), Calendar.datetime()) ::
          {azimuth :: float, altitude :: float}

  def sun_azimuth_elevation(location, unquote(Guards.datetime()) = date_time) do
    _ = calendar

    moment = Time.date_time_to_moment(date_time)
    {right_ascension, declination, _distance} = Solar.solar_position(moment)

    azimuth_elevation(location, moment, right_ascension, declination)
  end

  # Meeus, Astronomical Algorithms, equations 13.5 and 13.6. Equation 13.5
  # measures azimuth from the south; adding 180° measures it from the north.
  defp azimuth_elevation(location, moment, right_ascension, declination) do
    %Geo.PointZ{coordinates: {longitude, latitude, _altitude}} =
      Location.normalize_location(location)

    local_sidereal_time = Time.apparent_sidereal_from_moment(moment) + longitude
    hour_angle = local_sidereal_time - right_ascension

    azimuth_from_south =
      :math.atan2(
        sin(hour_angle),
        cos(hour_angle) * sin(latitude) - Math.tan(declination) * cos(latitude)
      )

    sin_elevation =
      sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hour_angle)

    azimuth = mod(to_degrees(azimuth_from_south) + 180.0, 360.0)
    elevation = to_degrees(:math.asin(sin_elevation))

    {azimuth, elevation}
  end

  @doc """
  Returns the Sun's apparent right ascension, declination and distance
  at a date or date time.

  This is the Sun's apparent geocentric position: where it is seen
  from the centre of the Earth, referred to the true equator and
  equinox of the date. Right ascension is measured eastward along the
  celestial equator from the equinox and declination north of the
  equator.

  Where the loaded JPL DE440s ephemeris covers the moment, the
  Earth-to-Sun vector is read from it at the moment less the light
  time, corrected for aberration, and rotated from the ICRF to the
  true equator of date by IAU 1976 precession and IAU 1980 nutation.
  Elsewhere the Sun's longitude comes from the 49-term series of
  Bretagnon and Simon, with aberration and nutation added, and is
  converted to right ascension and declination with the true
  obliquity of the ecliptic (Meeus, *Astronomical Algorithms*,
  chapter 13).

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`. A date is
    taken at 00:00 UTC.

  ### Returns

  * a `t:Geo.PointZ.t/0` struct with coordinates
    `{right_ascension, declination, distance}` with properties
    `%{reference: :celestial, object: :sun}`. Right ascension is in
    degrees from −180° to 180°, declination in degrees and
    `distance` in metres.

  ### Accuracy

  Inside the ephemeris the reduction reproduces Meeus's
  full-precision example 25.b to 0.2″. Outside it the series agree
  with JPL over 1900–2100 to 0.76″ RMS in right ascension and 0.50″ in
  declination (2.2″ and 1.3″ at most), and to 4,300 km in distance.
  Far from the present the series drift, and ΔT, which places the
  moment in Terrestrial Time, becomes uncertain by minutes to hours;
  the [accuracy guide](accuracy.md) gives the details.

  ### Examples

      iex> %Geo.PointZ{coordinates: {right_ascension, declination, distance}, properties: properties} =
      ...>   Astro.sun_position_at(~D[1992-10-13])
      iex> {Float.round(right_ascension, 6), Float.round(declination, 6), round(distance)}
      {-161.621245, -7.784069, 149240324715}
      iex> properties
      %{object: :sun, reference: :celestial}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 25 (solar coordinates).

  * Ryan S. Park and others, [The JPL Planetary and Lunar Ephemerides
    DE440 and DE441](https://doi.org/10.3847/1538-3881/abd414),
    *The Astronomical Journal* 161 (2021), 105.

  * Edward M. Reingold and Nachum Dershowitz, *Calendrical
    Calculations*, for the series of Bretagnon and Simon.

  * [Position of the Sun](https://en.wikipedia.org/wiki/Position_of_the_Sun),
    Wikipedia.

  """
  @doc since: "0.6.0"
  @spec sun_position_at(date()) :: Geo.PointZ.t()

  def sun_position_at(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> sun_position_at_moment()
  end

  def sun_position_at(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Time.date_time_to_moment()
    |> sun_position_at_moment()
  end

  defp sun_position_at_moment(moment) do
    moment
    |> Solar.solar_position()
    |> convert_distance_to_m()
    |> Location.normalize_location()
    |> Map.put(:properties, %{reference: :celestial, object: :sun})
  end

  defp convert_distance_to_m({lng, lat, alt}) do
    {lng, lat, Math.au_to_m(alt)}
  end

  @doc """
  Returns a `t:Geo.PointZ.t/0` containing
  the right ascension and declination of
  the moon at a given date or date time.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  ### Returns

  * a `t:Geo.PointZ.t/0` struct with coordinates
    `{right_ascension, declination, distance}` with properties
    `%{reference: :celestial, object: :moon}`.
    `distance` is in meters.

  ### Examples

      iex> Astro.moon_position_at(~D[1992-04-12]) |> Astro.Location.round(6)
      %Geo.PointZ{
        coordinates: {134.697251, 13.765115, 368404879.697206},
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
    |> moon_position_at_moment()
  end

  def moon_position_at(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Time.date_time_to_moment()
    |> moon_position_at_moment()
  end

  defp moon_position_at_moment(moment) do
    moment
    |> Lunar.lunar_position()
    |> Location.normalize_location()
    |> Map.put(:properties, %{reference: :celestial, object: :moon})
  end

  @doc """
  Returns the illumination of the moon
  as a float for a given date or date time.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  ### Returns

  * a `float` value between `0.0` and `1.0`
    representing the fractional illumination of
    the moon.

  ### Examples

      iex> fraction = Astro.illuminated_fraction_of_moon_at(~D[2017-03-16])
      iex> Float.round(fraction, 4)
      0.8884

      iex> fraction = Astro.illuminated_fraction_of_moon_at(~D[1992-04-12])
      iex> Float.round(fraction, 4)
      0.6786

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
    |> Time.date_time_to_moment()
    |> Lunar.illuminated_fraction_of_moon()
  end

  @doc """
  Returns the date time of the new
  moon before a given date or date time.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  ### Returns

  * `{:ok, date_time}`, the UTC `t:DateTime.t/0` at which the new
    moon occurs.

  Raises `ArgumentError` for a date more than 50,000 years from J2000,
  where the new moons can no longer be told apart reliably.

  ### Examples

      iex> Astro.date_time_new_moon_before(~D[2021-08-23])
      {:ok, ~U[2021-08-08 13:50:08.051937Z]}

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_before(date()) :: {:ok, DateTime.t()}

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
    |> Time.date_time_to_moment()
    |> Lunar.date_time_new_moon_before()
    |> Time.date_time_from_moment()
  end

  # The date-time clause of `date_time_new_moon_before/1` was once defined
  # under this name, which then carried that function's documentation.
  @doc false
  @deprecated "Use Astro.date_time_new_moon_before/1 instead"
  @spec date_time_new_moon_at_or_before(date()) :: {:ok, DateTime.t()}
  def date_time_new_moon_at_or_before(date_time) do
    date_time_new_moon_before(date_time)
  end

  @doc """
  Returns the date time of the new
  moon nearest to a given date or date time.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  ### Returns

  * `{:ok, date_time}`, the UTC `t:DateTime.t/0` at which the new
    moon occurs.

  ### Examples

      iex> Astro.date_time_new_moon_nearest(~D[2021-08-23])
      {:ok, ~U[2021-08-08 13:50:08.007771Z]}

  """
  @doc since: "2.0.0"
  @spec date_time_new_moon_nearest(date()) :: {:ok, DateTime.t()}

  def date_time_new_moon_nearest(unquote(Guards.datetime()) = date_time) do
    _ = calendar

    date_time
    |> Time.date_time_to_moment()
    |> Lunar.date_time_new_moon_nearest()
    |> Time.date_time_from_moment()
  end

  def date_time_new_moon_nearest(unquote(Guards.date()) = date) do
    _ = calendar

    date
    |> Time.date_time_to_moment()
    |> Lunar.date_time_new_moon_nearest()
    |> Time.date_time_from_moment()
  end

  @doc """
  Returns the date time of the new
  moon at or after a given date or
  date time.

  ### Arguments

  * `date_time` is a `DateTime` or a `Date` or
    any struct that meets the requirements of
    `t:Calendar.date` or `t:Calendar.datetime`.

  ### Returns

  * `{:ok, date_time}`, the UTC `t:DateTime.t/0` at which the new
    moon occurs.

  Raises `ArgumentError` for a date more than 50,000 years from J2000,
  where the new moons can no longer be told apart reliably.

  ### Examples

      iex> Astro.date_time_new_moon_at_or_after(~D[2021-08-23])
      {:ok, ~U[2021-09-07 00:51:46.307784Z]}

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_at_or_after(date()) :: {:ok, DateTime.t()}

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
    |> Time.date_time_to_moment()
    |> Lunar.date_time_new_moon_at_or_after()
    |> Time.date_time_from_moment()
  end

  @doc """
  Returns the lunar phase as a
  float number of degrees at a given
  date or date time.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  ### Returns

  * the lunar phase as a float number of
    degrees.

  ### Examples

      iex> Astro.lunar_phase_at ~U[2021-08-22 12:02:02.816534Z]
      180.00068383330358

      iex> Astro.lunar_phase_at(~U[2021-07-10 01:16:37.026816Z])
      359.9999651540469

  Outside the loaded ephemeris the phase comes from the analytical
  series:

      iex> Astro.lunar_phase_at(~D[1000-01-01]) |> Float.round(2)
      202.55

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
    |> Time.date_time_to_moment()
    |> Lunar.lunar_phase_at()
  end

  @doc """
  Returns the moon phase as a UTF8 binary
  representing an emoji of the moon phase.

  ### Arguments

  * `phase` is a moon phase between `0.0` and `360.0`.

  ### Returns

  * A single grapheme string representing the [Unicode
    moon phase emoji](https://unicode-table.com/en/sets/moon/).

  ### Examples

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

      iex> ~U[2021-08-22 12:02:02.816534Z]
      ...> |> Astro.lunar_phase_at()
      ...> |> Astro.lunar_phase_emoji()
      "🌕"

  """
  @spec lunar_phase_emoji(phase()) :: String.t()
  def lunar_phase_emoji(phase) when is_lunar_phase(phase) do
    # Each symbol covers 45 degrees centred on its phase, so the new moon's
    # bin runs from 337.5 degrees round to 22.5.
    bin = rem(ceil(phase / @emoji_phase + 0.5) - 1, @emoji_phase_count)
    <<@emoji_base + 1 + bin::utf8>>
  end

  @doc """
  Returns the date time of a given
  lunar phase at or before a given
  date time or date.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0.0` and
    `3660.0`.

  ### Returns

  * `{:ok, date_time}`, the UTC `t:DateTime.t/0` at which the phase
    occurs.

  ### Examples

      iex> Astro.date_time_lunar_phase_at_or_before(~D[2021-08-01], Astro.Lunar.new_moon_phase())
      {:ok, ~U[2021-07-10 01:16:37.026816Z]}

  """

  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_before(date(), Astro.phase()) ::
          {:ok, DateTime.t()}

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
    |> Time.date_time_to_moment()
    |> Lunar.date_time_lunar_phase_at_or_before(phase)
    |> Time.date_time_from_moment()
  end

  @doc """
  Returns the date time of a given
  lunar phase at or after a given
  date time or date.

  ### Arguments

  * `date_time` is a `t:DateTime.t/0` or a `t:Date.t/0` or
    any struct that meets the requirements of
    `t:Calendar.date/0` or `t:Calendar.datetime/0`.

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0.0` and
    `360.0`.

  ### Returns

  * `{:ok, date_time}`, the UTC `t:DateTime.t/0` at which the phase
    occurs.

  ### Examples

      iex> Astro.date_time_lunar_phase_at_or_after(~D[2021-08-01], Astro.Lunar.full_moon_phase())
      {:ok, ~U[2021-08-22 12:01:57.910586Z]}

  """

  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_after(date(), Astro.phase()) ::
          {:ok, DateTime.t()}

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
    |> Time.date_time_to_moment()
    |> Lunar.date_time_lunar_phase_at_or_after(phase)
    |> Time.date_time_from_moment()
  end

  @doc """
  Calculates the sunrise for a given location and date.

  Sunrise is the moment when the upper limb of the sun appears on the
  horizon in the morning.

  Refraction lifts the Sun by a standard 34′ at the horizon and its
  semi-diameter is about 16′, so this is the moment the Sun's centre,
  computed without refraction, is 50′ below the horizon. The
  twilights are the moments the centre is 6°, 12° or 18° below it.

  The Sun's altitude is calculated from its apparent geocentric
  position (see `sun_position_at/1`) and the local apparent sidereal
  time; its parallax, at most 8.8″, is ignored. The altitude is
  sampled every 24 minutes across the day to bracket the crossing,
  which is then narrowed by bisection to 0.01 s. The position comes
  from the JPL DE440s ephemeris where the loaded kernel covers the
  date, and from the analytical series elsewhere.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0`.
    Longitude comes first. An elevation does not change the result.

  * `date` is a `t:Date.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`
    for the day of the sunrise.

  * `options` is a keyword list of options.

  ### Options

  * `:solar_elevation` is the zenith angle of the sun, in degrees, that
    marks the sunrise, or one of the names below. The default is
    `:geometric`.

    * `:geometric` is 90°, corrected for refraction and the sun's
      apparent radius so that it matches the moment the upper limb
      appears to touch the horizon.

    * `:civil` is 96°. The sun is below the horizon but there is
      generally enough natural light for most outdoor activities.

    * `:nautical` is 102°. The horizon is barely visible, and the moon
      and stars can still be used for navigation.

    * `:astronomical` is 108°. Beyond this, astronomical observation
      becomes impractical.

  * `:time_zone` is the time zone of the returned date time: `:default`,
    the time zone of the location, which is the default; `:utc`; or a
    time zone name.

  * `:time_zone_database` is the module implementing the
    `Calendar.TimeZoneDatabase` behaviour. The default is the configured
    Elixir time zone database.

  * `:time_zone_resolver` is a 1-arity function that receives a
    `%Geo.Point{coordinates: {lng, lat}}` and returns
    `{:ok, time_zone_name}` or `{:error, reason}`. The default is
    `TzWorld.timezone_at/1` when `:tz_world` is a dependency.

  ### Returns

  * `{:ok, date_time}` where `date_time` is the sunrise in the requested
    time zone.

  * `{:error, :no_time}` if there is no sunrise on that date at that
    location, as happens at very high latitudes in summer and winter.

  * `{:error, :invalid_solar_elevation}` if `:solar_elevation` is neither
    a number nor one of the names above.

  * `{:error, :time_zone_not_found}` if the requested time zone is
    unknown.

  * `{:error, :time_zone_not_resolved}` if no time zone can be resolved
    for the location, which happens when `:tz_world` is not a dependency
    and no `:time_zone_resolver` is given.

  * `{:error, :tz_world_data_not_installed}` if `:tz_world` is a
    dependency but its data has not been installed. Run
    `mix tz_world.update` to install it.

  * `{:error, :utc_only_time_zone_database}` if the sunrise is requested
    in a time zone other than UTC and no time zone database is
    configured.

  ### Accuracy

  Against Skyfield, using the same ephemeris, results agree to 0.95 s
  on average and 1.6 s at most; Skyfield uses the Sun's apparent
  semi-diameter for the day rather than a fixed 16′. Against
  timeanddate.com, which publishes to the minute, they agree to
  28.8 s on average and within a minute in 307 of 310 cases. Outside
  the ephemeris the series move the result by 0.07 s RMS and 0.21 s
  at most. The atmosphere matters more than any of these: refraction
  at the horizon departs from the standard 34′ with temperature and
  pressure, and a high observer sees a lower horizon, and neither is
  modelled. The [accuracy guide](accuracy.md) gives the details.

  ### Examples

      iex> {:ok, date_time} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
      iex> date_time
      #DateTime<2019-12-04 05:37:06.206432+11:00 AEDT Australia/Sydney>

      iex> Astro.sunrise({-62.3481, 82.5018}, ~D[2019-12-04])
      {:error, :no_time}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 15 (rising, transit and setting) and chapter 16
    (atmospheric refraction).

  * United States Naval Observatory, [Rise, Set, and Twilight
    Definitions](https://aa.usno.navy.mil/faq/RST_defs).

  * [Sunrise](https://en.wikipedia.org/wiki/Sunrise) and
    [Twilight](https://en.wikipedia.org/wiki/Twilight), Wikipedia.

  """
  @spec sunrise(location, date, options) ::
          {:ok, DateTime.t()}
          | {:error,
             :no_time
             | :invalid_solar_elevation
             | :time_zone_not_found
             | :time_zone_not_resolved
             | :tz_world_data_not_installed
             | :utc_only_time_zone_database}

  def sunrise(location, date, options \\ []) when is_list(options) do
    Solar.SunRiseSet.sunrise(location, date_to_moment(date), options)
  end

  @doc """
  Calculates the sunset for a given location and date.

  Sunset is the moment when the upper limb of the sun disappears below
  the horizon in the evening.

  Refraction lifts the Sun by a standard 34′ at the horizon and its
  semi-diameter is about 16′, so this is the moment the Sun's centre,
  computed without refraction, is 50′ below the horizon. The
  twilights are the moments the centre is 6°, 12° or 18° below it.

  The Sun's altitude is calculated from its apparent geocentric
  position (see `sun_position_at/1`) and the local apparent sidereal
  time; its parallax, at most 8.8″, is ignored. The altitude is
  sampled every 24 minutes across the day to bracket the crossing,
  which is then narrowed by bisection to 0.01 s. The position comes
  from the JPL DE440s ephemeris where the loaded kernel covers the
  date, and from the analytical series elsewhere.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0`.
    Longitude comes first. An elevation does not change the result.

  * `date` is a `t:Date.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`
    for the day of the sunset.

  * `options` is a keyword list of options.

  ### Options

  * `:solar_elevation` is the zenith angle of the sun, in degrees, that
    marks the sunset, or one of the names below. The default is
    `:geometric`.

    * `:geometric` is 90°, corrected for refraction and the sun's
      apparent radius so that it matches the moment the upper limb
      appears to touch the horizon.

    * `:civil` is 96°. The sun is below the horizon but there is
      generally enough natural light for most outdoor activities.

    * `:nautical` is 102°. The horizon is barely visible, and the moon
      and stars can still be used for navigation.

    * `:astronomical` is 108°. Beyond this, astronomical observation
      becomes impractical.

  * `:time_zone` is the time zone of the returned date time: `:default`,
    the time zone of the location, which is the default; `:utc`; or a
    time zone name.

  * `:time_zone_database` is the module implementing the
    `Calendar.TimeZoneDatabase` behaviour. The default is the configured
    Elixir time zone database.

  * `:time_zone_resolver` is a 1-arity function that receives a
    `%Geo.Point{coordinates: {lng, lat}}` and returns
    `{:ok, time_zone_name}` or `{:error, reason}`. The default is
    `TzWorld.timezone_at/1` when `:tz_world` is a dependency.

  ### Returns

  * `{:ok, date_time}` where `date_time` is the sunset in the requested
    time zone.

  * `{:error, :no_time}` if there is no sunset on that date at that
    location, as happens at very high latitudes in summer and winter.

  * `{:error, :invalid_solar_elevation}` if `:solar_elevation` is neither
    a number nor one of the names above.

  * `{:error, :time_zone_not_found}` if the requested time zone is
    unknown.

  * `{:error, :time_zone_not_resolved}` if no time zone can be resolved
    for the location, which happens when `:tz_world` is not a dependency
    and no `:time_zone_resolver` is given.

  * `{:error, :tz_world_data_not_installed}` if `:tz_world` is a
    dependency but its data has not been installed. Run
    `mix tz_world.update` to install it.

  * `{:error, :utc_only_time_zone_database}` if the sunset is requested
    in a time zone other than UTC and no time zone database is
    configured.

  ### Accuracy

  Against Skyfield, using the same ephemeris, results agree to 0.95 s
  on average and 1.6 s at most; Skyfield uses the Sun's apparent
  semi-diameter for the day rather than a fixed 16′. Against
  timeanddate.com, which publishes to the minute, they agree to
  28.8 s on average and within a minute in 307 of 310 cases. Outside
  the ephemeris the series move the result by 0.07 s RMS and 0.21 s
  at most. The atmosphere matters more than any of these: refraction
  at the horizon departs from the standard 34′ with temperature and
  pressure, and a high observer sees a lower horizon, and neither is
  modelled. The [accuracy guide](accuracy.md) gives the details.

  ### Examples

      iex> {:ok, date_time} = Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
      iex> date_time
      #DateTime<2019-12-04 19:53:18.155710+11:00 AEDT Australia/Sydney>

      iex> Astro.sunset({-62.3481, 82.5018}, ~D[2019-12-04])
      {:error, :no_time}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 15 (rising, transit and setting) and chapter 16
    (atmospheric refraction).

  * United States Naval Observatory, [Rise, Set, and Twilight
    Definitions](https://aa.usno.navy.mil/faq/RST_defs).

  * [Sunset](https://en.wikipedia.org/wiki/Sunset) and
    [Twilight](https://en.wikipedia.org/wiki/Twilight), Wikipedia.

  """
  @spec sunset(location, date, options) ::
          {:ok, DateTime.t()}
          | {:error,
             :no_time
             | :invalid_solar_elevation
             | :time_zone_not_found
             | :time_zone_not_resolved
             | :tz_world_data_not_installed
             | :utc_only_time_zone_database}

  def sunset(location, date, options \\ []) when is_list(options) do
    Solar.SunRiseSet.sunset(location, date_to_moment(date), options)
  end

  @doc """
  Returns the moonrise for a given location and date.

  The moonrise is the moment the upper limb of the Moon appears above the
  horizon, found from the JPL DE440s ephemeris with full topocentric
  correction.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is a `t:Date.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`
    for the day of the moonrise.

  * `options` is a keyword list of options.

  ### Options

  * `:limb` is the part of the Moon's disk that defines the event.

    * `:upper`, the default, puts the upper limb on the apparent
      horizon, the USNO standard. The event threshold is
      `−(34′ refraction + semi-diameter)`.

    * `:center` puts the centre of the disk on the apparent horizon.
      The event threshold is `−34′` of refraction only.

  * `:interpolation` is how the Moon's position is evaluated while the
    event is bisected.

    * `:direct`, the default, evaluates the JPL ephemeris at every step.

    * `:lagrange` interpolates the geocentric position quadratically
      from three points, as Meeus Ch. 15 does.

  * `:time_zone` is the time zone of the returned date time: `:default`,
    the time zone of the location, which is the default; `:utc`; or a
    time zone name.

  * `:time_zone_database` is the module implementing the
    `Calendar.TimeZoneDatabase` behaviour. The default is the configured
    Elixir time zone database.

  * `:time_zone_resolver` is a 1-arity function that receives a
    `%Geo.Point{coordinates: {lng, lat}}` and returns
    `{:ok, time_zone_name}` or `{:error, reason}`. The default is
    `TzWorld.timezone_at/1` when `:tz_world` is a dependency.

  ### Returns

  * `{:ok, date_time}` where `date_time` is the moonrise in the requested
    time zone.

  * `{:error, :no_time}` if the Moon does not rise on that date at that
    location, as it can stay below the horizon for a whole day.

  * `{:error, :invalid_limb}` if `:limb` is not `:upper` or `:center`.

  * `{:error, :invalid_interpolation}` if `:interpolation` is not
    `:direct` or `:lagrange`.

  * `{:error, :time_zone_not_found}` if the requested time zone is
    unknown.

  * `{:error, :time_zone_not_resolved}` if no time zone can be resolved
    for the location, which happens when `:tz_world` is not a dependency
    and no `:time_zone_resolver` is given.

  * `{:error, :tz_world_data_not_installed}` if `:tz_world` is a
    dependency but its data has not been installed. Run
    `mix tz_world.update` to install it.

  * `{:error, :utc_only_time_zone_database}` if the moonrise is requested
    in a time zone other than UTC and no time zone database is
    configured.

  ### Examples

      iex> {:ok, date_time} = Astro.moonrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
      iex> date_time
      #DateTime<2019-12-04 12:20:54.388717+11:00 AEDT Australia/Sydney>

      iex> Astro.moonrise({-62.3481, 82.5018}, ~D[2024-01-01])
      {:error, :no_time}

  """
  @doc since: "2.0.0"
  @spec moonrise(location, date, options) ::
          {:ok, DateTime.t()}
          | {:error,
             :no_time
             | :invalid_limb
             | :invalid_interpolation
             | :time_zone_not_found
             | :time_zone_not_resolved
             | :tz_world_data_not_installed
             | :utc_only_time_zone_database}

  def moonrise(location, date, options \\ default_options())

  def moonrise(location, date, options) when is_list(options) do
    Lunar.MoonRiseSet.moonrise(location, date_to_moment(date), options)
  end

  @doc """
  Returns the moonset for a given location and date.

  The moonset is the moment the upper limb of the Moon disappears below the
  horizon, found from the JPL DE440s ephemeris with full topocentric
  correction.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is a `t:Date.t/0`, `t:NaiveDateTime.t/0` or `t:DateTime.t/0`
    for the day of the moonset.

  * `options` is a keyword list of options.

  ### Options

  * `:limb` is the part of the Moon's disk that defines the event.

    * `:upper`, the default, puts the upper limb on the apparent
      horizon, the USNO standard. The event threshold is
      `−(34′ refraction + semi-diameter)`.

    * `:center` puts the centre of the disk on the apparent horizon.
      The event threshold is `−34′` of refraction only.

  * `:interpolation` is how the Moon's position is evaluated while the
    event is bisected.

    * `:direct`, the default, evaluates the JPL ephemeris at every step.

    * `:lagrange` interpolates the geocentric position quadratically
      from three points, as Meeus Ch. 15 does.

  * `:time_zone` is the time zone of the returned date time: `:default`,
    the time zone of the location, which is the default; `:utc`; or a
    time zone name.

  * `:time_zone_database` is the module implementing the
    `Calendar.TimeZoneDatabase` behaviour. The default is the configured
    Elixir time zone database.

  * `:time_zone_resolver` is a 1-arity function that receives a
    `%Geo.Point{coordinates: {lng, lat}}` and returns
    `{:ok, time_zone_name}` or `{:error, reason}`. The default is
    `TzWorld.timezone_at/1` when `:tz_world` is a dependency.

  ### Returns

  * `{:ok, date_time}` where `date_time` is the moonset in the requested
    time zone.

  * `{:error, :no_time}` if the Moon does not set on that date at that
    location, as it can stay above the horizon for a whole day.

  * `{:error, :invalid_limb}` if `:limb` is not `:upper` or `:center`.

  * `{:error, :invalid_interpolation}` if `:interpolation` is not
    `:direct` or `:lagrange`.

  * `{:error, :time_zone_not_found}` if the requested time zone is
    unknown.

  * `{:error, :time_zone_not_resolved}` if no time zone can be resolved
    for the location, which happens when `:tz_world` is not a dependency
    and no `:time_zone_resolver` is given.

  * `{:error, :tz_world_data_not_installed}` if `:tz_world` is a
    dependency but its data has not been installed. Run
    `mix tz_world.update` to install it.

  * `{:error, :utc_only_time_zone_database}` if the moonset is requested
    in a time zone other than UTC and no time zone database is
    configured.

  ### Examples

      iex> {:ok, date_time} = Astro.moonset({151.20666584, -33.8559799094}, ~D[2019-12-04])
      iex> date_time
      #DateTime<2019-12-04 01:13:25.822599+11:00 AEDT Australia/Sydney>

      iex> Astro.moonset({-62.3481, 82.5018}, ~D[2024-01-01])
      {:error, :no_time}

  """
  @doc since: "2.0.0"
  @spec moonset(location, date, options) ::
          {:ok, DateTime.t()}
          | {:error,
             :no_time
             | :invalid_limb
             | :invalid_interpolation
             | :time_zone_not_found
             | :time_zone_not_resolved
             | :tz_world_data_not_installed
             | :utc_only_time_zone_database}

  def moonset(location, date, options \\ default_options())

  def moonset(location, date, options) when is_list(options) do
    Lunar.MoonRiseSet.moonset(location, date_to_moment(date), options)
  end

  @doc """
  Predicts the visibility of the new crescent moon at a given location
  on a given date using one of three published criteria.

  At the optimal observation time after sunset, the function evaluates
  the geometric and photometric conditions to classify the crescent
  into one of five visibility categories.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is a `t:Date.t/0` or `t:DateTime.t/0` indicating the evening
    on which crescent visibility is to be evaluated.

  * `method` selects the prediction criterion. Default `:odeh`.

    * `:odeh` — Odeh (2006). Empirical criterion based on 737 observations.
      Uses topocentric ARCV with a Danjon limit of 6.4°. The most widely
      used modern criterion.

    * `:yallop` — Yallop (1997). Empirical criterion based on 295
      observations. Uses geocentric ARCV. The original single-parameter
      approach that Odeh later refined.

    * `:schaefer` — Schaefer (1988/2000). Physics-based model computing
      the contrast between crescent brightness and twilight sky brightness
      against the human contrast detection threshold. The best observation
      time is found by scanning from sunset to moonset.

  ### Options

  When `method` is `:schaefer`, the following options are accepted as
  an optional fourth argument (a keyword list):

  * `:extinction` — V-band zenith extinction coefficient. Default `0.172`
    (clean sea-level site). Typical values: `0.12` (high mountain),
    `0.17` (sea level), `0.25` (hazy conditions).

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of:

    * `:A` — Visible to the naked eye.

    * `:B` — Visible with optical aid.

    * `:C` — May need optical aid.

    * `:D` — Not visible with optical aid.

    * `:E` — Not visible.

  * `{:error, :no_sunset}` if no sunset occurs on the given date at
    the given location (e.g. polar day).

  ### Method comparison

  | Aspect | Yallop (1997) | Odeh (2006) | Schaefer (1988/2000) |
  |---|---|---|---|
  | Basis | Empirical polynomial | Empirical polynomial | Physical model |
  | Observations | 295 | 737 | N/A (theory) |
  | ARCV type | Geocentric | Topocentric | N/A |
  | Best time | Sunset + 4/9 lag | Sunset + 4/9 lag | Scanned (max Rs) |
  | Atmosphere | Not modelled | Not modelled | Extinction coefficient |

  ### Examples

      iex> location = {-0.1275, 51.5072}
      iex> Astro.new_visible_crescent(location, ~D[2025-03-31])
      {:ok, :A}

      iex> location = {-0.1275, 51.5072}
      iex> Astro.new_visible_crescent(location, ~D[2025-03-31], :yallop)
      {:ok, :A}

  """
  @doc since: "2.1.0"
  @type method :: :odeh | :yallop | :schaefer

  @spec new_visible_crescent(location(), date(), method()) ::
          {:ok, Lunar.CrescentVisibility.visibility()} | {:error, :no_sunset}

  def new_visible_crescent(location, date, method \\ :odeh)

  def new_visible_crescent(location, date, :yallop) do
    moment = Time.date_time_to_moment(date)
    normalized = Location.normalize_location(location)
    Lunar.CrescentVisibility.yallop_new_visible_crescent(normalized, moment)
  end

  def new_visible_crescent(location, date, :odeh) do
    moment = Time.date_time_to_moment(date)
    normalized = Location.normalize_location(location)
    Lunar.CrescentVisibility.odeh_new_visible_crescent(normalized, moment)
  end

  def new_visible_crescent(location, date, :schaefer) do
    moment = Time.date_time_to_moment(date)
    normalized = Location.normalize_location(location)
    Lunar.CrescentVisibility.schaefer_new_visible_crescent(normalized, moment)
  end

  @doc """
  Predicts the visibility of the new crescent moon with Schaefer's
  method, adjusted for the atmosphere.

  This is `new_visible_crescent/3` with the `:schaefer` method, taking
  the same location and date and returning the same classes. See
  `new_visible_crescent/3` for how the methods compare.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is a `t:Date.t/0` or `t:DateTime.t/0` indicating the evening
    on which crescent visibility is to be evaluated.

  * `method` is `:schaefer`, the only method that takes options.

  * `options` is a keyword list of options.

  ### Options

  * `:extinction` is the V-band zenith extinction coefficient. The
    default is `0.172`, a clean sea-level site. Typical values are
    `0.12` on a high mountain, `0.17` at sea level and `0.25` in hazy
    conditions.

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of the classes `:A`
    to `:E` described in `new_visible_crescent/3`.

  * `{:error, :no_sunset}` if no sunset occurs on the given date at the
    given location.

  ### Examples

      iex> location = {39.8579, 21.3891}
      iex> Astro.new_visible_crescent(location, ~D[2025-03-31], :schaefer, extinction: 0.25)
      {:ok, :A}

  """
  @doc since: "2.1.0"
  @spec new_visible_crescent(location(), date(), :schaefer, keyword()) ::
          {:ok, Lunar.CrescentVisibility.visibility()} | {:error, :no_sunset}

  def new_visible_crescent(location, date, method, options)

  def new_visible_crescent(location, date, :schaefer, options) when is_list(options) do
    moment = Time.date_time_to_moment(date)
    normalized = Location.normalize_location(location)
    Lunar.CrescentVisibility.schaefer_new_visible_crescent(normalized, moment, options)
  end

  @doc """
  Returns the datetime of either the March or September
  equinox, in UTC or a requested time zone.

  An equinox is the moment the Sun's apparent ecliptic longitude
  reaches 0° (the March equinox) or 180° (the September equinox).
  The Sun is then very nearly on the celestial equator, heading
  north in March and south in September, and day and night are of
  almost equal length everywhere.

  The moment is found from the Sun's apparent ecliptic longitude
  (see `sun_apparent_longitude/1`). Starting 20 days before the 1st
  of the month, the Sun's mean motion of 360° a tropical year
  estimates when it reaches the target longitude, and a ten-day
  bracket around that estimate is bisected until it is narrower than
  a millisecond. The longitude comes from the JPL DE440s ephemeris where the
  loaded kernel covers the year, and from the analytical series for
  any other year.

  ### Arguments

  * `year` is the Gregorian year for which the equinox is
    to be calculated, within 50,000 years of 2000.

  * `event` is either `:march` or `:september` indicating
    which of the two annual equinox datetimes is required.

  * `options` is a keyword list of options.

  ### Options

  * `:time_zone` is `:utc` (the default) or a time zone
    name such as `"Asia/Tokyo"`. The equinox is one instant
    everywhere; the time zone decides the local date and
    time it is given in, and so the civil day it falls on.

  * `:time_zone_database` is the module implementing
    `Calendar.TimeZoneDatabase` in which a named time zone
    is looked up. The default is the configured database,
    `Calendar.get_time_zone_database/0`. UTC needs none.

  ### Returns

  * `{:ok, datetime}`, the equinox in the requested time
    zone.

  * `{:error, :time_zone_not_found}` if the time zone is
    not known to the time zone database.

  * `{:error, :utc_only_time_zone_database}` if a time zone
    other than UTC is requested and no time zone database
    is configured.

  * `{:error, :invalid_time_zone_database}` if
    `:time_zone_database` is not a time zone database.

  * `{:error, :invalid_year}` if `year` is not an integer.

  * `{:error, :year_out_of_range}` if `year` is more than 50,000
    years from 2000.

  * `{:error, :invalid_event}` if `event` is not `:march` or
    `:september`.

  ### Accuracy

  The search ends within a millisecond of the crossing. For the June
  solstice of 1962, Meeus gives 21h24m42s TD from the full VSOP87
  theory (*Astronomical Algorithms*, chapter 27); Astro gives
  21:24:07.8 UTC, which is 21h24m42.0s TD. Outside the ephemeris the
  series put the events 14 s early on average over 1900–2100, 18 s
  RMS and 50 s at most. Far from the present the time is limited by
  ΔT, which is uncertain by minutes before about 1000 and after
  about 2500; the [accuracy guide](accuracy.md) gives the details.

  ### Examples

      iex> {:ok, dt} = Astro.equinox 2019, :march
      iex> DateTime.truncate(dt, :second)
      ~U[2019-03-20 21:58:24Z]
      iex> {:ok, dt} = Astro.equinox 2019, :september
      iex> DateTime.truncate(dt, :second)
      ~U[2019-09-23 07:50:08Z]
      iex> {:ok, dt} = Astro.equinox 900, :march
      iex> DateTime.to_date(dt)
      ~D[0900-03-20]

      # The March 2019 equinox is on the 20th in UTC but the 21st in Tokyo
      iex> {:ok, dt} = Astro.equinox(2019, :march, time_zone: "Asia/Tokyo")
      iex> DateTime.to_date(dt)
      ~D[2019-03-21]

      iex> Astro.equinox(2019, :march,
      ...>   time_zone: "Asia/Tokyo",
      ...>   time_zone_database: Calendar.UTCOnlyTimeZoneDatabase
      ...> )
      {:error, :utc_only_time_zone_database}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 27 (equinoxes and solstices).

  * United States Naval Observatory, [Earth's
    Seasons](https://aa.usno.navy.mil/data/Earth_Seasons).

  * [Equinox](https://en.wikipedia.org/wiki/Equinox) and
    [Tropical year](https://en.wikipedia.org/wiki/Tropical_year), Wikipedia.

  """
  @spec equinox(Calendar.year(), :march | :september, options()) ::
          {:ok, DateTime.t()}
          | {:error,
             :invalid_year
             | :invalid_event
             | :year_out_of_range
             | :time_zone_not_found
             | :utc_only_time_zone_database
             | :invalid_time_zone_database}
  def equinox(year, event, options \\ [])

  def equinox(year, event, options) when event in [:march, :september] and is_integer(year) do
    with {:ok, equinox} <- Solar.equinox_and_solstice(year, event) do
      in_time_zone(equinox, options)
    end
  end

  def equinox(year, _event, _options) when not is_integer(year) do
    {:error, :invalid_year}
  end

  def equinox(_year, _event, _options) do
    {:error, :invalid_event}
  end

  @doc """
  Returns the datetime of either the June or December
  solstice, in UTC or a requested time zone.

  A solstice is the moment the Sun's apparent ecliptic longitude
  reaches 90° (the June solstice) or 270° (the December solstice).
  The Sun is then at its farthest north or south of the celestial
  equator, and the day is the longest of the year in one hemisphere
  and the shortest in the other.

  The moment is found from the Sun's apparent ecliptic longitude
  (see `sun_apparent_longitude/1`). Starting 20 days before the 1st
  of the month, the Sun's mean motion of 360° a tropical year
  estimates when it reaches the target longitude, and a ten-day
  bracket around that estimate is bisected until it is narrower than
  a millisecond. The longitude comes from the JPL DE440s ephemeris where the
  loaded kernel covers the year, and from the analytical series for
  any other year.

  ### Arguments

  * `year` is the Gregorian year for which the solstice is
    to be calculated, within 50,000 years of 2000.

  * `event` is either `:june` or `:december` indicating
    which of the two annual solstice datetimes is required.

  * `options` is a keyword list of options.

  ### Options

  * `:time_zone` is `:utc` (the default) or a time zone
    name such as `"Asia/Tokyo"`. The solstice is one instant
    everywhere; the time zone decides the local date and
    time it is given in, and so the civil day it falls on.

  * `:time_zone_database` is the module implementing
    `Calendar.TimeZoneDatabase` in which a named time zone
    is looked up. The default is the configured database,
    `Calendar.get_time_zone_database/0`. UTC needs none.

  ### Returns

  * `{:ok, datetime}`, the solstice in the requested time
    zone.

  * `{:error, :time_zone_not_found}` if the time zone is
    not known to the time zone database.

  * `{:error, :utc_only_time_zone_database}` if a time zone
    other than UTC is requested and no time zone database
    is configured.

  * `{:error, :invalid_time_zone_database}` if
    `:time_zone_database` is not a time zone database.

  * `{:error, :invalid_year}` if `year` is not an integer.

  * `{:error, :year_out_of_range}` if `year` is more than 50,000
    years from 2000.

  * `{:error, :invalid_event}` if `event` is not `:june` or
    `:december`.

  ### Accuracy

  The search ends within a millisecond of the crossing. For the June
  solstice of 1962, Meeus gives 21h24m42s TD from the full VSOP87
  theory (*Astronomical Algorithms*, chapter 27); Astro gives
  21:24:07.8 UTC, which is 21h24m42.0s TD. Outside the ephemeris the
  series put the events 14 s early on average over 1900–2100, 18 s
  RMS and 50 s at most. Far from the present the time is limited by
  ΔT, which is uncertain by minutes before about 1000 and after
  about 2500; the [accuracy guide](accuracy.md) gives the details.

  ### Examples

      iex> {:ok, dt} = Astro.solstice 2019, :december
      iex> DateTime.truncate(dt, :second)
      ~U[2019-12-22 04:19:24Z]
      iex> {:ok, dt} = Astro.solstice 2019, :june
      iex> DateTime.truncate(dt, :second)
      ~U[2019-06-21 15:54:13Z]
      iex> {:ok, dt} = Astro.solstice 3500, :june
      iex> DateTime.to_date(dt)
      ~D[3500-06-20]

      # The June 2021 solstice is on the 21st in UTC but the 20th in Santiago
      iex> {:ok, dt} = Astro.solstice(2021, :june, time_zone: "America/Santiago")
      iex> DateTime.to_date(dt)
      ~D[2021-06-20]

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 27 (equinoxes and solstices).

  * United States Naval Observatory, [Earth's
    Seasons](https://aa.usno.navy.mil/data/Earth_Seasons).

  * [Solstice](https://en.wikipedia.org/wiki/Solstice) and
    [Tropical year](https://en.wikipedia.org/wiki/Tropical_year), Wikipedia.

  """
  @spec solstice(Calendar.year(), :june | :december, options()) ::
          {:ok, DateTime.t()}
          | {:error,
             :invalid_year
             | :invalid_event
             | :year_out_of_range
             | :time_zone_not_found
             | :utc_only_time_zone_database
             | :invalid_time_zone_database}
  def solstice(year, event, options \\ [])

  def solstice(year, event, options) when event in [:june, :december] and is_integer(year) do
    with {:ok, solstice} <- Solar.equinox_and_solstice(year, event) do
      in_time_zone(solstice, options)
    end
  end

  def solstice(year, _event, _options) when not is_integer(year) do
    {:error, :invalid_year}
  end

  def solstice(_year, _event, _options) do
    {:error, :invalid_event}
  end

  @doc """
  Returns solar noon at a location on a date, as a UTC date time.

  Solar noon is the moment the Sun crosses the local meridian, when it
  is due north or south and highest in the sky. It is rarely 12:00 on
  the clock: a mean Sun moving uniformly would cross the meridian at
  12:00 local mean time, but the true Sun runs ahead of or behind it
  by the equation of time, up to about 16 minutes, because the Earth's
  orbit is elliptical and its axis is tilted.

  Solar noon is found as the moment the Sun's local hour angle (the
  local apparent sidereal time less the Sun's apparent right
  ascension) is zero, by Newton's method from 12:00 local mean time;
  see `Astro.Solar.solar_noon/2`. The Sun's position comes from the
  JPL DE440s ephemeris where the loaded kernel covers the date, and
  from the analytical series elsewhere.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is any `t:Calendar.date/0`. A date in a calendar other
    than `Calendar.ISO` is converted to its ISO date first.

  ### Returns

  * `{:ok, datetime}`, the UTC date time of solar noon at the given
    location on the given UTC date.

  * `{:error, :invalid_date}` if `date` is not a valid date in its
    calendar.

  * `{:error, :incompatible_calendars}` if its calendar cannot be
    converted to `Calendar.ISO`.

  ### Accuracy

  The hour angle is solved to a millisecond, so solar noon is as
  accurate as the Sun's right ascension and the sidereal time. Inside
  the ephemeris the right ascension is accurate to well under 0.01 s
  of time; outside it the series move solar noon by 0.06 s RMS and
  0.15 s at most over 1900–2100. Sidereal time follows the Earth's
  rotation, UT1, and Astro takes UTC for it; the two differ by up to
  0.9 s. The [accuracy guide](accuracy.md) describes how ΔT limits
  results far from the present.

  ### Examples

      iex> Astro.solar_noon {151.20666584, -33.8559799094}, ~D[2019-12-06]
      {:ok, ~U[2019-12-06 01:45:52.977018Z]}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 15 (rising, transit and setting) and chapter 28
    (equation of time).

  * [Equation of time](https://en.wikipedia.org/wiki/Equation_of_time)
    and [Hour angle](https://en.wikipedia.org/wiki/Hour_angle),
    Wikipedia.

  """
  @spec solar_noon(Astro.location(), Calendar.date()) ::
          {:ok, DateTime.t()}
          | {:error, :invalid_date | :incompatible_calendars}
  def solar_noon(location, date) do
    %Geo.PointZ{coordinates: {longitude, _, _}} = Location.normalize_location(location)

    # Both the Julian day and the date time are taken from the ISO date, so a
    # date in another calendar gives the solar noon of that same day.
    with {:ok, iso_date} <- Time.iso_date(date) do
      iso_date
      |> Time.date_time_to_moment()
      |> Solar.solar_noon(longitude)
      |> Time.date_time_from_moment()
    end
  end

  @doc """
  Returns the Sun's apparent ecliptic longitude at a date or date time.

  The ecliptic longitude is the Sun's position along the ecliptic,
  the plane of the Earth's orbit, measured eastward from the equinox
  of the date. It is 0° at the March equinox, 90° at the June
  solstice, 180° at the September equinox and 270° at the December
  solstice, so it measures how far through the tropical year (the
  year of the seasons) the Earth has moved, without the irregularity
  of leap years. Solar terms, such as those of the Chinese calendar,
  are the moments it reaches multiples of 15°.

  Where the loaded JPL DE440s ephemeris covers the moment, the
  apparent position (see `sun_position_at/1`) is rotated from the
  true equator to the ecliptic of date by the true obliquity.
  Elsewhere it is the 49-term series of Bretagnon and Simon, with
  aberration and nutation in longitude added.

  ### Arguments

  * `date` is a `t:Date.t/0`, `t:NaiveDateTime.t/0` or
    `t:DateTime.t/0`. A date is taken at 00:00 UTC.

  ### Returns

  * the apparent ecliptic longitude in degrees, from 0 to 360.

  ### Accuracy

  Outside the ephemeris the series agree with JPL over 1900–2100 to
  0.75″ RMS and 2.0″ at most, with a mean bias of +0.56″. The Sun
  moves about 2.5″ a minute, so that bias puts the moment the Sun
  reaches a given longitude about 14 s early. The
  [accuracy guide](accuracy.md) gives the details, and how the series
  and ΔT drift far from the present.

  ### Examples

      iex> Astro.sun_apparent_longitude ~D[2019-03-21]
      0.0838600951350463
      iex> Astro.sun_apparent_longitude ~D[2019-06-22]
      90.32182153965914
      iex> Astro.sun_apparent_longitude ~D[2019-09-23]
      179.68053562968015
      iex> Astro.sun_apparent_longitude ~D[2019-12-23]
      270.8352772904792

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 25 (solar coordinates).

  * Edward M. Reingold and Nachum Dershowitz, *Calendrical
    Calculations*, for the series of Bretagnon and Simon.

  * [Ecliptic coordinate system](https://en.wikipedia.org/wiki/Ecliptic_coordinate_system),
    Wikipedia.

  """
  @spec sun_apparent_longitude(date()) :: degrees()
  def sun_apparent_longitude(date) do
    date
    |> Time.date_time_to_moment()
    |> Solar.solar_ecliptic_longitude()
  end

  @doc """
  Returns the number of hours of daylight for a given
  location on a given date.

  Daylight is the time the Sun is above the horizon during the local
  calendar day, from the sunrise and sunset of `sunrise/3` and
  `sunset/3` in the location's time zone. It is counted from the
  events that fall within the day rather than as sunset less
  sunrise, so a day near a polar circle on which the Sun sets just
  after midnight and rises again a few hours later is handled. With
  neither event, the day is all daylight or none, according to
  whether the Sun is up.

  `duration_of_daylight/2` is the same calculation returning a
  `t:Duration.t/0`, which can represent a full 24 hours of daylight.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is any `t:Date.t/0` in the Gregorian
    calendar (for example, `Calendar.ISO`).

  ### Returns

  * `{:ok, time}` where `time` is a `Time.t()`. The maximum value is
    `~T[23:59:59]`, representing 24 hours of daylight (a `Time.t()`
    cannot hold `24:00:00`).

  * `{:error, reason}` if the time zone for the location cannot be
    resolved.

  ### Accuracy

  It is taken from `sunrise/3` and `sunset/3`, each within 1.6 s of
  Skyfield for the same definition of the horizon, and is rounded
  down to the second. Refraction in the real atmosphere moves both
  events, by different amounts.

  ### Examples

      iex> Astro.hours_of_daylight({151.20666584, -33.8559799094}, ~D[2019-12-10])
      {:ok, ~T[14:20:50]}

      # No sunset in summer
      iex> Astro.hours_of_daylight({-62.3481, 82.5018}, ~D[2019-06-07])
      {:ok, ~T[23:59:59]}

      # No sunrise in winter
      iex> Astro.hours_of_daylight({-62.3481, 82.5018}, ~D[2019-12-07])
      {:ok, ~T[00:00:00]}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 15 (rising, transit and setting).

  * [Daytime](https://en.wikipedia.org/wiki/Daytime),
    [Midnight sun](https://en.wikipedia.org/wiki/Midnight_sun) and
    [Polar night](https://en.wikipedia.org/wiki/Polar_night),
    Wikipedia.

  """
  @spec hours_of_daylight(Astro.location(), Calendar.date()) ::
          {:ok, Elixir.Time.t()} | {:error, atom()}
  def hours_of_daylight(location, date) do
    case daylight_seconds(location, date) do
      {:ok, seconds} when seconds >= @seconds_per_day ->
        # 24 hours of daylight (polar day). A `Time.t/0` cannot represent
        # 24:00:00, so it is reported one second short. Use
        # `duration_of_daylight/2` for an uncapped `Duration.t/0`.
        Elixir.Time.new(23, 59, 59)

      {:ok, seconds} ->
        Elixir.Time.new(div(seconds, 3600), div(rem(seconds, 3600), 60), rem(seconds, 60))

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns the duration of daylight for a given location on a
  given date as a `t:Duration.t/0`.

  This is the same calculation as `hours_of_daylight/2` but,
  because a `t:Duration.t/0` is not bounded like a `t:Time.t/0`,
  it can represent a full 24 hours of daylight (returned as
  `%Duration{hour: 24}`) during the polar summer rather than
  capping at `~T[23:59:59]`.

  ### Arguments

  * `location` is the observer's position as a `{longitude, latitude}`
    tuple in degrees, a `t:Geo.Point.t/0`, or a `t:Geo.PointZ.t/0` that
    also carries an elevation in metres. Longitude comes first.

  * `date` is any `t:Date.t/0` in the Gregorian calendar
    (for example, `Calendar.ISO`).

  ### Returns

  * `{:ok, duration}` where `duration` is a `t:Duration.t/0`
    between `%Duration{}` (no daylight) and `%Duration{hour: 24}`
    (24 hours of daylight).

  * `{:error, reason}` if the time zone for the location cannot
    be resolved.

  ### Accuracy

  It is taken from `sunrise/3` and `sunset/3`, each within 1.6 s of
  Skyfield for the same definition of the horizon, and is rounded
  down to the second. Refraction in the real atmosphere moves both
  events, by different amounts.

  ### Examples

      iex> Astro.duration_of_daylight({151.20666584, -33.8559799094}, ~D[2019-12-10])
      {:ok, %Duration{hour: 14, minute: 20, second: 50}}

      # 24 hours of daylight in the polar summer, uncapped
      iex> Astro.duration_of_daylight({-62.3481, 82.5018}, ~D[2019-06-07])
      {:ok, %Duration{hour: 24}}

      # No daylight in the polar winter
      iex> Astro.duration_of_daylight({-62.3481, 82.5018}, ~D[2019-12-07])
      {:ok, %Duration{}}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 15 (rising, transit and setting).

  * [Daytime](https://en.wikipedia.org/wiki/Daytime),
    [Midnight sun](https://en.wikipedia.org/wiki/Midnight_sun) and
    [Polar night](https://en.wikipedia.org/wiki/Polar_night),
    Wikipedia.

  """
  @doc since: "2.3.0"
  @spec duration_of_daylight(Astro.location(), Calendar.date()) ::
          {:ok, Duration.t()} | {:error, atom()}
  def duration_of_daylight(location, date) do
    case daylight_seconds(location, date) do
      {:ok, seconds} ->
        {:ok,
         Duration.new!(
           hour: div(seconds, 3600),
           minute: div(rem(seconds, 3600), 60),
           second: rem(seconds, 60)
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Total seconds the Sun is above the horizon during the local calendar day,
  # in the range 0..86_400. Rather than subtracting sunrise from sunset (which
  # breaks at sub-polar latitudes near the solstice, where the Sun can set just
  # after local midnight and rise again hours later, so sunset precedes
  # sunrise), the daylight is derived from which events fall within the day:
  #
  #   * both events present  → normal day (rise then set) is set − rise; a
  #     reversed day (set then rise) is the whole day minus the night between.
  #   * only sunrise present → Sun rises and stays up to end of day.
  #   * only sunset present  → Sun is up at midnight and sets during the day.
  #   * neither present      → polar day (24h) or polar night (0h).
  #
  defp daylight_seconds(location, date) do
    sunrise_result = sunrise(location, date)

    # A successful sunrise carries the zone it resolved for this location, so
    # sunset reuses it rather than repeating the tz_world lookup. Otherwise
    # sunset resolves exactly as before, which keeps a location with no sunrise
    # -- a polar point in open ocean, say -- behaving as it always has.
    sunset_result = sunset(location, date, sunset_options(sunrise_result))
    daylight_from_events(sunrise_result, sunset_result, location, date)
  end

  defp sunset_options({:ok, %DateTime{time_zone: time_zone}}), do: [time_zone: time_zone]
  defp sunset_options(_sunrise_result), do: []

  defp daylight_from_events({:ok, sunrise}, {:ok, sunset}, _location, _date),
    do: {:ok, daylight_between(sunrise, sunset)}

  defp daylight_from_events({:error, :no_time}, {:ok, sunset}, _location, _date),
    do: {:ok, seconds_since_midnight(sunset)}

  defp daylight_from_events({:ok, sunrise}, {:error, :no_time}, _location, _date),
    do: {:ok, @seconds_per_day - seconds_since_midnight(sunrise)}

  defp daylight_from_events({:error, :no_time}, {:error, :no_time}, location, date) do
    if Solar.SunRiseSet.sun_above_horizon?(location, date_to_moment(date)) do
      {:ok, @seconds_per_day}
    else
      {:ok, 0}
    end
  end

  defp daylight_from_events({:error, reason}, _sunset_result, _location, _date),
    do: {:error, reason}

  defp daylight_from_events(_sunrise_result, {:error, reason}, _location, _date),
    do: {:error, reason}

  # When sunset precedes sunrise on the same calendar day the Sun was already
  # up at local midnight, set briefly, then rose again — daylight is the whole
  # day less the night between the two events (`DateTime.diff` is negative).
  # The difference is taken in microseconds and divided down rather than
  # asking for `:second` directly. `DateTime.diff/2` at second precision
  # handles the microsecond components differently across Elixir releases
  # -- 1.18 and earlier effectively drop them before subtracting, which
  # inflates the result by up to a second -- so the same location and date
  # returned 14:18:45 there and 14:18:44 on 1.19 and later. Dividing an
  # exact microsecond difference truncates identically on every release.
  defp daylight_between(sunrise, sunset) do
    case div(DateTime.diff(sunset, sunrise, :microsecond), 1_000_000) do
      seconds when seconds >= 0 -> seconds
      night -> @seconds_per_day + night
    end
  end

  defp seconds_since_midnight(%DateTime{hour: hour, minute: minute, second: second}) do
    hour * 3600 + minute * 60 + second
  end

  # An equinox or solstice in the requested time zone. UTC needs no time
  # zone database; a named zone is looked up in `:time_zone_database`, the
  # configured database by default, which knows only UTC when none is
  # configured.
  defp in_time_zone(utc_date_time, options) when is_list(options) do
    case Keyword.get(options, :time_zone, :utc) do
      :utc -> {:ok, utc_date_time}
      time_zone when is_binary(time_zone) -> shift_to_time_zone(utc_date_time, time_zone, options)
      _not_a_time_zone -> {:error, :time_zone_not_found}
    end
  end

  defp in_time_zone(_utc_date_time, _options), do: {:error, :time_zone_not_found}

  defp shift_to_time_zone(utc_date_time, time_zone, options) do
    time_zone_database =
      Keyword.get(options, :time_zone_database, Calendar.get_time_zone_database())

    if time_zone_database?(time_zone_database) do
      DateTime.shift_zone(utc_date_time, time_zone, time_zone_database)
    else
      {:error, :invalid_time_zone_database}
    end
  end

  defp time_zone_database?(module) do
    is_atom(module) and Code.ensure_loaded?(module) and
      function_exported?(module, :time_zone_period_from_utc_iso_days, 2)
  end

  @doc false
  def default_options do
    default_time_zone_db =
      Application.get_env(:elixir, :time_zone_database) || @compile_time_time_zone_db

    [
      solar_elevation: Solar.solar_elevation(:geometric),
      time_zone: :default,
      time_zone_database: default_time_zone_db
    ]
  end

  # Convert a Date, DateTime or NaiveDateTime to a moment
  # (integer Gregorian days representing UTC midnight).
  defp date_to_moment(date) do
    Time.date_time_to_moment(date)
  end
end
