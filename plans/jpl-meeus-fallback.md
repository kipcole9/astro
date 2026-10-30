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

* **One source of positions.** `Astro.Ephemeris` stays the only place the Sun's and Moon's apparent positions come from. Each position function asks the loaded kernel first; when the kernel has no segment for the moment, it computes the same quantity from the Meeus series. The return shapes do not change, and `{:error, :not_found}` is no longer returned for a date outside the kernel.

* **A Meeus provider module.** A new internal module, `Astro.Ephemeris.Meeus`, returns the apparent geocentric Sun and Moon in the frame the JPL path uses (true equator and equinox of date, distances in km): right ascension, declination and distance, and ecliptic longitude, latitude and distance.

* **The Sun.** Apparent longitude from the 49-term periodic series Astro carried until 2.8.0 as `sun_apparent_longitude_alt/1` (deleted in 8f61281), with the nutation in longitude converted from radians to degrees, which that function omitted; latitude zero; distance from the Keplerian ellipse; equatorial coordinates through the true obliquity of `Astro.Earth.nutation/1`. It replaces the Ch.25 series in `Astro.Solar.solar_ecliptic_longitude/1`'s fallback.

* **The Moon.** The Meeus Ch.47 series for longitude, latitude and distance, recovered from `8f61281^:lib/astro/lunar.ex`, with the nutation in longitude added, then to equatorial coordinates the same way.

* **Callers become total.** With every position available, the `{:ok, _} =` matches in `Astro.Solar` and `Astro.Lunar` cannot fail, the coverage checks in the `Astro` functions and in the rise and set searches are removed, and equinoxes, solstices and new moons are found as crossings of the JPL-or-Meeus positions.

* **Equinoxes and solstices.** Seed with the Ch.27 estimate, then find the crossing with `Astro.Solar.solar_ecliptic_longitude_after/2`. Inside the ephemeris this matches published instants to about 5 seconds, against about 30 for the closed form, and the 1000–3000 refusal goes.

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

* [ ] **Add the Moon to `Astro.Ephemeris.Meeus`** — the Ch.47 series recovered from git history, in the same shapes, with tests against JPL inside the ephemeris.

* [ ] **Fall back inside `Astro.Ephemeris`** — every position function uses the Meeus provider when the kernel has no segment; specs and docs say the functions always return `{:ok, _}`.

* [ ] **Remove the coverage checks** — from the `Astro` functions, sunrise and sunset, moonrise and moonset, solar noon and crescent visibility; update specs, docs, README and guides; tests for far past and far future dates.

* [ ] **Find equinoxes and solstices as longitude crossings** — seeded by the Ch.27 estimate, with the 1000–3000 refusal removed.

* [ ] **Refine new moons to the zero-phase crossing** — seeded by `nth_new_moon/1`, so the before and after searches agree with `date_time_new_moon_nearest/1`.

* [ ] **Test the ephemeris edges** — every public function across both edges of the bundled and the full kernel, with no error, no raise, and event times within the stated jump.

* [ ] **Validate far dates against DE441** — optional: DE441 covers −13,200 to +17,191, so it can measure both Meeus series at ±10,000 years. It is a 3 GB kernel, so this is a one-off check, not a CI job.

* [ ] **Calendrical follow-up** — once released, remove `covered?/1`, `searchable/1` and the `range: :jpl_ephemeris` error from `Calendrical.Islamic.Visibility`, and raise Calendrical's Astro requirement. In the Calendrical repository, by its maintainer.

### Done

* [x] **Fix the precession coefficients** — `Astro.Coordinates.icrf_to_true_equator/2` now uses the J2000 coefficients of Meeus 21.3; the Sun's ecliptic latitude stays within 1.0″ over 1850–2149, where it reached 2.4″. 2026-10-31.

* [x] **Add `Astro.Ephemeris.Meeus` for the Sun** — `sun_position_dt/1` and `sun_ecliptic_position_dt/1`; within 3.3″ of JPL in longitude, 3.6″ in right ascension and 2.0″ in declination over 1900–2100. 2026-10-31.

* [x] **Measure the candidate Sun series** — the 49-term series with corrected nutation, about 1″ RMS against JPL over 1900–2100. 2026-10-31.
