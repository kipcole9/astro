# JPL positions with a Meeus fallback

**Status:** in progress, 2026-10-31

Astro computes the Sun and Moon from the JPL DE440s ephemeris, which covers 1900–2100 in the bundled file and 1849–2150 in the full kernel. Calendars need dates far outside that span, so Astro must answer for any date: from JPL where the loaded ephemeris covers the moment, and from the Meeus series where it does not.

## Objective

Calendrical, Tempo and every other consumer deal only with Astro's API. They never check ephemeris coverage, never see `{:error, :not_found}` for a date outside the ephemeris, and never choose between JPL and Meeus. Which source answered is Astro's internal concern.

## Where things stand (2.9.0)

* **Still Meeus** — `Astro.equinox/3` and `Astro.solstice/3` use the Meeus Ch.27 closed form and refuse years outside 1000–3000. `Astro.date_time_new_moon_before/1` and `date_time_new_moon_at_or_after/1` use the Meeus Ch.49 series alone.

* **JPL with a Meeus fallback** — only `Astro.Solar.solar_ecliptic_longitude/1`, and the two solar-longitude searches built on it.

* **JPL with no fallback** — every other Sun and Moon position. `Astro.Solar` and `Astro.Lunar` match `{:ok, _} =` on the ephemeris and raise `MatchError` outside it; the `Astro` functions, sunrise and sunset, moonrise and moonset, and crescent visibility check coverage first and return `{:error, :not_found}`.

* **Calendrical works around the gap** — `Calendrical.Islamic.Visibility` calls `Astro.Ephemeris.check_coverage/2` and raises `Calendrical.UnsupportedDateRangeError` with `range: :jpl_ephemeris` outside it. The lunisolar compiler already relies on the solar-longitude fallback.

## Design

* **The code is a learning guide.** The implementation is meant to teach astronomical calculation to people new to it, so each body's algorithms live together in its own module, with the same layout, naming and documentation for the Sun and the Moon.

* **Sun algorithms in `Astro.Solar`, Moon algorithms in `Astro.Lunar`.** Each module documents its two sources and holds the analytical series (`analytical_solar_position/1` and `analytical_solar_ecliptic_position/1`; `analytical_lunar_position/1` and `analytical_lunar_ecliptic_position/1`) beside the orbital elements and fundamental arguments they are built from. They take a moment and return the same shapes and units as `solar_position/1` (astronomical units) and `lunar_position/1` (metres), with right ascension in the range 0 to 360.

* **`Astro.Ephemeris` stays JPL only.** It reads the kernel and returns `{:ok, position}` or `{:error, :not_found}`. `Astro.Solar` and `Astro.Lunar` choose: the JPL position where the kernel covers the moment, otherwise the analytical series. The rise and set searches and every other caller ask `Astro.Solar` and `Astro.Lunar` for positions, so none of them sees a coverage error.

* **Shared conversions in `Astro.Coordinates`.** `ecliptic_to_equatorial/3` turns an ecliptic position into right ascension and declination for both bodies.

* **The Sun.** Apparent longitude from the 49-term periodic series Astro carried until 2.8.0 as `sun_apparent_longitude_alt/1` (deleted in 8f61281), with the nutation in longitude converted from radians to degrees, which that function omitted; latitude zero; distance from the Keplerian ellipse; equatorial coordinates through the true obliquity of `Astro.Earth.nutation/1`. It replaces the private Ch.25 series in `Astro.Solar.solar_ecliptic_longitude/1`'s fallback.

* **The Moon.** The Meeus Ch.47 series for longitude, latitude and distance, recovered from `8f61281^:lib/astro/lunar.ex`, with the nutation in longitude added, then to equatorial coordinates the same way.

* **Callers become total.** With the choice made in `Astro.Solar` and `Astro.Lunar`, their `{:ok, _} =` matches on the ephemeris go, the coverage checks in the `Astro` functions and in the rise and set searches are removed, and equinoxes, solstices and new moons are found as crossings of the JPL-or-Meeus positions.

* **Equinoxes and solstices.** Find the crossing with `Astro.Solar.solar_ecliptic_longitude_after/2`, starting 20 days before the 1st of the event's month (the Ch.27 polynomial seed is fitted only to 1000–3000, so the calendar date is the better seed for any era). Inside the ephemeris this matches published instants to about 1.5 seconds, against about 30 for the closed form, and the 1000–3000 refusal goes.

* **New moons.** Seed with `Astro.Lunar.nth_new_moon/1`, then refine to the moment the lunar phase is zero. Inside the ephemeris the result moves by seconds; outside it the series and the crossing agree to within the Moon series' accuracy.

* **`Astro.Ephemeris.check_coverage/2` stays public.** It answers "would JPL answer this moment", which is useful for diagnostics, but no caller needs it for correctness.

## Accuracy and limits

* **Inside the ephemeris** results are unchanged from 2.9.0, except equinoxes, solstices and new moons, which become more accurate by seconds.

* **Outside it** the Moon series is good to about 10″ in longitude near the present, and the Sun series to about 1″ (see the measurement below). An event found from them is within seconds to minutes of the true instant near the present, and less certain the further away it is.

* **Far from the present ΔT dominates.** Its uncertainty reaches minutes by 1000 and hours by −2000, which outweighs the difference between JPL and Meeus. The docs say so rather than imply precision that does not exist.

* **At the edge of the ephemeris** the source switches, so a position can jump by up to the series' error, and an event time by seconds. Tests pin this down at both edges of both kernels.

* **The new moon series is ordered only within about ±300,000 years of J2000**, where `date_time_new_moon_before/1` and `date_time_new_moon_at_or_after/1` raise `ArgumentError`. That is far beyond any calendar's range and is the one limit that stays.

