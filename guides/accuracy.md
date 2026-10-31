# Accuracy

Every result Astro returns rests on two things: where the Sun and the Moon are, and what time it is. This guide explains where Astro's positions come from, how accurate they are near the present and far from it, and how the uncertainty of the Earth's rotation, ΔT, comes to dominate far from the present. The figures here were measured against independent sources and are repeated, briefly, in the `### Accuracy` section of each function's documentation.

## Where the positions come from

Astro has two sources for the apparent positions of the Sun and the Moon, and chooses between them for each moment:

* **The JPL DE440s ephemeris** — a numerical integration of the solar system by NASA's Jet Propulsion Laboratory, fitted to radar, spacecraft and lunar laser ranging data. Astro reads it from a kernel file: the bundled `de440s-astro.bsp` covers 1900 to 2100, and the full `de440s.bsp` (`mix astro.download_ephemeris`) covers 1849 to 2150.

* **Analytical series** — sums of periodic terms that describe each orbit for any date. The Sun uses the 49-term series of Bretagnon and Simon, as given in *Calendrical Calculations*. The Moon uses the series of Meeus, *Astronomical Algorithms*, chapter 47, abridged from the ELP-2000/82 lunar theory. New moon searches start from the estimates of Meeus chapter 49.

Where the loaded kernel covers a moment, the position comes from JPL; everywhere else it comes from the series. The choice is made in one place for each body, in `Astro.Solar` and `Astro.Lunar`, so every function answers for any date without checking coverage.

JPL positions are rotated to the true equator and equinox of date with the IAU 1976 precession and IAU 1980 nutation, corrected for light time and aberration. This reduction reproduces Meeus's full-precision VSOP87 example for the Sun (*Astronomical Algorithms*, example 25.b) to 0.2″.

## Within the ephemeris

Inside 1900–2100 (or 1849–2150 with the full kernel), positions are limited by the reduction above rather than by the ephemeris, and event times by how the event is defined: the refraction at the horizon, the Sun's and the Moon's apparent radii, and the minute to which reference times are published.

| Result | Compared with | Agreement |
|---|---|---|
| Sunrise and sunset | Skyfield, same ephemeris | 0.95 s mean, 1.6 s at most |
| Moonrise and moonset | Skyfield, same ephemeris | 0.08 s mean, 0.1 s at most |
| Sunrise and sunset | timeanddate.com, to the minute | 28.8 s mean, within a minute in 307 of 310 cases |
| Moonrise and moonset | USNO, to the minute | 15.5 s mean, 29 s at most |
| Equinoxes and solstices | published times for 2019 and 2024 | within 1.5 s |

The remaining second against Skyfield for the Sun comes from the horizon: Astro uses a fixed solar radius of 16′ where Skyfield uses the apparent radius. The [rise and set comparisons](rise_and_set_comparisons.md) give the details.

## Outside the ephemeris

The analytical series were measured against JPL by answering every date in 1900–2100 from the series and comparing each function with its JPL result:

| Result | Series minus JPL, RMS | At most |
|---|---|---|
| Sunrise, sunset | 0.07 s | 0.21 s |
| Moonrise, moonset | 0.22 s | 0.93 s |
| Solar noon | 0.06 s | 0.15 s |
| Equinoxes and solstices | 18 s | 50 s |
| New moons | 6.0 s | 20 s |
| Full moons | 6.2 s | 30 s |
| The Sun's right ascension and declination | 0.76″ and 0.50″ | 2.2″ and 1.3″ |
| The Sun's apparent longitude | 0.75″ | 2.0″ |
| The Moon's right ascension and declination | 2.7″ and 1.3″ | 10.1″ and 6.5″ |
| The Moon's distance | 2.9 km | 11.7 km |
| The lunar phase | 2.8″ | 11.5″ |
| The illuminated fraction | 0.0000045 | 0.000018 |

Crescent visibility, a category rather than a time, agreed in 3,749 of 3,750 cases across the Odeh, Yallop and Schaefer criteria.

