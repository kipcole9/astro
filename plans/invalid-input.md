# Invalid input

**Status:** draft, 2026-10-31

A library must return `{:error, reason}` on invalid input rather than raise. A survey on 2026-10-31 called every public `Astro` function with ten invalid values in each argument (`nil`, `""`, `:""`, `2024.0`, `"2024"`, `%{}`, `[]`, `{1, 2, 3}`, `:april`, `-1`). Every function raised for some of them, almost always `FunctionClauseError` from a guard. `Astro.equinox/3` and `Astro.solstice/3` have since been fixed.

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

## The decision needed

Seven functions return a bare value rather than a tagged tuple: `sun_position_at/1`, `moon_position_at/1`, `sun_azimuth_elevation/2`, `sun_apparent_longitude/1`, `lunar_phase_at/1`, `illuminated_fraction_of_moon_at/1` and `lunar_phase_emoji/1`. Returning `{:error, reason}` from them changes their return type, which breaks callers that use the value directly. The options are to change them in a major release, to add tagged forms beside them, or to leave them raising and document it.

The functions that already return `{:ok, _}` or `{:error, _}` can gain error clauses without breaking anyone.
