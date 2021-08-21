# Changelog for Astro version 0.4.0

This is the changelog for Astro version 0.5.0 released on August 21st, 2021.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Bug Fixes

* Updates documentation to be clear about installation and setup requirements for `tz_world`

* Fixes test data for Sao Paulo now that it no longer uses DST

* Ensure `:astro` is started in test mode


This is the changelog for Astro version 0.4.0 released on February 16th, 2020.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Breaking Change

* When no timezone is found the return is changed from `{:error, :timezone_not_found}` to `{:error, :time_zone_not_found}` to be consistent with Elixir and `TzData`.

# Changelog for Astro version 0.3.0

This is the changelog for Astro version 0.3.0 released on December 9th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Change in behaviour

* Seconds are no longer truncated to zero when calculating datetimes and durations

### Enhancements

* Add `Astro.solar_noon/2` to return the true solar noon for a location and date

* Add `Astro.hours_of_daylight/2` to return hours, minutes and seconds as a `Time.t()` representing the number of daylight hours for a give location and date

* Add `Astro.sun_apparent_longitude/1` to return the apparent solar longitude on a given date. The result, a number of degrees between 0 and 360, can be used to determine the seasons.

# Changelog for Astro version 0.2.0

This is the changelog for Astro version 0.2.0 released on December 6th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Enhancements

* Add `Astro.equinox/2`and `Astro.solstice/2` to calculate solstices and equinoxes for a year. From these can be derived the seasons.

* Add `Astro.Time.datetime_from_julian_days/1`

* Add `Astro.Time.utc_datetime_from_terrestrial_datetime/1`

# Changelog for Astro version 0.1.0

This is the changelog for Astro version 0.1.0 released on December 5th, 2019.  For older changelogs please consult the release tag on [GitHub](https://github.com/kipcole9/astro/tags)

### Enhancements

* Initial release includes `Astro.sunrise/3` and `Astro.sunset/3`.  See the readme for further roadmap details.
