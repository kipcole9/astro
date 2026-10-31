# Documentation as a learning guide

**Status:** in progress, 2026-10-31

Astro's documentation should teach as well as describe. Someone using the library to learn astronomical calculation should be able to read a function's documentation and understand what is being calculated, how, from which ephemeris or series, how accurate the answer is, and where to read more. No other library does this, and it suits a codebase already arranged as a guide (Sun algorithms in `Astro.Solar`, Moon algorithms in `Astro.Lunar`).

## Scope

The 22 primary public functions in `Astro`:

* **Sun** — `sunrise/3`, `sunset/3`, `solar_noon/2`, `hours_of_daylight/2`, `duration_of_daylight/2`, `sun_position_at/1`, `sun_azimuth_elevation/2`, `sun_apparent_longitude/1`, `equinox/3`, `solstice/3`.

* **Moon** — `moonrise/3`, `moonset/3`, `moon_position_at/1`, `lunar_phase_at/1`, `lunar_phase_emoji/1`, `illuminated_fraction_of_moon_at/1`, `date_time_new_moon_before/1`, `date_time_new_moon_at_or_after/1`, `date_time_new_moon_nearest/1`, `date_time_lunar_phase_at_or_before/2`, `date_time_lunar_phase_at_or_after/2`, `new_visible_crescent/3,4`.

The analytical-series functions in `Astro.Solar` and `Astro.Lunar` already describe their algorithms; they gain `### Accuracy` and `### Reference` sections where they lack them. The moduledocs of `Astro`, `Astro.Solar`, `Astro.Lunar` and `Astro.Ephemeris` link to the accuracy guide.

## Shape of each function's documentation

