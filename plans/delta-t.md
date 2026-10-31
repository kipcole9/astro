# ΔT

**Status:** implemented (v2.10.0), 2026-10-31

ΔT is the difference between Terrestrial Time, in which the Sun's and the Moon's positions are computed, and Universal Time, which follows the Earth's rotation and in which Astro returns its results. Tidal friction slows the Earth, so ΔT grows roughly as the square of the time from the present, with decade-scale fluctuations from the Earth's core. Every event time Astro gives far from the present is shifted by ΔT, and outside the telescopic era ΔT is known only from records of ancient eclipses and occultations.

## How Astro computes it now

`Astro.Time.delta_t/1` joins four sources:

* **1972–2025** — IERS observed values, interpolated.

* **1620–1971** — the table of Meeus, *Astronomical Algorithms*, chapter 10.

* **Before 1620** — two polynomials from the same chapter: `102 + 102t + 25.3t²` for 948 to 1620, and `2177 + 497t + 44.1t²` before 948, with `t` in centuries from 2000.

* **After 2025** — a straight line from the last IERS value, rising 0.15 s a year.

## The reference model

NASA's eclipse catalogues use the polynomials of Espenak and Meeus ([Polynomial Expressions for Delta T](https://eclipse.gsfc.nasa.gov/SEhelp/deltatpoly2004.html)), fitted to the historical values of Morrison and Stephenson (2004, *Journal for the History of Astronomy* 35), with a long-term parabola `−20 + 32u²`, `u` in centuries from 1820, before −500 and after 2150. NASA's [uncertainty estimates](https://eclipse.gsfc.nasa.gov/LEcat5/uncertainty.html) go with it.

## Where the two differ

| Year | Astro | Espenak and Meeus | Difference | NASA standard error |
|---|---|---|---|---|
| −2000 | 52,857 s | 46,676 s | +6,181 s | 3,732 s |
| −1000 | 26,957 s | 25,428 s | +1,529 s | 636 s |
| 0 | 9,877 s | 10,584 s | −707 s | 265 s |
| 250 | 6,985 s | 8,163 s | −1,178 s | |
| 500 | 4,645 s | 5,710 s | −1,066 s | |
| 1000 | 1,612 s | 1,574 s | +38 s | 54 s |
| 1700–2000 | | | within 2 s | 5 s at 1700 |
| 2025 | 69 s | 74 s | −5 s | |
| 2050 | 73 s | 93 s | −20 s | |
| 2100 | 81 s | 203 s | −122 s | |
| 2500 | 141 s | 1,460 s | −1,319 s | 612 s |
| 3000 | 216 s | 4,436 s | −4,220 s | 1,885 s |

Three things cause this:

* **The ancient polynomials are older fits.** Meeus's chapter 10 formulas predate Morrison and Stephenson (2004). At −1000 and at 0 they differ from it by more than two standard errors, and by up to 20 minutes around 250 CE. For the Moon, which moves about 0.55″ a second, 20 minutes is 11′ of position, enough to change an ancient crescent sighting or the circumstances of an eclipse.

* **A 41 s jump at 1620**, where the 948–1620 polynomial (80 s at 1619) meets the Meeus table (121 s at 1620). The polynomial was published for 948–1600.

* **The future is a straight line.** Tidal braking makes ΔT accelerate. Morrison and Stephenson's parabola grows 32 s per century², and the length of day observed by Stephenson, Morrison and Hohenkerk ([2016](https://doi.org/10.1098/rspa.2016.0404), [addendum 2021](https://doi.org/10.1098/rspa.2020.0776)) lengthens 1.8 ms a century, which is about 33 s per century². Astro's line gives 216 s at 3000, where the parabola gives 4,436 s, a difference of over two standard errors.

Espenak and Meeus are not better everywhere: their 2005–2050 polynomial was fitted before 2005 and gives 74 s for 2025, where the IERS observed 69.3 s. The Earth's rotation has sped up since 2016, and ΔT has hardly changed since 2020.

## Recommendation

* **Before 1972, use the Espenak and Meeus polynomials** in place of the chapter 10 polynomials and table. They are the model NASA's eclipse catalogues use, they follow Morrison and Stephenson (2004), they remove the jump at 1620, and from 1700 to 1971 they agree with the present table to 2 s, so modern results do not move.

* **From 1972 to 2025, keep the IERS observed values.**

* **After 2025, join the last observed value smoothly to the long-term parabola**, reaching it at 2150 and following it after. A cubic Hermite join that matches the 2025 value and rate (69.3 s, −0.01 s a year over 2020–2025) and the parabola's value and slope at 2150 (328.5 s, 2.1 s a year) gives 70.1 s in 2030, 87.6 s in 2050, 199 s in 2100 and 4,436 s in 3000: it keeps today's observed values, unlike the Espenak and Meeus 2005–2050 polynomial, and agrees with the long-term model, unlike the present line. Espenak and Meeus bridge 2050–2150 the same way, with a linear correction to their parabola.

* **Do not apply the lunar secular acceleration correction for now.** Morrison and Stephenson's ΔT assumes the Moon's tidal acceleration is −26″ per century²; ELP-2000/82 uses −25.858″, and NASA adds `−0.000012932 (y − 1955)²` seconds for it: 49 s at the year 0 and 202 s at −2000, below the uncertainty, and it would apply only to the Moon.

* **Consider the 2016 model later.** Stephenson, Morrison and Hohenkerk's 2016 spline, revised in 2021, is the most recent; HM Nautical Almanac Office publishes it, but its pages were not reachable to compare. Its parabola is close to Morrison and Stephenson's, so it would refine rather than overturn the recommendation.

What changes: event times before about 1000 CE and after about 2050 move, by up to 20 minutes around 250 CE, 2 minutes at 2100 and 70 minutes at 3000. Anything that pins such a time in Calendrical or Tempo would need new values. Nothing between 1700 and 2050 moves by more than a few seconds.

## Tasks

### Done

* [x] **Replace ΔT before 1972 with the Espenak and Meeus polynomials** — within 0.07 s of all 28 Morrison and Stephenson values NASA tabulates from −500 to 1950; steps at the formula boundaries at most 0.25 s, where 1620 jumped 41 s. 2026-10-31.

* [x] **Join 2025 to the long-term parabola** — cubic Hermite from the 2025 IERS value and the 2020–2025 rate to `−20 + 32u²` at 2150. 2026-10-31.

* [x] **Update the accuracy guide and the ΔT docs.** 2026-10-31.
