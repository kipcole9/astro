# Calendar support

**Status:** implemented (v2.10.0), 2026-10-31

Calendrical is to compute no astronomy of its own: every astronomical quantity a calendar needs comes from Astro, and Calendrical keeps only the calendar rules. A survey of Calendrical on 2026-10-31 found what it still computes itself; this plan is the Astro side, the functions Calendrical needs so that it can stop. The Calendrical side is `plans/astro-only.md` in that repository.

## What Calendrical computes today

* **The lunisolar calendars** (`Calendrical.Lunisolar`) find the local day of each new moon, the local day of the December solstice by an estimate and a day-by-day walk of the Sun's longitude at local midnight, and the local day of each solar term. They only ever use days, never moments, converting with offsets that change with the era (Beijing local mean time before 1929, UTC+8 after; similar histories for Seoul, Tokyo and Hanoi).

* **The Islamic calendars** search day by day, up to 60 days, for the first evening with a visible crescent; take the local date of a conjunction by adding a fixed three hours; and compute centre-of-disk sunset by passing `solar_elevation: 90.5667`.

* **`Calendrical.DayStart`** asks for sunset on the local date but in UTC. West of about 30°W the local evening's sunset falls on the next UTC day, so it is given the previous evening's sunset: in Los Angeles a Hebrew day with `day_start: :sunset` begins at 16:00, four hours before sunset. This is a defect in released Calendrical.

* **Hebrew** turns a longitude into a mean solar time offset (`round(longitude * 240)` seconds).

## New functions

Day-level functions answer with a day number, days since 0000-01-01 as Calendrical's `iso_days` and Astro's moments count them, for a local time given by an offset in days or by a function from a moment to an offset (so that an era's change of zone is respected exactly as now). Because only the day matters, they refine an event only when its estimate is near a local midnight, which recovers most of the speed Calendrical had on Astro 2.9.

* **`Astro.Lunar.new_moon_day_before(day, offset)` and `new_moon_day_on_or_after(day, offset)`** — the local day of the last new moon before the start of `day`, and of the first at or after it. Replace `Calendrical.Lunisolar.new_moon_before/2` and `new_moon_on_or_after/2`.

* **`Astro.Solar.solar_longitude_day_on_or_after(lambda, day, offset)` and `solar_longitude_day_before(lambda, day, offset)`** — the local day the Sun's apparent longitude first reaches `lambda` at or after the start of `day`, and the last day before it. Replace `solar_longitude_on_or_after/3`, `december_solstice_on_or_before/2` and its walk, and the date search in `solar_term/3`.

* **A `:utc_offset` option (seconds) on `Astro.sunset/3`, `sunrise/3`, `moonset/3`, `moonrise/3` and `new_visible_crescent/3,4`** — selects the event whose date at that offset is `date`, returned in UTC. Fixes `DayStart` and replaces the Islamic code's own local-date arithmetic.

* **`limb: :center` on `Astro.sunset/3` and `sunrise/3`**, as `moonset/3` already has. Replaces the hand-built `solar_elevation: 90.5667`.

* **`Astro.date_new_visible_crescent_on_or_after(location, date, method \\ :odeh, options \\ [])` and `_on_or_before`** — the first (last) evening on which the crescent is visible (category `:A` to `:C`, or a `:threshold` option), as `{:ok, Date.t()}`. Replace the 60-day search in `Calendrical.Islamic.Visibility`.

* **`Astro.Time.offset_from_longitude/1` accepting a `Geo.Point`** — for Hebrew's mean solar time.

Existing functions already cover the rest: `Astro.equinox/3` and `solar_noon/2` for Persian, `equinox/3` and the phase searches for astronomical Easter, `moonset/3` with `limb: :center` for Umm al-Qura.

## Decisions

* **2026-10-31 — Day-level searches return day numbers and take an offset or an offset function.** Calendrical works in days and changes zone by era; a numeric offset alone would differ from today's results for events across a zone change.

## Tasks

### Done

* [x] **Day-level new moon searches** — `Astro.Lunar.new_moon_day_before/2` and `new_moon_day_on_or_after/2`: the same day as the moment searches for all 31,440 days and offsets tested over ±40,000 years, including a zone change and the two 1900–2100 new moons within 15 s of UTC+8 midnight; 20 µs against 43 µs. Calendrical's cold lunisolar year 0.21–0.29 ms with them. 2026-10-31.

* [x] **Day-level solar longitude searches** — `Astro.Solar.solar_longitude_day_on_or_after/3` and `solar_longitude_day_on_or_before/3`: the same day as the moment searches for all 48,475 cases tested over ±40,000 years; 10 µs against 150 µs. The Sun's rate over ±50,000 years is 0.9475–1.0257° a day, so the bounds are 0.90–1.08. With both day searches, Calendrical's solstices and solar terms are unchanged and a cold lunisolar year takes 0.17–0.27 ms. 2026-10-31.

* [x] **`:utc_offset` and `limb: :center` for rise and set** — `:utc_offset` (whole seconds within ±14 h) chooses the event by its date at the offset; `limb: :center` gives the Sun's centre at −34′, identical to `solar_elevation: 90°34′`. Passed through `Calendrical.DayStart` in the scratch copy, it fixes the Los Angeles sunset day. 2026-10-31.

* [x] **Crescent visibility searches** — `Astro.first_visible_crescent_on_or_before/4` and `_on_or_after/4` (and the moment-level forms in `Astro.Lunar.CrescentVisibility`), with `:visible` and `:utc_offset`; `new_visible_crescent/4` takes options for every method. Calendrical's `phasis_on_or_before/3` and `phasis_on_or_after/3` are these evenings plus one day on all 1,220 days compared (Cairo and Mecca, all three criteria). 2026-10-31.

* [x] **`offset_from_longitude/1` for `Geo.Point`.** 2026-10-31.
