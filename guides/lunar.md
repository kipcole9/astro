# Lunar events

Moonrise and moonset, the phase cycle, illumination, and whether the new
crescent can actually be seen.

Examples use Sydney, `{151.20666584, -33.8559799094}`, and assume `:tz_world` is
running so times come back in the zone at the location. See
[Getting started](getting_started.html) if that is not set up.

## Moonrise and moonset

```elixir
iex> {:ok, datetime} = Astro.moonrise({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 12:20:56.695846+11:00 AEDT Australia/Sydney>

iex> {:ok, datetime} = Astro.moonset({151.20666584, -33.8559799094}, ~D[2019-12-04])
iex> datetime
#DateTime<2019-12-04 01:13:28.212125+11:00 AEDT Australia/Sydney>
```

They take the same options as the solar equivalents, minus `:solar_elevation`:

```elixir
iex> Astro.moonrise({151.20666584, -33.8559799094}, ~D[2019-12-04], time_zone: :utc)
{:ok, ~U[2019-12-04 01:20:56.695846Z]}
```

Note the moon set *before* it rose on this date. That is not an error. The moon
rises roughly 50 minutes later each day, so on about one day a month it skips a
calendar date entirely and the rise and set you get belong to different cycles.
Expect `{:error, :no_time}` on those days, and do not assume a rise always
precedes the set on the same date.

## Phase

`lunar_phase_at/1` returns the phase angle in degrees — the elongation of the
moon from the sun:

| Angle | Phase |
|---|---|
| 0° | New moon |
| 90° | First quarter |
| 180° | Full moon |
| 270° | Last quarter |

```elixir
iex> Astro.lunar_phase_at(~D[2019-12-04])
86.8427160627657
```

Just under 90°, so a day or so before first quarter.

`lunar_phase_emoji/1` turns an angle into the matching glyph, which is handy for
display:

```elixir
iex> Astro.lunar_phase_emoji(86.8427160627657)
"🌓"

iex> Astro.lunar_phase_emoji(180)
"🌕"
```

The emoji follow the northern-hemisphere convention, where a waxing moon is lit
on the right. Seen from Sydney the same moon is lit on the left, so the glyph
will look mirrored to a southern viewer.

## Illumination

The fraction of the visible disc that is lit, from 0.0 to 1.0:

```elixir
iex> Astro.illuminated_fraction_of_moon_at(~D[2019-12-04])
0.4739255300395426
```

This is not a linear function of the phase angle. At the quarters the disc is
half lit, but illumination changes fastest there and slowest near new and full,
which is why a "nearly full" moon looks full for several nights.

## Finding a phase in time

Rather than asking what the phase is on a date, these search for when a phase
occurs. All return UTC, because a phase is a single instant worldwide.

```elixir
iex> Astro.date_time_new_moon_before(~D[2019-12-04])
{:ok, ~U[2019-11-26 15:05:39.392335Z]}

iex> Astro.date_time_new_moon_at_or_after(~D[2019-12-04])
{:ok, ~U[2019-12-26 05:13:15.112931Z]}
```

`date_time_new_moon_nearest/1` picks whichever of the two is closer.

For phases other than new, give the angle:

```elixir
iex> Astro.date_time_lunar_phase_at_or_after(~D[2019-12-04], 180)
{:ok, ~U[2019-12-12 05:12:21.264711Z]}
```

`date_time_lunar_phase_at_or_before/2` searches backwards. Together these are
what lunar and lunisolar calendars are built from — the new moon instants set
the month boundaries.

## Crescent visibility

Knowing when the new moon occurs is not the same as knowing when anyone can see
the crescent that follows it. That gap matters for calendars that begin a month
on first sighting.

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

The same evening from Sydney, for a different lunation, is hopeless — the moon
sets too soon after the sun:

```elixir
iex> Astro.new_visible_crescent({151.20666584, -33.8559799094}, ~D[2019-12-26])
{:ok, :E}
```

Three criteria are available, and they disagree near the limit, which is the
interesting part:

* `:odeh` (the default) — Odeh (2006), an empirical polynomial fitted to 737
  observations using topocentric arc of vision.
* `:yallop` — Yallop (1997), the same shape of model over 295 observations,
  using geocentric arc of vision.
* `:schaefer` — Schaefer (1988/2000), a physical model of atmospheric
  extinction rather than a fit to observations. It accepts an extinction
  coefficient via a fourth argument.

```elixir
iex> Astro.new_visible_crescent({-0.1275, 51.5072}, ~D[2025-03-31], :yallop)
{:ok, :A}
```

Two error cases are worth distinguishing: `{:error, :no_sunset}` means a polar
day with no sunset to compute from, a genuine astronomical condition, while
`{:error, :not_found}` means the date is outside the loaded ephemeris.

## Position of the moon

`moon_position_at/1` gives the geocentric celestial position as a `Geo.PointZ` —
right ascension and declination in degrees, distance in metres:

```elixir
iex> Astro.moon_position_at(~D[2019-12-04])
%Geo.PointZ{
  coordinates: {-18.265497077930355, -12.617389187144866, 403536594.40775913},
  srid: nil,
  properties: %{reference: :celestial, object: :moon}
}
```

That distance, roughly 403,500 km, is near apogee — the moon's distance varies
by about 13% over a month, which is where "supermoon" comes from.
