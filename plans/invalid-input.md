# Invalid input

**Status:** implemented (v2.10.0), 2026-10-31

A library must return `{:error, reason}` on invalid input rather than raise. A survey on 2026-10-31 called every public `Astro` function with ten invalid values in each argument (`nil`, `""`, `:""`, `2024.0`, `"2024"`, `%{}`, `[]`, `{1, 2, 3}`, `:april`, `-1`). Every function raised for some of them, almost always `FunctionClauseError` from a guard. The functions that return `{:ok, _}` or `{:error, _}` have since been fixed; the table below is the survey as it was.

## Survey

| Function and argument | Raises on | Exception |
|---|---|---|
| `sunrise/3`, `sunset/3`: location | 10 of 10 | `FunctionClauseError`, `RuntimeError` |
| `sunrise/3`, `sunset/3`: date | 10 of 10 | `FunctionClauseError` |
| `sunrise/3`: options | 10 of 10 | `FunctionClauseError`, `RuntimeError` |
| `moonrise/3`, `moonset/3`: location, date, options | 10 of 10 | `FunctionClauseError`, `RuntimeError` |
| `solar_noon/2`: location | 9 of 10 | `FunctionClauseError` |
| `hours_of_daylight/2`, `duration_of_daylight/2` | 10 of 10 | `FunctionClauseError`, `RuntimeError` |
| `sun_position_at/1`, `moon_position_at/1` | 10 of 10 | `FunctionClauseError` |
| `sun_azimuth_elevation/2`: location, date time | 9–10 of 10 | `FunctionClauseError` |
| `sun_apparent_longitude/1` | 10 of 10 | `FunctionClauseError` |
| `lunar_phase_at/1`, `illuminated_fraction_of_moon_at/1` | 10 of 10 | `FunctionClauseError` |
| `lunar_phase_emoji/1` | 10 of 10 | `FunctionClauseError` |
| `date_time_new_moon_*/1` | 10 of 10 | `FunctionClauseError` |
| `date_time_lunar_phase_at_or_before/2`: date | 10 of 10 | `FunctionClauseError` |
| `date_time_lunar_phase_at_or_after/2`: phase | 8 of 10 | `ArithmeticError` |
| `new_visible_crescent/3`: location, date, method | 9–10 of 10 | `FunctionClauseError` |

The new moon searches also raise `ArgumentError` more than 50,000 years from J2000, a bound chosen on 2026-10-31.

## Decisions

* **2026-10-31 — The seven bare-value functions keep raising.** They return a value rather than a tagged tuple, and the user decided they may raise on invalid input.

## The question that was put

Seven functions return a bare value rather than a tagged tuple: `sun_position_at/1`, `moon_position_at/1`, `sun_azimuth_elevation/2`, `sun_apparent_longitude/1`, `lunar_phase_at/1`, `illuminated_fraction_of_moon_at/1` and `lunar_phase_emoji/1`. Returning `{:error, reason}` from them changes their return type, which breaks callers that use the value directly. The options are to change them in a major release, to add tagged forms beside them, or to leave them raising and document it.

The functions that already return `{:ok, _}` or `{:error, _}` can gain error clauses without breaking anyone.

## Tasks

### Done

* [x] **The new moon bound** — the five `Astro` moon searches return `{:error, :year_out_of_range}` beyond 50,000 years from J2000, as equinoxes and solstices do; the `Astro.Lunar` moment functions, which Calendrical's lunisolar compiler pipes, still raise. 2026-10-31.

* [x] **Return errors from the tuple-returning functions** — location, date, options, phase, method, time zone resolver and database are checked, a missing tz_world backend is reported, and `test/invalid_input_test.exs` covers each. 2026-10-31.

* [x] **Equinox and solstice** — `:invalid_year`, `:invalid_event` and `:year_out_of_range`. 2026-10-31.
