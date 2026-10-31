# Eclipses

**Status:** implemented (v2.11.0), 2026-11-01

Astro 2.10 adds solar and lunar eclipses: finding them, classifying them, and giving their circumstances, globally and for a solar eclipse at a place. Like the rest of Astro they are computed from the Sun's and the Moon's apparent positions (the JPL ephemeris where it covers a date, the analytical series beyond it), so an eclipse is answered for any date within 50,000 years of 2000, and the implementation is written to be read as a guide to how eclipses are calculated.

## The reference

NASA's eclipse catalogues by Espenak and Meeus are the standard to test against. They cover −1999 to +3000 and give, per eclipse, the instant of greatest eclipse in Terrestrial Time, ΔT, the type, gamma and the magnitudes:

* **Solar** — [Five Millennium Catalog of Solar Eclipses](https://eclipse.gsfc.nasa.gov/SEcat5/SEcatalog.html), one page per century (for example [2001 to 2100](https://eclipse.gsfc.nasa.gov/SEcat5/SE2001-2100.html)), with the columns described in its [key](https://eclipse.gsfc.nasa.gov/SEcat5/SEcatkey.html). Each eclipse also has published Besselian elements (for example [2024 April 8](https://eclipse.gsfc.nasa.gov/SEbeselm/SEbeselm2001/SE2024Apr08Tbeselm.html)).

* **Lunar** — [Five Millennium Catalog of Lunar Eclipses](https://eclipse.gsfc.nasa.gov/LEcat5/LEcatalog.html), one page per century (for example [2001 to 2100](https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html)), with penumbral and umbral magnitudes and the durations of the penumbral, partial and total phases.

* **The canons** — Espenak and Meeus, *Five Millennium Canon of Solar Eclipses: −1999 to +3000* ([NASA/TP-2006-214141](https://eclipse.gsfc.nasa.gov/SEpubs/5MCSE.html)) and *Five Millennium Canon of Lunar Eclipses: −1999 to +3000* ([NASA/TP-2009-214172](https://eclipse.gsfc.nasa.gov/SEpubs/5MCLE.html)), which describe the method.

NASA computes from VSOP87 and ELP-2000/82, not the JPL ephemeris, so instants are compared in Terrestrial Time, where the two differ by about a second, and not in Universal Time, where Astro's ΔT and NASA's also differ before 1972 and after 2025.

## The method

### Solar eclipses: Besselian elements

The shadow of the Moon is described on the *fundamental plane*, through the centre of the Earth and perpendicular to the line from the Sun to the Moon. At any instant six quantities, the Besselian elements, describe it: `x` and `y`, the shadow axis on the plane in Earth radii; `d` and `μ`, the declination and Greenwich hour angle of the axis; and `l1` and `l2`, the radii of the penumbral and umbral cones on the plane, with the angles of the cones, `f1` and `f2`. Astro computes them directly from the geocentric apparent positions and distances of the Sun and the Moon, which is the method of the *Explanatory Supplement to the Astronomical Almanac*, rather than reading them from a published polynomial.

* **Finding an eclipse.** A solar eclipse can only occur at a new moon near a node of the Moon's orbit. Each new moon from Astro's search is tested: if the Moon's ecliptic latitude rules out any contact, it is skipped.

* **Greatest eclipse** is the instant the shadow axis passes closest to the centre of the Earth, the minimum of `√(x² + y²)`, found by a bracketed search. Gamma is that distance, signed by `y`.

* **The type** follows from gamma, the Earth's flattening and `l2`: partial when the axis misses the Earth, central otherwise, and then total or annular by the sign of the umbral radius where the axis meets the surface. A hybrid eclipse changes from one to the other along its path; it is found by testing the umbral radius at the surface at the ends and at the middle of the central line.

* **Magnitude** is the fraction of the Sun's diameter covered at greatest eclipse, and for a central eclipse the ratio of the Moon's apparent diameter to the Sun's.

* **Local circumstances** at a place follow from the elements and the place's geocentric coordinates: the times of first and last contact (and second and third for a total or annular eclipse), the instant of maximum, the magnitude and obscuration there, and the Sun's altitude at each.

### Lunar eclipses: the Earth's shadow

A lunar eclipse can only occur at a full moon near a node. The Moon's distance from the axis of the Earth's shadow, at the antisolar point, is compared with the radii of the penumbral and umbral shadows at the Moon's distance:

* **The shadow radii** are `Rp = 1.01 πm + ss + πs` and `Ru = 1.01 πm − ss + πs`, from the Moon's horizontal parallax `πm`, the Sun's semi-diameter `ss` and horizontal parallax `πs`. The factor `1.01` is Danjon's enlargement for the Earth's atmosphere, `1 + 1/85 − 1/594`, as NASA uses it ([Enlargement of Earth's Shadows](https://eclipse.gsfc.nasa.gov/LEcat5/shadow.html)).

* **Greatest eclipse** is the instant the Moon's centre is closest to the shadow axis; gamma is that distance in Earth radii, signed by the Moon's latitude.

* **The type and magnitudes** follow from that distance and the radii: penumbral, partial or total, with the penumbral and umbral magnitudes.

* **The contacts** P1, U1, U2, U3, U4 and P4 are the instants the Moon's limb touches each shadow, found by root-finding either side of greatest eclipse.

## Decisions

All four were accepted as recommended on 2026-10-31.

1. **The shadow convention for lunar eclipses.** Danjon's (`1.01`, NASA's catalogue, and geometrically right) or Chauvenet's (`1.02`, the older almanac convention, closer to observed timings of crater contacts). The two differ by about 0.006 in umbral magnitude and change the type of eclipses at the limit. **Decided:** Danjon's by default, matching the catalogue the tests use, with a `:shadow` option for `:chauvenet`.

2. **The Moon's radius for solar eclipses.** NASA uses `k1 = 0.272488` for the penumbra and `k2 = 0.272281`, a mean radius below the limb's peaks, for the umbra, so that a total phase is not overstated. **Decided:** NASA's two values, so that types and central durations compare with the catalogue.

3. **Scope for 2.10.** **Decided:** global circumstances for both kinds (finding, type, greatest eclipse, gamma, magnitudes, lunar contacts and durations) and local circumstances of a solar eclipse at a place. Defer the Saros series number to a later release (added in 2.10.0, 2026-11-01). **Revised 2026-11-01:** the geography of a solar eclipse (the central line, the northern and southern limits, path width) is in 2.10 too, as `Astro.solar_eclipse_path/2`, for drawing the path on a map.

4. **Where the code lives.** **Decided:** `Astro.Solar.Eclipse` and `Astro.Lunar.Eclipse`, beside `Astro.Lunar.MoonRiseSet` and `Astro.Lunar.CrescentVisibility`, taking moments as the other `Astro.Solar` and `Astro.Lunar` functions do, with the public functions in `Astro` taking dates and date-times.

## The API

In `Astro`, returning `{:ok, eclipse}` or `{:error, reason}`, with `{:error, :year_out_of_range}` beyond 50,000 years of 2000 as the new moon searches do:

* `solar_eclipse_at_or_after/1` and `solar_eclipse_before/1` — the next or previous solar eclipse as an `Astro.Solar.Eclipse` struct: `:type` (`:partial`, `:annular`, `:total` or `:hybrid`), `:greatest` (a `DateTime`), `:gamma`, `:magnitude`.

* `lunar_eclipse_at_or_after/2` and `lunar_eclipse_before/2` — an `Astro.Lunar.Eclipse` struct: `:type` (`:penumbral`, `:partial` or `:total`), `:greatest`, `:gamma`, `:penumbral_magnitude`, `:umbral_magnitude`, and the contacts `:penumbral_begins`, `:partial_begins`, `:total_begins`, `:total_ends`, `:partial_ends` and `:penumbral_ends`, `nil` for those the eclipse does not have.

* `solar_eclipse_at/3` — the local circumstances of a solar eclipse at a location, given an eclipse or a date: an `Astro.Solar.Eclipse.Local` struct with the type there, the contacts, the instant of maximum, magnitude, obscuration, and the Sun's altitude at each, or `{:error, :not_visible}` where the eclipse is not seen there.

* `solar_eclipse_path/2` — the path of a total, annular or hybrid solar eclipse, given an eclipse or a date: an `Astro.Solar.Eclipse.Path` struct with the type and the `:central_line`, `:northern_limit` and `:southern_limit` as lists of `%{time, location}` points, `location` a `Geo.Point` of `{longitude, latitude}`; central-line points also carry `:type`, `:width` (km), `:duration` (s) and `:sun_altitude`. Option `:interval` in seconds, default 60. `{:error, :no_path}` for a partial eclipse.

* `lunar_eclipse_at/3` — the same for a lunar eclipse: an `Astro.Lunar.Eclipse.Local` struct with the eclipse's fields and the Moon's topocentric altitude at each contact, or `{:error, :not_visible}` where the Moon is below the horizon throughout.

Instants are UTC `DateTime`s, as the new moon searches return them, except that the local functions return them in the location's time zone by default, taking `:time_zone`, `:time_zone_database` and `:time_zone_resolver` as `sunrise/3` does. The lunar functions take `:shadow`; the global solar ones have no options, so they take none.

The Besselian `μ` is the Greenwich hour angle at the moment, not NASA's ephemeris hour angle (TD read as UT); the two differ by ΔT's worth of rotation, which local circumstances must not apply twice.

For a total or annular eclipse whose axis misses the Earth, NASA's magnitude is the fraction of the Sun's diameter covered at the limb, as for a partial eclipse, not the diameter ratio. The local magnitude NASA and the USNO give is that fraction everywhere, `(L1 − m)/(L1 + L2)`, exceeding 1 inside the umbra.

## Accuracy

Within the JPL ephemeris, instants of greatest eclipse should agree with NASA's to about a second in Terrestrial Time and gamma and magnitudes to 0.0001 to 0.001, the size of the difference between DE440 and VSOP87/ELP. Beyond it the Meeus Moon series is good to about 10″, about 20 s of the Moon's motion. In Universal Time every result far from the present carries ΔT's uncertainty, which before about 1600 exceeds the time of an eclipse's passage over a place, so local circumstances in antiquity are as uncertain as ΔT.

## Tasks

### Done

* [x] **Region of partial eclipse** — `Astro.solar_eclipse_path/2` adds the penumbral limits, the sunrise and sunset limits (lists of lines, two branches possible), the curves of maximum eclipse at sunrise and sunset, and first and last contact; a partial eclipse returns its region. First and last contact within 0.3 s of NASA (EclipseWise, TD) for eight eclipses; the curves agree with the local circumstances within 0.01 s with the Sun on the horizon. 2026-11-01, v2.11.0.

* [x] **Saros series** — `:saros` on solar and lunar eclipses (`Astro.Saros`), from the lunation (`Astro.Lunar.lunation_at/1`) by `s ≡ 38 (n − c) (mod 223)` and a fitted band of series in progress; NASA's number for all 694 solar and 703 lunar eclipses tested, with the lunation. 2026-11-01, v2.10.0.

* [x] **Documentation** — the `Astro` eclipse functions in the house format with Accuracy and Reference sections, and an eclipses section in `guides/accuracy.md` (global, local and path accuracy against NASA and the USNO, and ΔT's effect on paths). 2026-11-01.

* [x] **Path** — `Astro.solar_eclipse_path/2` (`Astro.Solar.Eclipse.Path`): the central line and the northern and southern limits as timed `{longitude, latitude}` points, the limits following the horizon where they are beyond it so the band closes; width, duration and Sun altitude on the central line. Against NASA's path tables for eight eclipses 1999–2027 (674 instants, NASA's ΔT removed): within 0.7 km across the path with the Sun 20° or more up, 2.6 km over Antarctica with it lower, 2 s along it; width within 1 km and 0.6%, duration 0.7 s. `test/solar_eclipse_path_test.exs`, `test/data/solar_eclipses/nasa_paths.csv`. 2026-11-01.

* [x] **Local circumstances** — `Astro.solar_eclipse_at/3` (`Astro.Solar.Eclipse.Local`) and `Astro.lunar_eclipse_at/3` (`Astro.Lunar.Eclipse.Local`). Against the USNO's computer for 17 eclipses and places 1999–2026, with its ΔT removed by shifting the longitude: partial contacts within 1.1 s, totality and annularity contacts within 2 s (4 s near an annular path's edge; the USNO's Moon is a little larger than NASA's `k2`), magnitude 0.0005, obscuration 0.0012, altitudes 0.05°, types and visibility the same; the USNO's maximum is 1 s before its own C2–C3 midpoint. The Moon's altitude agrees with moonrise and moonset to 0.00001°. `test/solar_eclipse_local_test.exs`, `test/lunar_eclipse_local_test.exs`. 2026-11-01.

* [x] **Solar eclipses** — `Astro.Solar.Eclipse` (Besselian elements, finding, greatest eclipse, type including hybrid, magnitude) and `Astro.solar_eclipse_at_or_after/1` / `solar_eclipse_before/1`. Against NASA in TD: 1901–2100 greatest within 0.6 s, gamma 0.00006, magnitude 0.00007, every type the same (hybrids included); elements for 2024-04-08 within 1e-4 radii; series centuries within 9 s (1801–1900), 32 s (2901–3000), 80 s (1–100) and 130 s (−999 to −900), magnitudes 0.0014. `test/solar_eclipse_test.exs`. 2026-11-01.

* [x] **Lunar eclipses** — `Astro.Lunar.Eclipse` and `Astro.lunar_eclipse_at_or_after/2` / `lunar_eclipse_before/2`. Against NASA in TD: 1901–2100 greatest within 2.7 s (0.5 s mean), gamma 0.00014, magnitudes 0.0004, partial and total durations 0.07 min, every type the same; series centuries within 15 s (1801–1900), 40 s (2901–3000), 78 s (1–100) and 141 s (−999 to −900), magnitudes 0.002. `test/lunar_eclipse_test.exs`. 2026-10-31.

* [x] **Decisions** — all four accepted as recommended. 2026-10-31.
