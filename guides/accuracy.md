# Accuracy

Every result Astro returns rests on two things: where the Sun and the Moon are, and what time it is. This guide explains where Astro's positions come from, how accurate they are near the present and far from it, how the uncertainty of the Earth's rotation, ΔT, comes to dominate far from the present, and how Astro's eclipses compare with NASA's catalogues and path tables and the USNO's eclipse computer. The figures here were measured against independent sources and are repeated, briefly, in the `### Accuracy` section of each function's documentation.

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
| June solstice of 1962 | Meeus, full VSOP87 theory, to the second | the same second |

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

The first is the series themselves. They are fitted to modern observations, and their small secular terms grow with the square of the time from J2000. Astro's Sun series and the simpler series of Meeus chapter 25 agree within 45″ (about 20 minutes of equinox time) between −2000 and 3000, but differ by up to 4,150″ (more than a day) at ±10,000 years, and nothing can say which is closer that far out. The Meeus chapter 49 new-moon estimates drift from the zero crossings of the series by about 1 second per century squared: 96 s at the years 1000 and 3000, 25 minutes at −2000 and four hours at −10,000. New moons are always the zero crossings, and the searches built on chapter 49 are limited to 50,000 years either side of J2000, beyond which its estimates can no longer identify each lunation. Equinoxes and solstices share the same limit, and the `Astro` functions return `{:error, :year_out_of_range}` beyond it.

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

`Astro.Time.delta_t/1` uses three sources:

* **Before 1972** — the polynomials of Espenak and Meeus ([Polynomial Expressions for Delta T](https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html)), the model NASA's eclipse catalogues use. They are fitted to the historical values of Morrison and Stephenson (2004), drawn from ancient and medieval eclipses and, since 1600, lunar occultations, and follow the long-term parabola `−20 + 32u²`, `u` in centuries from 1820, before −500. They agree with every value Morrison and Stephenson tabulate from −500 to 1950 to within 0.1 s.

* **1972–2025** — the values observed by the IERS, one for each 1 January.

* **After 2025** — a smooth curve from the last observed value, and its rate over 2020–2025, that joins the long-term parabola at 2150 and follows it after: 70 s in 2030, 88 s in 2050, 199 s in 2100 and 4,436 s in 3000.

