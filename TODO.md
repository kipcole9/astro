# TODO

Work planned for Astro. The detail of anything shipped is in the CHANGELOG.

## Open

* [ ] **Return errors rather than raise on invalid input** — the public functions guard their arguments, so a malformed location, date, phase or option value raises `FunctionClauseError` or `ArgumentError` rather than returning `{:error, reason}`. Returning errors changes the return types of the functions that return bare values, such as `Astro.lunar_phase_at/1`, so it belongs in a major release.

* [ ] **Remove `Astro.date_time_new_moon_at_or_before/1`** — deprecated in 2.6.2 in favour of `Astro.date_time_new_moon_before/1`; remove it in the next major release.

* [ ] **Use or drop CI's full-ephemeris download** — CI downloads the full DE440s kernel into `~/.cache/astro`, but the tests resolve the bundled kernel in `priv/` first, so nothing reads it. Point one test job at it with the `:ephemeris` option, or drop the step.
