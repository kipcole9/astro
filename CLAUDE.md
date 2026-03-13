# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
mix compile                        # Compile
mix test                           # Run all tests (~40s, 607 tests)
mix test test/sunrise_sunset_test.exs  # Run a single test file
mix test test/sunrise_sunset_test.exs:121  # Run a single test by line
mix format                         # Format code
mix dialyzer                       # Static type analysis
mix docs                           # Generate documentation
```
Make sure the TzWorld data is installed in the `:dev` and `:test` environments by running the following:
- `mix TzWorld.update`
- `MIX_ENV=test mix TzWorld.update`

Tests require `TzWorld` backend. The test helper starts `Astro.Supervisor` if `TzWorld` is loaded. Outside tests (e.g. `mix run` scripts), call `Astro.Supervisor.start_link()` manually or pass an explicit `:time_zone` option.

`mix test` requires the current working directory to be the project root directory.

## Architecture

**Astro** is an astronomical calculations library for Elixir. The public API is in `Astro` (`lib/astro.ex`); implementation lives in submodules.

### Two generations of algorithms coexist

| Domain | Old (Meeus/NOAA analytical) | New (JPL DE440s numerical) |
|---|---|---|
| Sunrise/sunset | `Astro.Solar.sun_rise_or_set/3` | `Astro.Solar.SunRiseSet` |
| Moonrise/moonset | — | `Astro.Lunar.MoonRiseSet` |
| Solar position | `Astro.Solar` (polynomial series) | `Astro.Ephemeris` + `Astro.Coordinates` |

The new rise/set modules use a **scan-and-bisect** algorithm: coarse-scan altitude every 24 minutes to bracket sign changes, then binary-search each bracket to ±0.01 s. Positions are evaluated directly from the JPL DE440s ephemeris (`priv/de440s.bsp`, ~32 MB), loaded into `:persistent_term` at application start.

### Key modules

- **`Astro.Ephemeris.Kernel`** — SPK/DAF binary parser; loads Chebyshev polynomial segments for Sun (NAIF 10), Moon (301), Earth (399), EMB (3).
- **`Astro.Ephemeris`** — Moon geocentric position from kernel; chains Moon/EMB − Earth/EMB segments.
- **`Astro.Coordinates`** — UTC↔TDB conversion, ΔT interpolation, IAU 1976 precession (Lieske) and IAU 1980 nutation (Wahr, 17-term), GAST, rotation matrices. Uses standard math rotation convention (R₃(α) = Rz(−α) in astronomy texts).
- **`Astro.Earth`** — Nutation (full IAU 1980 series returning `{Δψ, Δε, ε₀}`), obliquity, refraction/semi-diameter constants, adjusted solar elevation.
- **`Astro.Solar.SunRiseSet`** — Sunrise/sunset via JPL ephemeris. Supports `:solar_elevation` option (`:geometric`, `:civil`, `:nautical`, `:astronomical`, or custom degrees).
- **`Astro.Lunar.MoonRiseSet`** — Fully topocentric moonrise/moonset (corrects the ~2–3 min RA-parallax error in Meeus Ch.15). Event condition: altitude = −(34′ refraction + semi-diameter).
- **`Astro.Time`** — Julian day, moment (fractional days since epoch), Julian centuries, sidereal time, timezone resolution.
- **`Astro.Math`** — Trig in degrees, `mod/2`, polynomial evaluation (`poly/2`), angle normalization.

### Timezone resolution

Rise/set functions accept options:
- `:time_zone` — zone name string, `:utc`, or `:default` (resolve from coordinates via `TzWorld`)
- `:time_zone_database` — `Tz.TimeZoneDatabase` (configured in `config/config.exs`) or `Tzdata.TimeZoneDatabase`
- `:time_zone_resolver` — custom 1-arity fn `(%Geo.Point{}) → {:ok, String.t()}`

### Conventions

- **Location order**: `{longitude, latitude}` (matching `Geo.Point`). West/south negative.
- **Angles**: degrees throughout; `to_radians/1` and `to_degrees/1` macros for conversion.
- **Time scales**: moments (float days since 0000-01-01 epoch), Julian centuries from J2000.0, dynamical time (TDB seconds past J2000.0 for ephemeris).
- Use `Astro.Time.dynamical_time_from_moment/1` to convert a moment to dynamical time (TDB seconds past J2000.0)
- Use `Astro.Time.dynamical_time_to_moment/1` to convert dynamical time back to a moment
- Use `Astro.Time.julian_centuries_from_dynamical_time/1` to convert dynamical time to Julian centuries from J2000.0
- Functions in Astro take time parameters as dates or datetimes
- Functions in Astro.Solar, Astro.Lunar, Astro.Lunar.MoonRiseSet and Astro.Solar.SunRiseSet all take a **moment** as a time parameter.
- Functions in Astro validate their arguments and convert their date or datetime arguments into moment timescales. It is these moments that are passed to implementation functions.
- Functions in Astro.Solar, Astro.Lunar, Astro.Lunar.MoonRiseSet and Astro.Solar.SunRiseSet should avoid converting moments into dates or datetimes.
- Use Astro.Time.date_time_to_moment to convert dates and datetimes to a moment
- Use Astro.Time.date_time_from_moment to convert a moment to a datetime
- **Results**: `{:ok, value}` or `{:error, :no_time | :time_zone_not_found | ...}`.
- **Guards**: `is_lat/1`, `is_lng/1`, `is_alt/1` in `Astro.Guards`.


### Test data

Sunrise/sunset tests (`test/sunrise_sunset_test.exs`) validate 343 cases across 5 cities against the JPL-based algorithm. Moonrise/moonset tests (`test/moon_rise_set_test.exs`) validate 70 cases against USNO data with ±1 minute tolerance. CSV test data lives in `test/data/`. Test support modules compile from `test/support/`.

### Umm al-Qura calendar

`Astro.UmAlQura.Tabular` and `Astro.UmAlQura.Astronomical` implement the Islamic Hijri calendar. Property-based equivalence tests compare the two implementations.

## Dependencies

- **`geo`** — `Geo.Point` / `Geo.PointZ` coordinate types (required)
- **`tz`** or **`tzdata`** — time zone database (optional, one required for local times)
- **`tz_world`** — location → timezone resolution (optional)
- **`priv/de440s.bsp`** — JPL DE440s ephemeris file (required at runtime, not in hex package)
