# Astro

![Build Status](https://api.cirrus-ci.com/github/kipcole9/astro.svg)
[![Hex.pm](https://img.shields.io/hexpm/v/astro.svg)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/dw/astro.svg?)](https://hex.pm/packages/astro)
[![Hex.pm](https://img.shields.io/hexpm/l/astro.svg)](https://hex.pm/packages/astro)

Astro is a library to provide basic astromonomical functions with a focus on functions that support solar, lunar and lunisolar calendars such as the Chinese, Hebrew and Persian calendars.

## Usage

The primary functions are:

* `Astro.sunrise/3`
* `Astro.sunset/3`
* `Astro.solstice/2`
* `Astro.equinox/2`
* `Astro.hours_of_daylight/2`

### Examples
```elixir
  # Sunrise in Sydney on December 4th
  iex> Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
  {:ok, #DateTime<2019-12-04 05:37:00.000000+11:00 AEDT Australia/Sydney>}

  # Sunset in Sydney on December 4th
  iex> Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
  {:ok, #DateTime<2019-12-04 19:53:00.000000+11:00 AEDT Australia/Sydney>}

  # Sunset in the town of Alert in Nunavut, Canada
  # ...doesn't exist since there is no sunset in summer
  iex> Astro.sunset({-62.3481, 82.5018}, ~D[2019-07-01])
  {:error, :no_time}

  # ...or sunrise in winter
  iex> Astro.sunrise({-62.3481, 82.5018}, ~D[2019-12-04])
  {:error, :no_time}

  # Hours of daylight on December 7th in Sydney
  iex> Astro.hours_of_daylight {151.20666584, -33.8559799094}, ~D[2019-12-07]
  {:ok, ~T[14:18:45]}

  # No sunset in summer at high latitudes
  iex> Astro.hours_of_daylight {-62.3481, 82.5018}, ~D[2019-06-07]
  {:ok, ~T[23:59:59]}

  # No sunrise in winter at high latitudes
  iex> Astro.hours_of_daylight {-62.3481, 82.5018}, ~D[2019-12-07]
  {:ok, ~T[00:00:00]}

  # Calculate solstices for 2019
  iex> Astro.solstice 2019, :december
  {:ok, ~U[2019-12-22 04:18:57Z]}

  iex> Astro.solstice 2019, :june
  {:ok, ~U[2019-06-21 15:53:45Z]}

  # Calculate equinoxes for 2019
  iex> Astro.equinox 2019, :march
  {:ok, ~U[2019-03-20 21:58:06Z]}

  iex> Astro.equinox 2019, :september
  {:ok, ~U[2019-09-23 07:49:30Z]}
```

### Specifying a location

The desired location of sunrise or sunset can be specified as either:

* a tuple of longitude and latitude (note the order) such as `{-62.3481, 82.5018}`
* a tuple of longitude, latitude and elevation (note the order) such as `{-62.3481, 82.5018, 0}`.
* a `Geo.Point.t` struct
* a `Geo.PointZ.t` struct

### Location units and direction

For this implementation, the latitude and longitude of the functions in `Astro` are specified as follows:

* Longitude is `+` for eastern longitudes and `-` for western longitudes and specified in degrees
* Latitude is `+` for northern latitudes and `-` for southern latitudes and specified in degrees
* Elevation is specified in meters

## References

* Thanks to @pinnymz for the [ruby-zmanim](https://github.com/pinnymz/ruby-zmanim) gem which has a well structured ruby implementation of sunrise / sunset and some core astronomical algorithms.

* Eventually all roads lead to the canonical book on the subject by Jean Meeus: [Astronomical Algorithms](https://www.amazon.com/Astronomical-Algorithms-Jean-Meeus/dp/0943396352)

* For the intersection of calendars and astronomy, [Calendrical Calculations](https://www.amazon.com/Calendrical-Calculations-Ultimate-Edward-Reingold/dp/1107683165) by Nachum Dershowitz and Edward M. Reingold remains the standard reference.

* On the web, [timeanddate.com](https://www.timeanddate.com/astronomy/) is a great reference. The sunrise/sunset calculations in this library are tested to return times within 1 minute of timeanddate.com results.

* [Wikipedia](https://wikipedia.com) for content to help describe the understanding behind some of the functions

## Installation

Astro can be installed by adding `astro` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:astro, "~> 0.3.0"}
  ]
end
```
Then get dependencies and install the data required to determine a time zone from a location which is used by the dependency `tz_world`.

```
mix deps.get
mix tz_world.update
```

Documentation can be found at [https://hexdocs.pm/astro](https://hexdocs.pm/astro).

