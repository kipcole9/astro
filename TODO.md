# TODO

Work planned for Astro. The detail of anything shipped is in the CHANGELOG.

## Open

* [ ] **Calendar support** — day-level new moon and solar longitude searches, a `:utc_offset` and `limb: :center` for rise and set, and a crescent visibility day search, so that Calendrical computes no astronomy of its own. Plan in [plans/calendar-support.md](plans/calendar-support.md).

* [ ] **Answer every date from JPL or Meeus** — positions come from the JPL ephemeris where it covers the moment and from the Meeus series where it does not, so no consumer checks coverage or sees `{:error, :not_found}`. Design and tasks in [plans/jpl-meeus-fallback.md](plans/jpl-meeus-fallback.md).

* [ ] **Remove `Astro.date_time_new_moon_at_or_before/1`** — deprecated in 2.6.2 in favour of `Astro.date_time_new_moon_before/1`; remove it in the next major release.

## Done

* [x] **Documentation as a learning guide** — every primary function describes its calculation, accuracy and references, with an accuracy guide; see [plans/learning-documentation.md](plans/learning-documentation.md). 2026-10-31.

* [x] **Review the ΔT model** — Espenak and Meeus before 1972, IERS 1972–2025, a smooth join to the long-term parabola after; see [plans/delta-t.md](plans/delta-t.md). 2026-10-31.

* [x] **Return errors rather than raise on invalid input** — the tuple-returning `Astro` functions return errors for invalid arguments and beyond 50,000 years; the seven bare-value functions keep raising, by decision. See [plans/invalid-input.md](plans/invalid-input.md). 2026-10-31.

* [x] **Drop CI's unused full-ephemeris download** — CI tests the bundled kernel, the one hex installs ship. 2026-10-18, v2.8.0.