## Sun series measurement

Measured 2026-10-31 over 20,000 moments from 1900 to 2100 against JPL on the bundled kernel, in apparent ecliptic longitude:

| Series | Mean | RMS | Max |
|---|---|---|---|
| Ch.25 (the 2.9.0 fallback) | 6.5″ | 11.8″ | 37.0″ |
| 49-term, as shipped until 2.8.0 | 0.0″ | 12.0″ | 20.4″ |
| 49-term, nutation corrected | −0.3″ | 1.0″ | 3.3″ |

Far from the present both series stay sane (the March equinox stays near 17–21 March and the equinox year near 365.242 days at ±10,000 years) but diverge from each other: within 45″ (20 minutes of equinox time) from −2000 to 3000, about 520″ at −5000, and 930″ to 4150″ (6 to 28 hours) at ±10,000. Neither can be checked that far out without DE441, and ΔT's own uncertainty is hours there.

## Decisions

* **2026-10-31 — Remove `{:error, :not_found}` from the specs and `### Returns` of the functions that can no longer return it.** So downstream Dialyzer sees the real shape; a consumer's own `:not_found` clause then shows as unreachable, which is the signal to delete it.

* **2026-10-31 — Keep the `ArgumentError` beyond ±300,000 years.** No calendar reaches it, and returning an error would change the shape of two functions that return bare moments.

* **2026-10-31 — Use the 49-term Sun series with corrected nutation.** It is twelve times more accurate than Ch.25 against JPL over 1900–2100 and stays sane at ±10,000 years.

## Tasks

* [ ] **Speed up the new moon refinement** — each search now refines two new moons by bisection over ±12 days (about 21 phase evaluations each): 0.39 ms inside the ephemeris and 1.25 ms outside it, against about 0.01 ms for chapter 49 alone. A Newton step on the phase (the estimate minus the signed phase over the Moon's rate) converges in three or four evaluations, and only the one new moon a caller needs has to be refined. A lunisolar calendar over 2,000 years needs about 25,000 new moons.

* [ ] **Restore the far-date new moon search** — the corrected lunation estimate and the ±300,000-year `ArgumentError` decided above are not in any commit (possibly in the user's `stash@{0}`); without them a search 100,000 years out walks many lunations and one beyond ±300,000 years does not end.

* [ ] **Test the ephemeris edges** — every public function across both edges of the bundled and the full kernel, with no error, no raise, and event times within the stated jump.

* [ ] **Validate far dates against DE441** — optional: DE441 covers −13,200 to +17,191, so it can measure both Meeus series at ±10,000 years. It is a 3 GB kernel, so this is a one-off check, not a CI job.

* [ ] **Calendrical follow-up** — once released, remove `covered?/1`, `searchable/1` and the `range: :jpl_ephemeris` error from `Calendrical.Islamic.Visibility`, and raise Calendrical's Astro requirement. In the Calendrical repository, by its maintainer.

### Done

* [x] **Refine new moons to the zero-phase crossing** — `lunar_phase_at/1` is the plain longitude difference (its chapter 49 substitution misfired across 0°/360°); each lunation's new moon is refined from its own chapter 49 estimate, so a new moon is the same moment however it is reached. Chapter 49 is within 12 s of the JPL crossing over 1900–2100 and drifts from the series as about 1 s per century² outside it (96 s at 1000, 4 h at −10,000). 2026-10-31.

* [x] **Find equinoxes and solstices as longitude crossings** — seeded from the event's month rather than Ch.27, whose tables are gone; within 1.5 s of published 2019 and 2024 instants and within the ±30 s rounding of all 42 reference solstices; any year. 2026-10-31.

* [x] **Remove the coverage checks** — from the `Astro` functions, both rise and set searches and crescent visibility; `:not_found` is gone from their specs and docs, the README and the guides; tests show answers for the years 500 and 1000. 2026-10-31.

* [x] **Point the rise and set searches at `Astro.Solar` and `Astro.Lunar`** — `Astro.Solar.SunRiseSet` and `Astro.Lunar.MoonRiseSet` read positions through `solar_position/1` and `lunar_position/1`; every result is unchanged to the microsecond and the searches cost the same. 2026-10-31.

* [x] **Choose JPL or the series in `Astro.Solar` and `Astro.Lunar`** — each module chooses in two private functions that every position goes through; `lunar_phase_at/1` takes the Sun from `Astro.Solar`; the private Ch.25 Sun series is gone. 2026-10-31.

* [x] **Fix the precession coefficients** — `Astro.Coordinates.icrf_to_true_equator/2` now uses the J2000 coefficients of Meeus 21.3; the Sun's ecliptic latitude stays within 1.0″ over 1850–2149, where it reached 2.4″. 2026-10-31.

* [x] **Move the series into `Astro.Solar` and `Astro.Lunar`** — `Astro.Ephemeris.Meeus` is gone; the orbital elements and fundamental arguments the series use are no longer deprecated; `Astro.Coordinates.ecliptic_to_equatorial/3` is shared. 2026-10-31.

* [x] **Add the Moon's analytical series** — Meeus chapter 47 from git history; reproduces example 47.a to 0.02″, and over 1900–2100 is within 17.9″ of JPL in longitude (2.7″ RMS), 4.9″ in latitude and 12.7 km in distance. 2026-10-31.

* [x] **Add the Sun's analytical series** — within 3.3″ of JPL in longitude, 3.6″ in right ascension and 2.0″ in declination over 1900–2100. 2026-10-31.

* [x] **Measure the candidate Sun series** — the 49-term series with corrected nutation, about 1″ RMS against JPL over 1900–2100. 2026-10-31.
