# Sun & Moon Rise and Set Accuracy Comparisons

Comparisons of `Astro.sunrise/3`, `Astro.sunset/3`, `Astro.moonrise/3`, and `Astro.moonset/3` against Skyfield (JPL DE440s), USNO (DE430), and timeanddate.com were run to confirm accuracy. They were run against Astro 2.8.0 and Skyfield 1.55, with both libraries reading the same `de440s.bsp` file.

## Sunrise / Sunset

Both Astro and Skyfield use the JPL DE440s ephemeris, which explains their close agreement. The remaining difference of about a second comes from the horizon: Astro uses a fixed solar semi-diameter of 16′, while Skyfield uses the Sun's apparent semi-diameter, which is slightly larger in December when the Earth is nearest the Sun. The timeanddate.com data (used in the CSV test files) agrees with both to within ±1 minute; the 3 cases just over 60 seconds are a minute-rounding artefact.

The comparison uses test dates from December 2019 across 5 cities (Sydney, Moscow, NYC, São Paulo, Beijing) for a total of 310 comparisons.

### Overall

| Comparison | Max diff | Mean diff | Within ±1 min |
|---|---|---|---|
| **Astro vs Skyfield** | **1.6 s** | **0.95 s** | 310/310 (100%) |
| **Astro vs timeanddate.com** (CSV) | 61 s | 28.8 s | 307/310 (99.0%) |
| **timeanddate.com vs Skyfield** | 61 s | 28.5 s | 308/310 (99.4%) |

### Per-city (Astro vs Skyfield)

| City | Rise max | Rise avg | Set max | Set avg |
|---|---|---|---|---|
| Sydney | 1.0 s | 1.0 s | 0.7 s | 0.7 s |
| Moscow | 1.6 s | 1.6 s | 1.3 s | 1.3 s |
| NYC | 1.1 s | 1.1 s | 0.7 s | 0.7 s |
| São Paulo | 0.9 s | 0.9 s | 0.6 s | 0.6 s |
| Beijing | 1.1 s | 1.1 s | 0.7 s | 0.7 s |

## Moonrise / Moonset

The ~16 s mean difference against USNO is explained by two factors: USNO uses DE430 (vs the JPL DE440s that Astro uses), and USNO rounds to the nearest minute. Skyfield shows the same ~16 s offset against USNO, suggesting this is an ephemeris version difference rather than an algorithmic error.

The Skyfield comparison covers every moonrise and moonset in March 2026 across 4 cities (NYC, London, Sydney, Tokyo), a total of 240 comparisons. The USNO comparison uses the 67 cases in the test suite.

### Overall

| Comparison | Max diff | Mean diff | Within ±1 min |
|---|---|---|---|
| **Astro vs Skyfield** | **0.1 s** | **0.08 s** | 240/240 (100%) |
| **Astro vs USNO** | 29 s | 15.5 s | 67/67 (100%) |
| **Skyfield vs USNO** | 35 s | 15.6 s | 67/67 (100%) |

### Per-city (Astro vs Skyfield)

| City | Max diff | Avg diff |
|---|---|---|
| NYC | 0.1 s | 0.08 s |
| London | 0.1 s | 0.08 s |
| Sydney | 0.1 s | 0.08 s |
| Tokyo | 0.1 s | 0.08 s |

### Per-city (Astro vs USNO)

| City | Max diff | Avg diff |
|---|---|---|
| NYC | 29 s | 15.8 s |
| London | 29 s | 16.7 s |
| Sydney | 27 s | 11.9 s |
| Tokyo | 27 s | 17.8 s |
