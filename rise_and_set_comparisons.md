# Sun & Moon Rise and Set Accuracy Comparisons

Comparisons of of `Astro.sunrise/3`, `Astro.sunset/3`, `Astro.moonrise/3`,
and `Astro.moonset/3` against Skyfield (JPL DE440s), USNO (DE430),
and timeanddate.com were run to confirm accuracy.

## Sunrise / Sunset

Both Astro and Skyfield use JPL DE440s ephemerides, which explains their near-exact
agreement. The timeanddate.com data (used in the CSV test files) agrees with both
to within ±1 minute, with the 2 boundary cases at 61 seconds being a minute-rounding
artefact.

The test data uses dates from December 2019 across 5 cities (Sydney, Moscow, NYC, São Paulo, Beijing) for a total of 310 comparisons.

### Overall

| Comparison | Max diff | Mean diff | Within ±1 min |
|---|---|---|---|
| **Astro vs Skyfield** | **7 s** | **3.8 s** | 310/310 (100%) |
| **Astro vs timeanddate.com** (CSV) | 61 s | ~29 s | 308/310 (99.4%) |
| **timeanddate.com vs Skyfield** | 61 s | 28.5 s | 308/310 (99.4%) |

### Per-city (Astro vs Skyfield)

| City | Rise max | Rise avg | Set max | Set avg |
|---|---|---|---|---|
| Sydney | 4 s | 2.8 s | 7 s | 4.9 s |
| Moscow | 5 s | 3.1 s | 6 s | 4.7 s |
| NYC | 5 s | 3.2 s | 6 s | 4.5 s |
| São Paulo | 4 s | 3.0 s | 6 s | 4.6 s |
| Beijing | 5 s | 3.3 s | 6 s | 4.3 s |

## Moonrise / Moonset

The ~16 s mean difference against USNO is explained by two factors: USNO uses DE430
(vs our DE440s), and USNO rounds to the nearest minute. Skyfield shows the same ~16 s
offset against USNO, suggesting this is an ephemeris version difference rather than an
algorithmic error.

The test data uses dates from March 2026 across 4 cities (NYC, London, Sydney, Tokyo) for a total of 70 comparisons.

### Overall

| Comparison | Max diff | Mean diff | Within ±1 min |
|---|---|---|---|
| **Astro vs Skyfield** | **6 s** | **2.5 s** | 240/240 (100%) |
| **Astro vs USNO** | 32 s | 15.5 s | 67/67 (100%) |
| **Skyfield vs USNO** | 35 s | 15.6 s | 67/67 (100%) |

### Per-city (Astro vs Skyfield)

| City | Max diff | Avg diff |
|---|---|---|
| NYC | 5 s | 2.1 s |
| London | 6 s | 2.8 s |
| Sydney | 6 s | 3.2 s |
| Tokyo | 5 s | 2.1 s |

### Per-city (Astro vs USNO)

| City | Max diff | Avg diff |
|---|---|---|
| NYC | 32 s | 16.3 s |
| London | 30 s | 16.4 s |
| Sydney | 28 s | 11.8 s |
| Tokyo | 28 s | 17.7 s |
