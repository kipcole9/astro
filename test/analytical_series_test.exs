defmodule Astro.AnalyticalSeriesTest do
  use ExUnit.Case, async: true

  alias Astro.{Ephemeris, Lunar, Math, Solar}

  # Largest differences from JPL DE440s measured over 20,000 moments from
  # 1900 to 2100 (2026-10-31), with a margin.
  #
  # Sun: longitude 3.3″, latitude 2.6″, right ascension 3.6″, declination
  # 2.0″, distance 12,200 km.
  @sun_longitude_tolerance 4.0 / 3600.0
  @sun_latitude_tolerance 3.0 / 3600.0
  @sun_right_ascension_tolerance 4.5 / 3600.0
  @sun_declination_tolerance 2.5 / 3600.0
  @sun_distance_tolerance_km 15_000.0

  # Moon: longitude 17.9″, latitude 4.9″, right ascension 17.5″,
  # declination 7.4″, distance 12.7 km.
  @moon_longitude_tolerance 20.0 / 3600.0
  @moon_latitude_tolerance 6.0 / 3600.0
  @moon_right_ascension_tolerance 20.0 / 3600.0
  @moon_declination_tolerance 9.0 / 3600.0
  @moon_distance_tolerance_km 15.0

  # The bundled ephemeris starts just after midnight on 1 January 1900.
  @first ~D[1900-01-02]
  @last ~D[2099-12-30]
  @samples 2_000

  defp moments do
    from = Astro.Time.date_time_to_moment(@first)
    to = Astro.Time.date_time_to_moment(@last)

    Enum.map(0..(@samples - 1), fn index ->
      from + index * (to - from) / (@samples - 1)
    end)
  end

  defp angular_difference(a, b) do
    difference = a - b
    difference - 360.0 * Float.round(difference / 360.0)
  end

  describe "the Sun's analytical series agree with JPL over 1900-2100" do
    test "in ecliptic longitude, latitude and distance" do
      for moment <- moments() do
        {:ok, {jpl_longitude, jpl_latitude, jpl_distance_km}} =
          Ephemeris.sun_ecliptic_position(moment)

        {longitude, latitude, distance_au} = Solar.analytical_solar_ecliptic_position(moment)

        assert abs(angular_difference(longitude, jpl_longitude)) < @sun_longitude_tolerance
        assert abs(latitude - jpl_latitude) < @sun_latitude_tolerance
        assert abs(Math.au_to_km(distance_au) - jpl_distance_km) < @sun_distance_tolerance_km
      end
    end

    test "in right ascension and declination" do
      for moment <- moments() do
        {:ok, {jpl_right_ascension, jpl_declination, _distance}} =
          Ephemeris.sun_position_from_moment(moment)

        {right_ascension, declination, _distance} = Solar.analytical_solar_position(moment)

        assert abs(angular_difference(right_ascension, jpl_right_ascension)) <
                 @sun_right_ascension_tolerance

        assert abs(declination - jpl_declination) < @sun_declination_tolerance
      end
    end
  end

  describe "the Moon's analytical series agree with JPL over 1900-2100" do
    test "in ecliptic longitude, latitude and distance" do
      for moment <- moments() do
        {:ok, {jpl_longitude, jpl_latitude, jpl_distance_km}} =
          Ephemeris.moon_ecliptic_position(moment)

        {longitude, latitude, distance_m} = Lunar.analytical_lunar_ecliptic_position(moment)

        assert abs(angular_difference(longitude, jpl_longitude)) < @moon_longitude_tolerance
        assert abs(latitude - jpl_latitude) < @moon_latitude_tolerance
        assert abs(distance_m / 1000.0 - jpl_distance_km) < @moon_distance_tolerance_km
      end
    end

    test "in right ascension and declination" do
      for moment <- moments() do
        {:ok, {jpl_right_ascension, jpl_declination, _distance}} =
          Ephemeris.moon_position_from_moment(moment)

        {right_ascension, declination, _distance} = Lunar.analytical_lunar_position(moment)

        assert abs(angular_difference(right_ascension, jpl_right_ascension)) <
                 @moon_right_ascension_tolerance

        assert abs(declination - jpl_declination) < @moon_declination_tolerance
      end
    end
  end

  describe "the analytical series far from the present" do
    test "give a position for dates no ephemeris covers" do
      for year <- [-10_000, -2_000, 1_000, 3_000, 10_000] do
        moment = Calendar.ISO.date_to_iso_days(year, 6, 21) * 1.0

        {sun_right_ascension, sun_declination, sun_distance} =
          Solar.analytical_solar_position(moment)

        assert sun_right_ascension >= 0.0 and sun_right_ascension < 360.0
        assert abs(sun_declination) <= 24.5
        assert sun_distance > 0.98 and sun_distance < 1.02

        {moon_right_ascension, moon_declination, moon_distance} =
          Lunar.analytical_lunar_position(moment)

        assert moon_right_ascension >= 0.0 and moon_right_ascension < 360.0
        assert abs(moon_declination) <= 30.0
        assert moon_distance > 3.5e8 and moon_distance < 4.1e8
      end
    end
  end
end