How much an error in position moves a result depends on how fast that position changes. A rise or set barely moves, because the horizon crossing is fast. An equinox moves most, because the Sun's longitude advances only about 2.5″ a minute: the Sun series' mean bias of +0.56″ in longitude puts equinoxes and solstices 14 s early on average. A new moon depends on the difference of the two longitudes, which changes about 30″ a minute, so 2.8″ of phase error is about 6 s.

## At the edges of the ephemeris

Where the kernel's coverage ends the source switches, so a position can jump by the difference between JPL and the series at that moment. At the edges of the bundled and the full kernels, positions half a second either side differ by at most 1.1″ for the Sun and 3.1″ for the Moon (including the Moon's own motion in that second), and an event time by well under a second.

## Far from the present

Two things limit results far from the present.

The first is the series themselves. They are fitted to modern observations, and their small secular terms grow with the square of the time from J2000. Astro's Sun series and the simpler series of Meeus chapter 25 agree within 45″ (about 20 minutes of equinox time) between −2000 and 3000, but differ by up to 4,150″ (more than a day) at ±10,000 years, and nothing can say which is closer that far out. The Meeus chapter 49 new-moon estimates drift from the zero crossings of the series by about 1 second per century squared: 96 s at the years 1000 and 3000, 25 minutes at −2000 and four hours at −10,000. New moons are always the zero crossings, and the searches built on chapter 49 are limited to 50,000 years either side of J2000, beyond which its estimates can no longer identify each lunation.

The second, and larger, is ΔT, the difference between Terrestrial Time, in which positions are computed, and Universal Time, in which results are given. It reflects the slowing and irregular rotation of the Earth, and before the telescopic era it is known only from historical eclipses and other observations. NASA's estimate of its uncertainty ([Uncertainty in Delta T](https://eclipse.gsfc.nasa.gov/LEcat5/uncertainty.html), after Morrison and Stephenson, 2004, and Huber, 2000) is:

| Year | Standard error of ΔT |
|---|---|
| −2000 | 3,732 s |
| −1000 | 636 s |
| 0 | 265 s |
| 1000 | 54 s |
| 1700 | 5 s |
| 1900 | 0.1 s |
| 2500 | 612 s |
| 3000 | 1,885 s |
| 5000 | 12,341 s |

Before about 1600 and after about 2100, an uncertainty of minutes to hours in ΔT outweighs every difference between JPL and the series: an event time is only as good as ΔT.

### How Astro computes ΔT

`Astro.Time.delta_t/1` uses IERS observations for 1972–2025, the table of Meeus, *Astronomical Algorithms*, chapter 10, for 1620–1971, two polynomials of Meeus chapter 10 before 1620, and a straight line from the last IERS value at 0.15 s a year after 2025. Compared with the model of Espenak and Meeus used by NASA's eclipse catalogues ([Polynomial Expressions for Delta T](https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html)):

| Year | Astro | Espenak and Meeus |
|---|---|---|
| −2000 | 52,857 s | 46,676 s |
| 0 | 9,877 s | 10,584 s |
| 500 | 4,645 s | 5,710 s |
| 1000 | 1,612 s | 1,574 s |
| 1500 | 225 s | 198 s |
| 2500 | 141 s | 1,460 s |
| 3000 | 216 s | 4,436 s |
| 5000 | 516 s | 32,340 s |

The two agree well between about 1000 and the present. Before that they differ by more than the uncertainty above, and after 2025 Astro's straight line stays far below the parabola that tidal braking of the Earth's rotation leads models to expect: by 3000 the difference is about 70 minutes.

## Speed

The series are not faster than JPL. Measured per position:

| Position | JPL | Series |
|---|---|---|
| The Sun | 4.6 µs | 4.0–4.2 µs |
| The Moon | 3.6 µs | 22 µs |

Astro therefore always uses JPL where the loaded kernel covers a moment. The kernel's cost is memory: about 8.4 MB for the bundled file and 31 MB for the full one, held in `:persistent_term` and loaded in a few milliseconds when Astro starts.
