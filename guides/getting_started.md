# Getting started

Astro computes the position of the sun and moon, and the events that follow from
them: sunrise and sunset, moonrise and moonset, twilight, daylight hours, lunar
phases, equinoxes and solstices.

Positions come from JPL's DE440s ephemeris rather than from a closed-form
approximation, so results agree with published almanacs to within a second or
two over the supported date range.

## Installation

Add `astro` to your dependencies:

```elixir
def deps do
  [
    {:astro, "~> 2.6"},
    {:tz, "~> 0.28"},
    {:tz_world, "~> 2.4"}
  ]
end
```

Only `astro` is required. The other two are optional and cover two separate
concerns, described below.

## The ephemeris

A compact ephemeris covering 1900 to 2100 ships inside the package, so Astro
works immediately after `mix deps.get` with no download step.

If you need dates outside that range, download the full JPL DE440s kernel, which
covers 1849 to 2150:

```bash
mix astro.download_ephemeris
```

The downloaded file takes precedence over the bundled one when present. To keep
it somewhere specific, configure the path:

```elixir
config :astro,
  ephemeris: "/path/to/de440s.bsp"
```

Setting an explicit path is worth doing in production. The default cache location
falls back to the system temporary directory when the user has no writable home
directory — common for service accounts in containers — and that is ephemeral.

## Time zones

Astro answers two different questions about time zones, and they need different
things from you.

**Converting an instant to a named zone** requires a `Calendar.TimeZoneDatabase`.
Add either `:tz` or `:tzdata`. Astro prefers Tz.TimeZoneDatabase when both are
loaded, and the `:elixir` `:time_zone_database` configuration always wins if you
set it.

**Working out which zone a coordinate falls in** requires `:tz_world`, plus its
backend in your supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      TzWorld.Backend.SpatialIndex
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Then install its data, once:

```bash
mix tz_world.update --force
```

`--force` is needed on a first install because the package ships no data
directory for the download to land in.

Without `:tz_world` you can still use every function — pass `time_zone: :utc`, or
name a zone explicitly, or supply your own `:time_zone_resolver`.

## Locations

A location is a longitude/latitude pair, in that order. Longitude first is the
GeoJSON convention and catches people out, so it is worth stating plainly: east
is positive, north is positive.

Three forms are accepted, and they are equivalent:

```elixir
iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 05:37:08.672884+11:00 AEDT Australia/Sydney>

iex> {:ok, datetime} = Astro.sunrise(%Geo.Point{coordinates: {151.20666584, -33.8559799094}}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 05:37:08.672884+11:00 AEDT Australia/Sydney>
```

`Geo.PointZ` also works and carries an altitude, which affects rise and set times
slightly.

## Options

`sunrise/3`, `sunset/3`, `moonrise/3` and `moonset/3` share a keyword list:

* `:time_zone` — `:default` (the zone at the location, the default), `:utc`, or
  any zone name your time zone database knows.

* `:time_zone_database` — a `Calendar.TimeZoneDatabase` module. Defaults to
  whichever of `:tz` or `:tzdata` is loaded.

* `:time_zone_resolver` — a 1-arity function taking a `Geo.Point` and returning
  `{:ok, zone_name}` or `{:error, reason}`. Defaults to `TzWorld.timezone_at/1`.

* `:solar_elevation` — how far below the horizon counts as the event. Sun events
  only; see the [Solar guide](solar.html).

The defaults in force are:

```elixir
iex> Astro.default_options()
[solar_elevation: 90.0, time_zone: :default, time_zone_database: Tz.TimeZoneDatabase]
```

Asking for UTC avoids the coordinate-to-zone lookup entirely, so it works with no
`:tz_world` installed:

```elixir
iex> Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04], time_zone: :utc)
{:ok, ~U[2019-12-04 18:37:05.706214Z]}
```

Note this is the sunrise falling inside the UTC day, which near a date boundary is
a different event from the one inside the local day.

## Errors

Astro returns tagged tuples rather than raising, including for the awkward cases
that are genuine astronomy rather than bad input:

* `{:error, :no_time}` — the event does not occur on that date at that place. A
  polar summer has no sunset:

  ```elixir
  iex> Astro.sunset({-62.3481, 82.5018}, ~D[2019-07-01])
  {:error, :no_time}
  ```

* `{:error, :not_found}` — the date lies outside the loaded ephemeris. Download
  the full kernel to widen the range.

* `{:error, :time_zone_not_found}` — the coordinate is in no time zone, typically
  open ocean.

* `{:error, :time_zone_not_resolved}` — `:tz_world` is not a dependency and no
  `:time_zone_resolver` was given.

* `{:error, :tz_world_data_not_installed}` — `:tz_world` is installed but its data
  has never been downloaded. Run `mix tz_world.update --force`.

* `{:error, :year_out_of_range}` — `equinox/2` and `solstice/2` are documented
  for 1000 CE to 3000 CE.

## Where next

* [Solar guide](solar.html) — sunrise, sunset, twilight, daylight, equinoxes and
  solstices.
* [Lunar guide](lunar.html) — moonrise, moonset, phases, illumination and
  crescent visibility.
