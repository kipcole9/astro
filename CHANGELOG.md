# Changelog

## Astro version 0.10.0

This is the changelog for Astro version 0.10.0 released on November 7th, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Enhancements

* Adds `Astro.Math.floor/1` and `Astro.Math.ceil/1` which are needed to support `Tempo`.

## Astro version 0.9.2

This is the changelog for Astro version 0.9.2 released on September 1st, 2022.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Bug Fixes

* Update `:tz_world` to "~> 1.0" which will also remove Elixir 1.14 warnings

## Astro version 0.9.1

This is the changelog for Astro version 0.9.1 released on October 23rd, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Bug Fixes

* Ensure that `gregorian_seconds` is an integer before passing it to `Tzdata.periods_for_time/3`. Thanks to @dvic for the report. Fixes #2.

## Astro version 0.9.0

This is the changelog for Astro version 0.9.0 released on October 8th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

**Please note that Elixir 1.11 or later is required.**

### Enhancements

* Adds `Astro.lunar_phase_emoji/1` to produce a single grapheme string representing the image of the moon phase for a given lunar angle.

## Astro version 0.8.0

This is the changelog for Astro version 0.8.0 released on October 3rd, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

**Please note that Elixir 1.11 or later is required.**

### Enhancements

* Convert some identity functions to macros which improves runtime performance

* Add additional specs and docs to `Astro.Math` module

## Astro version 0.7.0

This is the changelog for Astro version 0.7.0 released on September 10th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

**Please note that Elixir 1.11 or later is required.**

### Bug Fixes

* Revert `Astro` back to a pure library application. The supervisor for `TzWorld` still needs to be started. This fix brings the code back into line with the [README](/readme.html). Thanks to @dvic for the report. Closes #1.

## Astro version 0.6.0

This is the changelog for Astro version 0.6.0 released on September 5th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

**Please note that Elixir 1.11 or later is required.**

### Bug Fixes

* Fix `Astro.Math.atan_r/2`

* Fix ephemeris calculation

### Breaking changes

* Change `Time.date_time_{from, to}_iso_days/1` to `Time.date_time_{from, to}_moment/1`

### Enhancements

* Remove dependency on `ex_cldr_calendar` and `jason`

* Add `Astro.sun_position_at/1`

* Add `Astro.moon_position_at/1`

* Add `Astro.illuminated_fraction_of_moon_at/1`

## Astro version 0.5.0

This is the changelog for Astro version 0.5.0 released on August 26th, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

**Please note that Elixir 1.11 or later is required.**

### Bug Fixes

* Updates documentation to be clear about installation and setup requirements for `tz_world`

* Fixes test data for São Paulo now that it no longer uses DST

* Ensure `:astro` is started in test mode

### Enhancements

This primary focus of this release is to add lunar calculations for moon phase.

* Adds `Astro.date_time_new_moon_before/1`

* Adds `Astro.date_time_new_moon_at_or_after/1`

* Adds `Astro.lunar_phase_at/1`

* Adds `Astro.date_time_lunar_phase_at_or_before/2`

* Adds `Astro.date_time_lunar_phase_at_or_after/2`

## Astro version 0.4.0

This is the changelog for Astro version 0.4.0 released on February 16th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Breaking Change

* When no timezone is found the return is changed from `{:error, :timezone_not_found}` to `{:error, :time_zone_not_found}` to be consistent with Elixir and `TzData`.

## Astro version 0.3.0

This is the changelog for Astro version 0.3.0 released on December 9th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Change in behaviour

* Seconds are no longer truncated to zero when calculating datetimes and durations

### Enhancements

* Add `Astro.solar_noon/2` to return the true solar noon for a location and date

* Add `Astro.hours_of_daylight/2` to return hours, minutes and seconds as a `Time.t()` representing the number of daylight hours for a give location and date

* Add `Astro.sun_apparent_longitude/1` to return the apparent solar longitude on a given date. The result, a number of degrees between 0 and 360, can be used to determine the seasons.

## Astro version 0.2.0

This is the changelog for Astro version 0.2.0 released on December 6th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Enhancements

* Add `Astro.equinox/2`and `Astro.solstice/2` to calculate solstices and equinoxes for a year. From these can be derived the seasons.

* Add `Astro.Time.datetime_from_julian_days/1`

* Add `Astro.Time.utc_datetime_from_terrestrial_datetime/1`

## Astro version 0.1.0

This is the changelog for Astro version 0.1.0 released on December 5th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Enhancements

* Initial release includes `Astro.sunrise/3` and `Astro.sunset/3`.  See the readme for further roadmap details.