The parabola reflects tidal friction, which lengthens the day: Stephenson, Morrison and Hohenkerk ([2016](https://doi.org/10.1098/rspa.2016.0404)) measure an average lengthening of 1.8 ms a century since 720 BC, which corresponds to ΔT growing by about 33 s per century². The Earth's rotation also fluctuates over decades, which no model predicts: it has sped up since 2016, so ΔT barely changed between 2020 and 2025, and the join keeps that for the next few years before it turns toward the long-term trend.

Earlier versions of Astro used the older formulas of Meeus, *Astronomical Algorithms*, chapter 10, and a straight line after 2025. They differed from the model above by up to 20 minutes around 250 CE and 70 minutes at 3000, and jumped 41 s at 1620.

## Eclipses

Eclipses are tested against NASA's [Five Millennium Catalog of Solar Eclipses](https://eclipse.gsfc.nasa.gov/SEcat5/SEcatalog.html) and [Five Millennium Catalog of Lunar Eclipses](https://eclipse.gsfc.nasa.gov/LEcat5/LEcatalog.html) by Espenak and Meeus, NASA's path tables of [central solar eclipses](https://eclipse.gsfc.nasa.gov/SEpath/SEpath.html), and the USNO's [Solar Eclipse Computer](https://aa.usno.navy.mil/data/SolarEclipses). NASA computes from the VSOP87 and ELP-2000/82 theories and each source has its own ΔT, so instants are compared in Terrestrial Time, and places and local times with the source's ΔT taken out: a larger ΔT turns the Earth further under the shadow, the same as moving the observer west by the Earth's rotation in the difference. What remains is the difference between the positions.

### Global circumstances

Every eclipse NASA lists from 1901 to 2100, 452 solar and 457 lunar, is found, of the same type, hybrid solar eclipses included. Its Saros series is NASA's for every eclipse of the six centuries tested, 694 solar and 703 lunar:

| Result | Solar | Lunar |
|---|---|---|
| Greatest eclipse | within 0.6 s | within 2.7 s, 0.5 s mean |
| Gamma | within 0.00006 | within 0.00014 |
| Magnitudes | within 0.00007 | within 0.0004 |
| Durations of the partial and total phases | — | within 4 s |
| Saros series | the same | the same |

NASA gives durations to 0.1 minute; a phase the Moon only grazes, entering it by less than 0.05 of its diameter, lasts a time that changes quickly with how far it enters, and is only required to happen. Lunar eclipses use Danjon's enlargement of the Earth's shadow, as NASA's catalogue does; the `:shadow` option gives Chauvenet's, the older almanac convention, whose larger shadow adds about 0.005 to the umbral magnitude and 0.025 to the penumbral.

Outside the ephemeris the positions come from the series. Against every fourth eclipse of four other centuries, greatest eclipse agrees within:

| Century | Solar | Lunar |
|---|---|---|
| 1801–1900 | 9 s | 15 s |
| 2901–3000 | 32 s | 40 s |
| 1–100 | 80 s | 78 s |
| −999 to −900 | 130 s | 141 s |

with magnitudes within 0.0014 for the Sun and 0.002 for the Moon. These differences are much smaller than ΔT's uncertainty at those dates, so in Universal Time it is ΔT that limits them.

### Local circumstances

Against the USNO's computer for 17 eclipses and places from 1999 to 2026, including eclipses in progress at sunrise and sunset, a place 1,600 m high and two places that see none, `Astro.solar_eclipse_at/3` agrees on the type and visibility every time:

| Result | Agreement |
|---|---|
| Beginning and end of the partial eclipse | within 1.1 s |
| Beginning and end of totality or annularity | within 2 s; 4 s near the edge of an annular path |
| Magnitude | within 0.0005 |
| Obscuration | within 0.0012 |
| The Sun's altitude at each contact | within 0.05° |

Totality is about 2 s shorter, and annularity about 2 s longer, than the USNO's, which takes a larger radius for the Moon than NASA's mean limb used here. The mountains and valleys of the real lunar limb, which neither source includes, change the duration of totality by 1 to 3 s and move the limits of a path by 1 to 3 km.

The USNO has no lunar eclipse computer. A lunar eclipse happens at the same instants everywhere, so `Astro.lunar_eclipse_at/3` adds only the Moon's altitude; at the instants of moonrise and moonset it is the rise and set horizon to within 0.00001°.

### The path of a solar eclipse

Against NASA's path tables for eight eclipses from 1999 to 2027 (total, annular, hybrid, one over Antarctica and one whose shadow axis misses the Earth), at 674 instants, `Astro.solar_eclipse_path/2` finds every point NASA gives:

| Result | Agreement |
|---|---|
| The central line and the limits, across the path, with the Sun 20° or more up | within 0.7 km |
| The same over Antarctica, with the Sun lower | within 2.6 km |
| The same along the path | within 2 s of the shadow's motion |
| Path width | within 1 km and 0.6% |
| Duration on the central line | within 0.7 s |

The differences follow those of the shadow's position, up to about 0.7 km between the two ephemerides, and grow where the Sun is low because the ground is tilted to the shadow. Near sunrise and sunset the shadow crosses the ground at hundreds of kilometres a second, so a point at a given instant can differ by tens of kilometres along the path while the path itself is the same; the comparison therefore separates the distance across the path from the time along it.

In Universal Time an eclipse's places carry ΔT's uncertainty: a second of ΔT moves the path 0.46 km east or west at the equator and every local contact by about a second. In 1900 that is 0.05 km; at the year 0, where ΔT is uncertain by 265 s, it is about 1.1° of longitude, and in −2000 more than 15°, so the path of an ancient eclipse is known in shape and latitude far better than in longitude.

## Speed

The series are not faster than JPL. Measured per position:

| Position | JPL | Series |
|---|---|---|
| The Sun | 4.6 µs | 4.0–4.2 µs |
| The Moon | 3.6 µs | 22 µs |

Astro therefore always uses JPL where the loaded kernel covers a moment. The kernel's cost is memory: about 8.4 MB for the bundled file and 31 MB for the full one, held in `:persistent_term` and loaded in a few milliseconds when Astro starts.
