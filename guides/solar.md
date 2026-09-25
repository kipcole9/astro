# Solar events

Everything Astro derives from the position of the sun: rise and set, the twilights, solar noon, the length of the day, and the equinoxes and solstices.

Examples use Sydney, `{151.20666584, -33.8559799094}`, and assume `:tz_world` is running so times come back in the zone at the location. See [Getting started](getting_started.html) if that is not set up.

## Sunrise and sunset

```elixir
iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 05:37:08.672884+11:00 AEDT Australia/Sydney>

iex> {:ok, datetime} = Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 19:53:20.995687+11:00 AEDT Australia/Sydney>
```

Both return `{:error, :no_time}` where the event does not happen — inside the Arctic or Antarctic circles around the solstices:

```elixir
iex> Astro.sunset({-62.3481, 82.5018}, ~D[2019-07-01])
{:error, :no_time}
```

That is a real astronomical answer, not a failure. It is distinct from `{:error, :not_found}`, which means the date is outside the loaded ephemeris.

## Twilight

`:solar_elevation` sets how far the sun must be below the horizon to count as the event. It is measured as a zenith angle, so larger numbers mean the sun is lower and the event is earlier in the morning and later in the evening.

The default of `90.0` is not geometric sunrise. It includes the standard allowances for atmospheric refraction and the sun's apparent radius, which is what makes it match the moment the disc appears to touch the horizon.

| Value | Zenith | Meaning |
|---|---|---|
| `90.0` (default) | 90.0° | The disc appears on the horizon |
| `:civil` | 96.0° | Enough natural light for most outdoor activity |
| `:nautical` | 102.0° | Horizon just visible; stars usable for navigation |
| `:astronomical` | 108.0° | Beyond this, astronomical observation is impractical |

```elixir
iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04], solar_elevation: :civil)
iex> datetime
#DateTime<2019-12-04 05:08:29.916808+11:00 AEDT Australia/Sydney>

iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04], solar_elevation: :nautical)
iex> datetime
#DateTime<2019-12-04 04:33:25.167049+11:00 AEDT Australia/Sydney>

iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04], solar_elevation: :astronomical)
iex> datetime
#DateTime<2019-12-04 03:55:20.466748+11:00 AEDT Australia/Sydney>
```

The same option applies to sunset, where it gives the end of that twilight rather than its start:

```elixir
iex> {:ok, datetime} = Astro.sunset({151.20666584, -33.8559799094}, ~D[2019-12-04], solar_elevation: :civil)
iex> datetime
#DateTime<2019-12-04 20:22:02.773030+11:00 AEDT Australia/Sydney>
```

Any float works if you need a threshold of your own — a local religious observance, or an aviation rule:

```elixir
iex> {:ok, datetime} = Astro.sunrise({151.20666584, -33.8559799094}, ~D[2019-12-04], solar_elevation: 95.0)
iex> datetime
#DateTime<2019-12-04 05:14:08.317668+11:00 AEDT Australia/Sydney>
```

## Solar noon

The moment the sun crosses the local meridian, which is when it is highest. It is not 12:00 local time, and the gap between the two varies through the year by up to about a quarter of an hour, because the Earth's orbit is elliptical and its axis is tilted.

```elixir
iex> Astro.solar_noon({151.20666584, -33.8559799094}, ~D[2019-12-04])
{:ok, ~U[2019-12-04 01:44:53Z]}
```

## Length of the day

Two functions, differing in return type rather than in the calculation.

`hours_of_daylight/2` returns a `t:Time.t/0`, which cannot exceed a day and so saturates at `~T[23:59:59]` during a polar summer:

```elixir
iex> Astro.hours_of_daylight({151.20666584, -33.8559799094}, ~D[2019-12-07])
{:ok, ~T[14:18:44]}
```

`duration_of_daylight/2` returns a `t:Duration.t/0` and can therefore express a full 24 hours honestly:

```elixir
iex> Astro.duration_of_daylight({151.20666584, -33.8559799094}, ~D[2019-12-07])
{:ok, %Duration{hour: 14, minute: 18, second: 44}}
```

Prefer `duration_of_daylight/2` for anywhere inside the polar circles, where the `Time` version cannot tell a 24-hour day from one a second short of it.

## Equinoxes and solstices

These are instants, not dates, and they are the same instant everywhere on Earth — so they are returned in UTC unless you ask for a time zone.

```elixir
iex> Astro.equinox(2019, :march)
{:ok, ~U[2019-03-20 21:58:28.749476Z]}

iex> Astro.solstice(2019, :december)
{:ok, ~U[2019-12-22 04:19:19.643304Z]}
```

`:march` and `:september` are valid for `equinox/3`; `:june` and `:december` for `solstice/3`. Naming the month rather than "spring" or "summer" avoids the hemisphere ambiguity: the December solstice is midsummer in Sydney and midwinter in London.

The civil date of the instant depends on where you are. Japan's Vernal Equinox Day is the date of the March equinox in Japan, which is a day later than the UTC date in about a third of years. The `:time_zone` option returns the instant in that zone:

```elixir
iex> {:ok, equinox} = Astro.equinox(2019, :march, time_zone: "Asia/Tokyo")
iex> DateTime.to_date(equinox)
~D[2019-03-21]
```

A named time zone is looked up in `:time_zone_database`, which defaults to the configured database (`Calendar.get_time_zone_database/0`). With none configured only UTC is known, and a named zone returns `{:error, :utc_only_time_zone_database}`.

Both are documented for 1000 CE to 3000 CE and return `{:error, :year_out_of_range}` outside it.

## Position of the sun

For the geometry itself rather than the events derived from it.

`sun_azimuth_elevation/2` gives the sun's apparent position from a place at an instant, as `{azimuth, elevation}` in degrees. Azimuth is measured clockwise from north; elevation is above the horizon.

```elixir
iex> Astro.sun_azimuth_elevation({151.20666584, -33.8559799094}, ~U[2019-12-04 02:00:00Z])
{343.33472178197934, 77.8645848744289}
```

`sun_position_at/1` gives the geocentric celestial position as a `Geo.PointZ` — right ascension and declination in degrees, with distance in metres:

```elixir
iex> Astro.sun_position_at(~D[2019-12-04])
%Geo.PointZ{
  coordinates: {-110.01065731989793, -22.162056908520697, 147435883428.31708},
  srid: nil,
  properties: %{reference: :celestial, object: :sun}
}
```

`sun_apparent_longitude/1` gives ecliptic longitude in degrees, which is what solar-term and zodiacal calculations are built on:

```elixir
iex> Astro.sun_apparent_longitude(~D[2019-12-04])
251.5228008540026
```
