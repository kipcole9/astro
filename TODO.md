# TODO

Work planned for Astro. The detail of anything shipped is in the CHANGELOG.

## Open

* [ ] **Answer every date from JPL or Meeus** — positions come from the JPL ephemeris where it covers the moment and from the Meeus series where it does not, so no consumer checks coverage or sees `{:error, :not_found}`. Design and tasks in [plans/jpl-meeus-fallback.md](plans/jpl-meeus-fallback.md).

* [ ] **Return errors rather than raise on invalid input** — the public functions guard their arguments, so a malformed location, date, phase or option value raises `FunctionClauseError` or `ArgumentError` rather than returning `{:error, reason}`. Returning errors changes the return types of the functions that return bare values, such as `Astro.lunar_phase_at/1`, so it belongs in a major release.

* [ ] **Remove `Astro.date_time_new_moon_at_or_before/1`** — deprecated in 2.6.2 in favour of `Astro.date_time_new_moon_before/1`; remove it in the next major release.

## Done

* [x] **Drop CI's unused full-ephemeris download** — CI tests the bundled kernel, the one hex installs ship. 2026-10-18, v2.8.0.
