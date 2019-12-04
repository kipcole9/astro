# Astro

![Build Status](https://api.cirrus-ci.com/github/kipcole9/astro.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/astro.svg)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/dw/astro.svg?)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/l/astro.svg)](https://hex.pm/packages/astro)

Astro is a library to provide basic astromonomical functions with a focus on functions that support solar, lunar and lunisolar calendars such as the Chinese, Hebrew and Persian calendars.

## Usage

The two primary functions are `Astro.sunrise/3` and `Astro.sunset/3`.

### Examples
```elixir
# Sunrise in Sydney on December 4th
iex> Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
{:ok, #DateTime<2019-12-04 05:37:00.000000+11:00 AEDT Australia/Sydney>}

# Sunset in Sydney on December 4th
iex> Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
{:ok, #DateTime<2019-12-04 19:53:00.000000+11:00 AEDT Australia/Sydney>}

# Sunset in the town of Alert NU, Canada
# ...doesn't exist since there is no sunset in summer
iex> Astro.sunset({-62.3481, 82.5018}, ~D[2019-07-01])
{:error, :no_time}

# ...or sunrise in winter
iex> Astro.sunrise({-62.3481, 82.5018}, ~D[2019-12-04])
{:error, :no_time}
```
### Specifying a location
The desired location of sunrise or sunset can be specified as either:

* a tuple of longitude and latitude (note the order) such as `{-62.3481, 82.5018}`
* a tuple of longitude, latitude and elevation (note the order) such as `{-62.3481, 82.5018, 0}`. The elevation is specified in meters.
* a `%Geo.Point{}` struct
* a `Geo.PointZ{}` struct

## Status

Early development, not ready for use beyond experimental.

## Solar functions

* [X] Sunrise
* [X] Sunset
* [ ] Solstice
* [ ] Equinox

## Lunar functions

* [ ] Moon phase
* [ ] Moon rise
* [ ] Moon set

## Installation

Astro can be installed by adding `astro` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:astro, "~> 0.1.0"}
  ]
end
```
Then:
```
mix deps.get
mix tz_world.update
```

Documentation can be found at [https://hexdocs.pm/astro](https://hexdocs.pm/astro).

