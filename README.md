# Astro

[![Hex.pm](https://img.shields.io/hexpm/v/astro.svg)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/dw/astro.svg?)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/dt/astro.svg?)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/l/astro.svg)](https://hex.pm/packages/astro)

Astro is a library to provide accurate astronomical functions with a focus on functions that support solar, lunar and lunisolar calendars such as the Islamic, Chinese, Hebrew and Persian calendars.

## Migration from Astro 1.x

The public API functions in the `Astro` module retain the same signatures in Astro 2.x which should mean a smooth migration in most cases.

When upgrading to Astro 2.x the following should be applied:

* **Download the JPL ephemeris.** Astro 2.x uses the JPL DE440s ephemeris for its calculations. See [Download the JPL Ephemeris](#download-the-jpl-ephemeris) for instructions.

* **Numerical results may differ slightly.** The move from NOAA/Meeus polynomial approximations to the JPL DE440s ephemeris, combined with an improved ΔT computation, means that computed times for events such as equinoxes, solstices and new moons may shift by up to ~22 seconds.

* **Functions outside the `Astro` module may have changed.** Several functions in `Astro.Solar`, `Astro.Lunar`, `Astro.Time` and `Astro.Earth` have been renamed or have changed return types. See the [changelog](CHANGELOG.md) for full details.

## Usage

> #### Installation and Configuration {: .Warning}
>
> It's important to install and configure `Astro` correctly before use.
> See the [installation](#installation) notes below.

The primary functions are:

### Solar functions

* `Astro.sunrise/3`
* `Astro.sunset/3`
* `Astro.solstice/2`
* `Astro.equinox/2`
* `Astro.hours_of_daylight/2`
* `Astro.sun_position_at/1`

### Lunar functions

* `Astro.moonrise/3`
* `Astro.moonset/3`
* `Astro.moon_position_at/1`
* `Astro.illuminated_fraction_of_moon_at/1`
* `Astro.date_time_new_moon_at_or_after/1`
* `Astro.date_time_new_moon_before/1`
* `Astro.date_time_new_moon_nearest/1`
* `Astro.lunar_phase_at/1`
* `Astro.lunar_phase_emoji/1`

### Examples
```elixir
  # Sunrise in Sydney on December 4th
  iex> Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
  {:ok, #DateTime<2019-12-04 05:37:08+11:00 AEDT Australia/Sydney>}

  # Sunset in Sydney on December 4th
  iex> Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
  {:ok, #DateTime<2019-12-04 19:53:20+11:00 AEDT Australia/Sydney>}

  # Sunset in the town of Alert in Nunavut, Canada
  # ...doesn't exist since there is no sunset in summer
  iex> Astro.sunset({-62.3481, 82.5018}, ~D[2019-07-01])
  {:error, :no_time}

  # ...or sunrise in winter
  iex> Astro.sunrise({-62.3481, 82.5018}, ~D[2019-12-04])
  {:error, :no_time}

  # Hours of daylight on December 7th in Sydney
  iex> Astro.hours_of_daylight {151.20666584, -33.8559799094}, ~D[2019-12-07]
  {:ok, ~T[14:18:44]}

  # No sunset in summer at high latitudes
  iex> Astro.hours_of_daylight {-62.3481, 82.5018}, ~D[2019-06-07]
  {:ok, ~T[23:59:59]}

  # No sunrise in winter at high latitudes
  iex> Astro.hours_of_daylight {-62.3481, 82.5018}, ~D[2019-12-07]
  {:ok, ~T[00:00:00]}

  # Calculate solstices for 2019
  iex> Astro.solstice 2019, :december
  {:ok, ~U[2019-12-22 04:19:19Z]}

  iex> Astro.solstice 2019, :june
  {:ok, ~U[2019-06-21 15:54:07Z]}

  # Calculate equinoxes for 2019
  iex> Astro.equinox 2019, :march
  {:ok, ~U[2019-03-20 21:58:28Z]}

  iex> Astro.equinox 2019, :september
  {:ok, ~U[2019-09-23 07:49:52Z]}
```

### Specifying a location

The desired location of sunrise or sunset can be specified as either:

* a tuple of longitude and latitude (note the order) such as `{-62.3481, 82.5018}`
* a tuple of longitude, latitude and elevation (note the order) such as `{-62.3481, 82.5018, 0}`.
* a `Geo.Point.t` struct
* a `Geo.PointZ.t` struct

### Location units and direction

For this implementation, the latitude and longitude of the functions in `Astro` are specified as follows:

* Longitude is `+` for eastern longitudes and `-` for western longitudes and specified in degrees.
* Latitude is `+` for northern latitudes and `-` for southern latitudes and specified in degrees.
* Elevation is specified in meters.

## References

* Thanks to @pinnymz for the [ruby-zmanim](https://github.com/pinnymz/ruby-zmanim) gem which has a well structured ruby implementation of sunrise / sunset and some core astronomical algorithms.

* Eventually all roads lead to the canonical book on the subject by Jean Meeus: [Astronomical Algorithms](https://www.amazon.com/Astronomical-Algorithms-Jean-Meeus/dp/0943396352)

* For the intersection of calendars and astronomy, [Calendrical Calculations](https://www.amazon.com/Calendrical-Calculations-Ultimate-Edward-Reingold/dp/1107683165) by Nachum Dershowitz and Edward M. Reingold remains the standard reference.

* [SkyField](https://rhodesmill.org/skyfield/) is a powerful astronomy library for Python. The sunrise/sunset calculations in Astro 2.0 are tested to return times within 1 minute of Skyfield's results. On average the [deviation](rise_and_set_comparisons.md) is 3.8 seconds for sunrise/sunset and 2.5 seconds for moonrise/moonset.

* [timeanddate.com](https://www.timeanddate.com/astronomy/) is a also a great web reference.

## Installation

### Add Astro as a dependency

Astro can be installed by adding `astro` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:astro, "~> 2.0"}
  ]
end
```

### Download the JPL Ephemeris

Astro requires the JPL DE440s ephemeris file (`de440s.bsp`, ~32 MB) for its rise/set calculations. After fetching dependencies, download it with the included mix task:

```
mix deps.get
mix astro.download_ephemeris
```

The file is placed in Astro's `priv` directory and loaded into memory at application start.

To use an alternative file path or a diffferent but compatible ephemeris (such as `de440.bsp`), configure the `:ephemeris` option in your `runtime.exs`:

```elixir
config :astro,
  ephemeris: "/path/to/de440.bsp"
```

The default path is `priv/de440s.bsp` relative to the Astro application directory.

### Install a time zone database

A time zone database is required in order to support time zone conversions. Two popular options are [tzdata](https://hex.pm/packages/tzdata) and [tz](https://hex.pm/packages/tz). The time zone database must be configured in `config.exs` or `runtime.exs` as the default time zone database.  For example:

```elixir
# If using tzdata
config :elixir,
  :time_zone_database, Tzdata.TimeZoneDatabase

# If using tz
config :elixir,
  :time_zone_database, Tz.TimeZoneDatabase
```

### Optionally Install TzWorld

For functions such as `Astro.sunrise/3` and `Astro.sunset/3` it is common to expect the returned date time to be in the time zone of the specified location. The library `tz_world` provides that capability and, if configured, will automatically be used by those functions.

It is expected that `tz_world` is configured for most applications although it is not formally required.

`tz_world` does however require the download of nearly 30Mb of geojson data and a non-trivial post-processing step to format the data for efficient use by Astro. This might not be suitable for embedded devices and therefore `Astro.sunrise/3`, `Astro.sunset/3`, `Astro.moonrise/3` and `Astro.moonset/3` take an optional `:time_zone_resolver` option to support the implementation of a custom function to resolve the time zone name from a given location.

The following steps should be following if `tz_world` is configured.

#### Install TzWorld Data

Get all dependencies and then install the data required to resolve a time zone from a location which is used by the dependency `tz_world`.

```
mix deps.get
mix tz_world.update

# If testing locally also install for the test environment
MIX_ENV=test mix tz_world.update
```

#### Add TzWorld to supervision tree

It is also required that `tz_world` be added to your applications supervision tree by adding the relevant `tz_world` backend to it in your `MyApp.Application` module:
```
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      .....
      # See the documentation for tz_world for the
      # various available backends. This is the recommended
      # backend.
      TzWorld.Backend.DetsWithIndexCache
    ]

    opts = [strategy: :one_for_one, name: Astro.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

#### Configure your application module

Make sure that you have configured your application in `mix.exs`:
```elixir
  def application do
    [
      mod: {MyApp.Application, [strategy: :one_for_one]},
      .....
    ]
  end
```

Documentation can be found at [https://hexdocs.pm/astro](https://hexdocs.pm/astro).

#### Developing Astro Locally

The Astro test suite requires a functioning tz_world database to be available in the test environment. Once all other dependencies are installed, execute:

```
MIX_ENV=test mix tz_world.update
```

## Astro improved rise and set algorithms

The implementation of the sun and moon rise and set calculations in Astro 2.0 is a JPL DE440s ephemeris scan-and-bisect algorithm. Specifically:

* Astro version 1.x: was a NOAA/Meeus analytical solar position (polynomial + periodic-term approximation of the Sun's coordinates, with three-point interpolation for the rise/set crossing). There was no moon rise/set calculation in Astro 1.x.

* Astro version 2: JPL DE440s ephemeris with coarse-scan and binary-search — the Sun's (or Moon's) position is computed directly from the JPL Development Ephemeris at each evaluation point, and the altitude zero-crossing is found by:
  * Coarse scan — sampling altitude at regular intervals (24-minute steps for the Sun, shorter for the Moon) to bracket sign changes
  * Bisection — narrowing each bracket to ~1 second precision

For the Moon, it's additionally fully topocentric — the observer's geocentric displacement is applied to the Moon's position before computing altitude, rather than using the Meeus h0 = 0.7275π − 0.5667° parallax-in-altitude approximation.

There is a [comparison document](rise_and_set_comparisons.md) demonstrating how Astro's calculations for rise and set compare with Skyfield (JPL DE440s), USNO (DE430),
and [timeanddate.com](https://timeanddate.com).
