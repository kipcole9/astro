# TODO

Work planned for Astro. The detail of anything shipped is in the CHANGELOG.

## Open

* [ ] **Return errors rather than raise on invalid input** — every public `Astro` function raises `FunctionClauseError` for some invalid arguments; equinox and solstice are fixed. Seven functions return bare values, so fixing them changes their return type. Survey and options in [plans/invalid-input.md](plans/invalid-input.md).

* [ ] **Review the ΔT model** — `Astro.Time.delta_t/1` extrapolates in a straight line at 0.15 s a year after 2025, where long-term models follow a parabola: 216 s against Espenak and Meeus's 4,436 s at 3000, outside NASA's 1,885 s uncertainty. Before 1000 its Meeus chapter 10 polynomials differ from Espenak and Meeus by 700–1,100 s around 0–500 CE, against an uncertainty of 140–265 s. Consider adopting the Espenak and Meeus polynomials; the figures are in `guides/accuracy.md`.

* [ ] **Documentation as a learning guide** — each primary function explains what it calculates, how and from which source, how accurate it is, and where to read more, with an accuracy guide covering JPL against the series, near and far term. Plan in [plans/learning-documentation.md](plans/learning-documentation.md).

* [ ] **Answer every date from JPL or Meeus** — positions come from the JPL ephemeris where it covers the moment and from the Meeus series where it does not, so no consumer checks coverage or sees `{:error, :not_found}`. Design and tasks in [plans/jpl-meeus-fallback.md](plans/jpl-meeus-fallback.md).

* [ ] **Return errors rather than raise on invalid input** — the public functions guard their arguments, so a malformed location, date, phase or option value raises `FunctionClauseError` or `ArgumentError` rather than returning `{:error, reason}`. Returning errors changes the return types of the functions that return bare values, such as `Astro.lunar_phase_at/1`, so it belongs in a major release.

* [ ] **Remove `Astro.date_time_new_moon_at_or_before/1`** — deprecated in 2.6.2 in favour of `Astro.date_time_new_moon_before/1`; remove it in the next major release.

## Done

* [x] **Drop CI's unused full-ephemeris download** — CI tests the bundled kernel, the one hex installs ship. 2026-10-18, v2.8.0.