* **What it calculates** — one or two sentences defining the quantity astronomically (for example, sunrise is the moment the Sun's upper limb crosses the horizon, allowing 34′ of refraction).

* **How it is calculated** — one short paragraph: the method (scan and bisect, secant search, closed form), the source of the positions (JPL DE440s where the loaded ephemeris covers the date, the named analytical series otherwise), and the corrections applied (precession, nutation, aberration, parallax, refraction, ΔT).

* `### Arguments`, `### Options`, `### Returns` — as today.

* `### Accuracy` — the measured accuracy inside the ephemeris (against Skyfield, USNO or published times) and outside it (the analytical series against JPL), and the point beyond which ΔT dominates. Each figure links to the accuracy guide.

* `### Examples` — as today.

* `### Reference` — one to four references: the chapter of Meeus, *Astronomical Algorithms* (2nd edition, 1998), the relevant paper (the DE440 paper, Yallop 1997, Odeh 2004, Schaefer 1993), and a Wikipedia article where one explains the concept well. Every link is checked to resolve before it is written.

## Accuracy guide

A new guide, `guides/accuracy.md`, in the docs extras and the README's documentation list:

* **The two sources** — JPL DE440s (what it is, its span in the bundled and full kernels) and the analytical series (Bretagnon and Simon for the Sun, Meeus chapter 47 for the Moon, Meeus chapter 49 for new-moon estimates), with their measured differences from JPL.

* **Near term** — within the ephemeris: positions to well under a milliarcsecond; event times limited by the refraction model and the horizon definition, measured against Skyfield, USNO and timeanddate.com.

* **Outside the ephemeris** — the series' accuracy near the present, how it degrades with time from J2000, and the edges where the source switches.

* **Far term** — ΔT: how its uncertainty grows into the past and future, and why beyond a few thousand years it outweighs any difference between JPL and the series. The ±50,000-year limit on the new moon searches.

* **Per-function table** — each primary function's accuracy inside and outside the ephemeris.

## Measuring the series inside 1900–2100

The series' accuracy for each function (not just for positions) is measured by loading a subset kernel that covers only 2149–2150, built with `mix astro.build_ephemeris --from 2149 --to 2150`. With it, every date in 1900–2100 is answered from the series, and the results compare directly with the same calculations on the full kernel.

## Series accuracy, measured

Measured 2026-10-31 by running every function on the full DE440s kernel (JPL) and on a 2148–2150 subset kernel (so 1900–2100 came from the series), over 1900–2100: rise, set and noon for five cities (Sydney, London, New York, Tokyo, Cape Town) on 200 dates; every equinox and solstice; 1,000 new moon and full moon searches; positions and phase at 1,000 moments; crescent visibility on 250 evenings after new moon in each city.

| Quantity | Series minus JPL, RMS | Maximum |
|---|---|---|
| Sunrise, sunset | 0.07 s | 0.21 s |
| Moonrise, moonset | 0.22 s | 0.93 s |
| Solar noon | 0.06 s (remeasured after the solar noon fix) | 0.15 s |
| Equinoxes and solstices | 18 s (mean −14 s) | 50 s |
| New moons | 6.0 s | 20 s |
| Full moons | 6.2 s | 30 s |
| Sun right ascension, declination | 0.76″, 0.50″ | 2.2″, 1.3″ |
| Sun apparent longitude | 0.75″ (mean +0.56″) | 2.0″ |
| Sun azimuth, elevation (Sydney) | 0.83″, 0.63″ | 2.6″, 1.8″ |
| Sun distance | 4,300 km | 12,000 km |
| Moon right ascension, declination | 2.7″, 1.3″ | 10.1″, 6.5″ |
| Moon distance | 2.9 km | 11.7 km |
| Lunar phase | 2.8″ | 11.5″ |
| Illuminated fraction | 4.5×10⁻⁶ | 1.8×10⁻⁵ |
| Crescent visibility category | Odeh and Schaefer 1,250 of 1,250 agree; Yallop 1,249 of 1,250 | |

Rise and set times barely move, because a position error of a few seconds of arc moves the crossing of the horizon by well under a second. Equinoxes and solstices move most, because the Sun's longitude changes by only about 2.5″ a minute: the series' 0.56″ bias in longitude is the −14 s mean. New and full moons depend on the Moon's longitude, which changes by about 30″ a minute, so 2.8″ of phase error is about 6 s.

## Choosing JPL or the series (item 5)

Measured 2026-10-31, per position:

| Position | JPL | Series |
|---|---|---|
| Sun, equatorial | 4.6 µs | 4.2 µs |
| Sun, ecliptic | 4.6 µs | 4.0 µs |
| Moon, equatorial | 3.6 µs | 22.3 µs |
| Moon, ecliptic | 3.6 µs | 22.1 µs |

The series are not faster: the Sun's is about 10% faster and the Moon's six times slower. A choice of series-only would trade accuracy for nothing in speed. Its one gain is memory: the kernel occupies about 8.4 MB (bundled) or 31 MB (full) in `:persistent_term`, and loads in 1–4 ms.

Recommendation: do not add an accuracy-for-performance option. If a memory-constrained deployment needs it, a later `config :astro, ephemeris: :none` could skip loading a kernel, with the series answering every date.

## Decisions

* **2026-10-31 — `### Accuracy` goes before `### Examples`, `### Reference` last.** The order is Arguments, Options, Returns, Accuracy, Examples, Reference: accuracy beside what is returned, references at the end like a bibliography.

* **2026-10-31 — Cite Meeus, *Astronomical Algorithms* (2nd edition, 1998) by chapter only.** Chapter numbers are certain; page numbers cannot be checked without the book.

* **2026-10-31 — No option to choose the series over JPL.** The series are not faster, so the switch would trade accuracy for nothing; the accuracy guide says so.

## Tasks

* [ ] **Document the new moon and phase searches.**

* [ ] **Document moonrise, moonset and crescent visibility.**

* [ ] **Add accuracy and references to the `Astro.Solar` and `Astro.Lunar` analytical functions.**

### Done

* [x] **Document the Moon position, phase and illumination functions** — position, phase, phase emoji, illuminated fraction; checked against Meeus examples 47.a (2.1″, 0.3″, 4 km) and 48.a (0.67856 against 0.6786). 2026-10-31.

* [x] **Document the equinox and solstice functions** — and replace the unsourced "within 1.5 s of published times" with the check against Meeus's full VSOP87 June 1962 solstice (to the second); USNO's minute-rounded seasons differ by −24 to +41 s over 2015–2035, too coarse to use. 2026-10-31.

* [x] **Document the Sun functions** — sunrise, sunset, solar noon, daylight, position, azimuth and elevation, apparent longitude; found and fixed solar noon (up to 18 s off) and the azimuth's mean sidereal time on the way. 2026-10-31.

* [x] **Write `guides/accuracy.md`** — sources, within and outside the ephemeris, the edges, far term (series drift, ΔT uncertainty from NASA after Morrison and Stephenson 2004 and Huber 2000, Astro's ΔT against Espenak and Meeus) and speed; linked from the README, the docs extras and the `Astro`, `Astro.Solar`, `Astro.Lunar` and `Astro.Ephemeris` moduledocs. 2026-10-31.

* [x] **Measure every function's series accuracy** — see "Series accuracy, measured" above. 2026-10-31.
