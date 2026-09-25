# Astro

[![Hex.pm](https://img.shields.io/hexpm/v/astro.svg)](https://hex.pm/packages/astro) [![Hex.pm](https://img.shields.io/hexpm/dw/astro.svg?)](https://hex.pm/packages/astro) [![Hex.pm](https://img.shields.io/hexpm/dt/astro.svg?)](https://hex.pm/packages/astro) [![Hex.pm](https://img.shields.io/hexpm/l/astro.svg)](https://hex.pm/packages/astro)

Astro is a library of accurate astronomical functions, with a focus on those that support solar, lunar and lunisolar calendars such as the Islamic, Chinese, Hebrew and Persian calendars.

## Features

* **Sunrise, sunset and twilight** — `Astro.sunrise/3` and `Astro.sunset/3` in the local time zone of any location, for the geometric, civil, nautical or astronomical horizon or any solar elevation you choose.

* **Moonrise and moonset** — `Astro.moonrise/3` and `Astro.moonset/3`, fully topocentric.

* **Equinoxes and solstices** — `Astro.equinox/3` and `Astro.solstice/3`, in UTC or any time zone.

* **Lunar phases and new moons** — `Astro.lunar_phase_at/1`, `Astro.lunar_phase_emoji/1`, and searches for the new moon or any phase before or after a moment.

* **Crescent visibility** — `Astro.new_visible_crescent/3` predicts the first visibility of the new crescent with the Odeh, Yallop or Schaefer criteria.

* **Positions of the sun and moon** — right ascension, declination and distance, and the sun's azimuth and elevation from any location.

* **Length of the day** — `Astro.hours_of_daylight/2` and `Astro.duration_of_daylight/2`, including the 24-hour days of polar summer.

* **JPL ephemeris** — positions come from JPL's DE440s, and a compact ephemeris covering 1900 to 2100 ships with the package, so no download is needed.

## Supported Elixir and OTP versions

Astro requires **Elixir 1.17** or later and **Erlang/OTP 26** or later.

## Installation

Add `astro` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:astro, "~> 2.6"}
  ]
end
```

### Install a time zone database

A time zone database is required for time zone conversions. Two popular options are [tzdata](https://hex.pm/packages/tzdata) and [tz](https://hex.pm/packages/tz). Configure it in `config.exs` or `runtime.exs` as the default time zone database, for example:

```elixir
# If using tzdata
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# If using tz
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

### Optionally install tz_world

The rise and set functions return a date time in the time zone of the location. The [tz_world](https://hex.pm/packages/tz_world) library resolves that time zone and, when it is a dependency, those functions use it automatically. Most applications configure it, although it is not required.

`tz_world` downloads about 50 MB of time zone boundary data, which may not suit an embedded device. `Astro.sunrise/3`, `Astro.sunset/3`, `Astro.moonrise/3` and `Astro.moonset/3` therefore also take a `:time_zone_resolver` option for a function of your own that resolves the time zone of a location.

If `tz_world` is a dependency, install its data:

```bash
mix deps.get
mix tz_world.update --force
```

Then start its backend in your application's supervision tree, either directly or through `Astro.Supervisor`:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # tz_world's recommended backend. Alternatively, list
      # Astro.Supervisor, which starts it.
      TzWorld.Backend.SpatialIndex
    ]

    options = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, options)
  end
end
```

## Quick start

```elixir
# Sunrise in Sydney on December 4th
iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 05:37:08.672884+11:00 AEDT Australia/Sydney>

# Sunset in Sydney on December 4th
iex> {:ok, datetime} = Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 19:53:20.995687+11:00 AEDT Australia/Sydney>

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
{:ok, ~U[2019-12-22 04:19:19.643304Z]}

iex> Astro.solstice 2019, :june
{:ok, ~U[2019-06-21 15:54:07.713837Z]}

# Calculate equinoxes for 2019
iex> Astro.equinox 2019, :march
{:ok, ~U[2019-03-20 21:58:28.749476Z]}

iex> Astro.equinox 2019, :september
{:ok, ~U[2019-09-23 07:49:52.677810Z]}
```

## Specifying a location

A location can be given as:

* a `{longitude, latitude}` tuple such as `{-62.3481, 82.5018}`. Note the order.

* a `{longitude, latitude, elevation}` tuple such as `{-62.3481, 82.5018, 0}`.

* a `Geo.Point` struct.

* a `Geo.PointZ` struct, which also carries an elevation.

Longitude is positive east and negative west, and latitude positive north and negative south, both in degrees. Elevation is in metres.

## The JPL ephemeris

Astro computes positions directly from a JPL Development Ephemeris. A compact ephemeris covering **1900 to 2100** is bundled with the package, so no download is required and Astro works as soon as it is installed.

The bundled file is extracted from JPL's DE440s kernel and contains only the Sun, Moon and Earth segments Astro uses. The Chebyshev coefficients are copied verbatim, so results are identical to those computed from the full JPL file for any date it covers.

### Dates outside 1900–2100

For dates beyond the bundled range, download the full DE440s kernel, which covers **1849 to 2150**:

```bash
mix astro.download_ephemeris
```

The file is placed in Astro's `priv` directory and takes precedence over the bundled ephemeris automatically. To place it elsewhere, pass `--dest` and configure the path:

```elixir
config :astro,
  ephemeris: "/path/to/de440s.bsp"
