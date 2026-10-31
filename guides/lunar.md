# Lunar events

Moonrise and moonset, the phase cycle, illumination, whether the new crescent can actually be seen, and lunar eclipses.

Examples use Sydney, `{151.20666584, -33.8559799094}`, and assume `:tz_world` is running so times come back in the zone at the location. See [Getting started](getting_started.html) if that is not set up.

## Moonrise and moonset

```elixir
iex> {:ok, datetime} = Astro.moonrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 12:20:54.388717+11:00 AEDT Australia/Sydney>

iex> {:ok, datetime} = Astro.moonset({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 01:13:25.822599+11:00 AEDT Australia/Sydney>
```

They take the same options as the solar equivalents, minus `:solar_elevation`:

```elixir
iex> Astro.moonrise({151.20666584, -33.8559799094}, ~D[2019-12-04], time_zone: :utc)
{:ok, ~U[2019-12-04 01:20:54.388717Z]}
```

Note the moon set *before* it rose on this date. That is not an error. The moon rises roughly 50 minutes later each day, so on about one day a month it skips a calendar date entirely and the rise and set you get belong to different cycles. Expect `{:error, :no_time}` on those days, and do not assume a rise always precedes the set on the same date.

## Phase

`lunar_phase_at/1` returns the phase angle in degrees — the elongation of the moon from the sun:

| Angle | Phase |
|---|---|
| 0° | New moon |
| 90° | First quarter |
| 180° | Full moon |
| 270° | Last quarter |

```elixir
iex> Astro.lunar_phase_at(~D[2019-12-04])
86.84254410522834
```

Just under 90°, so a day or so before first quarter.

`lunar_phase_emoji/1` turns an angle into the matching glyph, which is handy for display:

```elixir
iex> Astro.lunar_phase_emoji(86.8427160627657)
"🌓"

iex> Astro.lunar_phase_emoji(180)
"🌕"
```

The emoji follow the northern-hemisphere convention, where a waxing moon is lit on the right. Seen from Sydney the same moon is lit on the left, so the glyph will look mirrored to a southern viewer.

## Illumination

The fraction of the visible disc that is lit, from 0.0 to 1.0:

```elixir
iex> Astro.illuminated_fraction_of_moon_at(~D[2019-12-04])
0.47390993113962154
```

This is not a linear function of the phase angle. At the quarters the disc is half lit, but illumination changes fastest there and slowest near new and full, which is why a "nearly full" moon looks full for several nights.

## Finding a phase in time

Rather than asking what the phase is on a date, these search for when a phase occurs. All return UTC, because a phase is a single instant worldwide.

```elixir
iex> Astro.date_time_new_moon_before(~D[2019-12-04])
{:ok, ~U[2019-11-26 15:05:35.158794Z]}

iex> Astro.date_time_new_moon_at_or_after(~D[2019-12-04])
{:ok, ~U[2019-12-26 05:13:07.574961Z]}
```

`date_time_new_moon_nearest/1` picks whichever of the two is closer.

For phases other than new, give the angle:

```elixir
iex> Astro.date_time_lunar_phase_at_or_after(~D[2019-12-04], 180)
{:ok, ~U[2019-12-12 05:12:15.756775Z]}
```

`date_time_lunar_phase_at_or_before/2` searches backwards. Together these are what lunar and lunisolar calendars are built from — the new moon instants set the month boundaries.

## Crescent visibility

Knowing when the new moon occurs is not the same as knowing when anyone can see the crescent that follows it. That gap matters for calendars that begin a month on first sighting.

`new_visible_crescent/3` grades the chance of sighting at sunset on a date:

| Code | Meaning |
|---|---|
| `:A` | Visible to the naked eye |
| `:B` | Visible with optical aid |
| `:C` | May need optical aid |
| `:D` | Not visible with optical aid |
| `:E` | Not visible |

```elixir
iex> Astro.new_visible_crescent({-0.1275, 51.5072}, ~D[2025-03-31])
{:ok, :A}
```

The same evening from Sydney, for a different lunation, is hopeless — the moon sets too soon after the sun:

```elixir
iex> Astro.new_visible_crescent({151.20666584, -33.8559799094}, ~D[2019-12-26])
{:ok, :E}
```

Three criteria are available, and they disagree near the limit, which is the interesting part:

* `:odeh` (the default) — Odeh (2004), an empirical polynomial fitted to 737 observations using topocentric arc of vision.

* `:yallop` — Yallop (1997), the same shape of model over 295 observations, using geocentric arc of vision.

* `:schaefer` — Schaefer (1988/2000), a physical model of atmospheric extinction rather than a fit to observations. It accepts an extinction coefficient via a fourth argument.

```elixir
iex> Astro.new_visible_crescent({-0.1275, 51.5072}, ~D[2025-03-31], :yallop)
{:ok, :A}
```

`{:error, :no_sunset}` means a polar day with no sunset to compute from: a genuine astronomical condition, not a failure.

## Lunar eclipses

A lunar eclipse is the Moon passing through the Earth's shadow. `lunar_eclipse_at_or_after/2` and `lunar_eclipse_before/2` find one and return an `Astro.Lunar.Eclipse`: its type (`:penumbral`, `:partial` or `:total`), greatest eclipse, gamma, the penumbral and umbral magnitudes, and the contacts as the Moon enters and leaves the penumbra and the umbra, `nil` for those it does not have. They are the same instants everywhere, so they are in UTC.

```elixir
iex> {:ok, eclipse} = Astro.lunar_eclipse_at_or_after(~D[2025-01-01])
iex> {eclipse.type, DateTime.truncate(eclipse.total_begins, :second)}
{:total, ~U[2025-03-14 06:26:04Z]}
iex> DateTime.truncate(eclipse.total_ends, :second)
~U[2025-03-14 07:31:28Z]
```

The Earth's atmosphere makes its shadow a little larger than geometry alone. By default the shadow is enlarged as Danjon proposed, as NASA's catalogue does; `shadow: :chauvenet` gives the larger shadow of the older almanacs, which adds about 0.005 to the umbral magnitude.

```elixir
iex> {:ok, eclipse} = Astro.lunar_eclipse_at_or_after(~D[2025-01-01], shadow: :chauvenet)
iex> Float.round(eclipse.umbral_magnitude, 3)
1.183
```

`lunar_eclipse_at/3` gives the same eclipse in the location's time zone with the Moon's altitude at greatest eclipse and at each contact, or `{:error, :not_visible}` where the Moon is below the horizon throughout:

```elixir
iex> dallas = {-96.80, 32.78}
iex> {:ok, local} = Astro.lunar_eclipse_at(dallas, ~D[2025-01-01], time_zone: "America/Chicago")
iex> DateTime.truncate(local.total_begins, :second)
#DateTime<2025-03-14 01:26:04-05:00 CDT America/Chicago>
iex> Float.round(local.moon_altitudes.greatest, 1)
59.0

iex> Astro.lunar_eclipse_at({77.21, 28.61}, ~D[2025-01-01])
{:error, :not_visible}
```

## Position of the moon

`moon_position_at/1` gives the geocentric celestial position as a `Geo.PointZ` — right ascension and declination in degrees, distance in metres:

```elixir
iex> Astro.moon_position_at(~D[2019-12-04]) |> Astro.Location.round(6)
%Geo.PointZ{
  coordinates: {-18.270609, -12.619441, 403540383.151343},
  srid: nil,
  properties: %{reference: :celestial, object: :moon}
}
```

That distance, roughly 403,500 km, is near apogee — the moon's distance varies by about 13% over a month, which is where "supermoon" comes from.