```

Dates outside the range of the loaded ephemeris return `{:error, :not_found}`.

### Using a different ephemeris

The `:ephemeris` option accepts any compatible DAF/SPK kernel, such as `de440.bsp` or `de441.bsp` for a much wider date range.

To build your own compact ephemeris over a different span of years — trading file size for coverage at roughly 42 KB per year — use:

```bash
mix astro.build_ephemeris --from 2000 --to 2050
```

Coverage cannot exceed that of the source kernel, which is 1849 to 2150 for the default DE440s. Pass `--source` to subset a wider kernel such as `de441.bsp`.

## Migration from Astro 1.x

The public functions in the `Astro` module keep the same signatures in Astro 2.x, which should mean a smooth migration in most cases. When upgrading:

* **Astro 2.x uses a JPL ephemeris.** A compact ephemeris covering 1900–2100 ships with the package, so no download is needed. For dates outside that range see [The JPL ephemeris](#the-jpl-ephemeris).

* **Numerical results may differ slightly.** The move from NOAA/Meeus polynomial approximations to the JPL DE440s ephemeris, combined with an improved ΔT computation, means that computed times for events such as equinoxes, solstices and new moons may shift by up to ~22 seconds.

* **Functions outside the `Astro` module may have changed.** Several functions in `Astro.Solar`, `Astro.Lunar`, `Astro.Time` and `Astro.Earth` have been renamed or have changed return types. See the [changelog](CHANGELOG.md) for full details.

## Rise and set algorithms

Astro 2 finds rise and set times from the JPL DE440s ephemeris by scanning and bisecting:

* **Astro 1.x** used a NOAA/Meeus analytical solar position: a polynomial and periodic-term approximation of the Sun's coordinates, with three-point interpolation for the rise and set crossing. It had no moonrise or moonset.

* **Astro 2** computes the Sun's or Moon's position directly from the JPL Development Ephemeris at each evaluation point, and finds the altitude's zero crossing with a coarse scan, sampling the altitude at regular intervals (24-minute steps for the Sun, shorter for the Moon) to bracket each sign change, followed by bisection of each bracket to about a second.

For the Moon it is also fully topocentric: the observer's displacement from the Earth's centre is applied to the Moon's position before its altitude is computed, rather than using Meeus's approximation of the parallax in altitude, h0 = 0.7275π − 0.5667°.

A [comparison document](rise_and_set_comparisons.md) shows how Astro's rise and set times compare with Skyfield (JPL DE440s), the USNO (DE430) and [timeanddate.com](https://timeanddate.com).

## References

* Thanks to @pinnymz for the [ruby-zmanim](https://github.com/pinnymz/ruby-zmanim) gem, a well-structured Ruby implementation of sunrise, sunset and some core astronomical algorithms.

* Eventually all roads lead to the canonical book on the subject by Jean Meeus, [Astronomical Algorithms](https://www.amazon.com/Astronomical-Algorithms-Jean-Meeus/dp/0943396352).

* For the intersection of calendars and astronomy, [Calendrical Calculations](https://www.amazon.com/Calendrical-Calculations-Ultimate-Edward-Reingold/dp/1107683165) by Nachum Dershowitz and Edward M. Reingold remains the standard reference.

* [Skyfield](https://rhodesmill.org/skyfield/) is a powerful astronomy library for Python. Astro's rise and set times are tested to be within a minute of Skyfield's; on average they [differ](rise_and_set_comparisons.md) by 3.8 seconds for sunrise and sunset and 2.5 seconds for moonrise and moonset.

* [timeanddate.com](https://www.timeanddate.com/astronomy/) is also a great web reference.

## Documentation

* **[Getting started](guides/getting_started.md)** — installation, the ephemeris, time zones, locations, options and errors.

* **[Solar events](guides/solar.md)** — sunrise, sunset, twilight, solar noon, the length of the day, and the equinoxes and solstices.

* **[Lunar events](guides/lunar.md)** — moonrise, moonset, phases, new moons and crescent visibility.

* **[Rise and set comparisons](rise_and_set_comparisons.md)** — Astro's results against Skyfield, the USNO and timeanddate.com.

The full API documentation is on [HexDocs](https://hexdocs.pm/astro).

## Development

The Astro test suite needs tz_world's data in the test environment. Once the other dependencies are installed, run:

```bash
MIX_ENV=test mix tz_world.update --force
```

## License

Astro is released under the [Apache License 2.0](LICENSE.md).
