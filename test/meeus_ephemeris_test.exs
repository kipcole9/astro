defmodule Astro.Ephemeris.MeeusTest do
  use ExUnit.Case, async: true

  doctest Astro.Ephemeris.Meeus

  alias Astro.Ephemeris
  alias Astro.Ephemeris.Meeus

  # Largest differences from JPL DE440s measured over 20,000 moments from
  # 1900 to 2100 (2026-10-31), with a margin: longitude 3.3″, right
  # ascension 3.6″, declination 2.0″, distance 12,200 km.
  @longitude_tolerance 4.0 / 3600.0
  @right_ascension_tolerance 4.5 / 3600.0
  @declination_tolerance 2.5 / 3600.0
  @distance_tolerance_km 15_000.0

  @first ~D[1900-01-02]
  @last ~D[2099-12-30]
  @samples 2_000

  defp dynamical_times do
    from = dynamical_time(@first)
    to = dynamical_time(@last)

    Enum.map(0..(@samples - 1), fn index ->
      from + index * (to - from) / (@samples - 1)
    end)
  end

  defp dynamical_time(date) do
    date
    |> Astro.Time.date_time_to_moment()
    |> Astro.Time.dynamical_time_from_moment()
  end

  defp angular_difference(a, b) do
    difference = a - b
    difference - 360.0 * Float.round(difference / 360.0)
  end

  describe "the Sun agrees with JPL over 1900-2100" do
    test "in ecliptic longitude, latitude and distance" do
      for dynamical_time <- dynamical_times() do
        {:ok, {jpl_longitude, jpl_latitude, jpl_distance}} =
          Ephemeris.sun_ecliptic_position_dt(dynamical_time)

        {:ok, {longitude, latitude, distance}} = Meeus.sun_ecliptic_position_dt(dynamical_time)

        assert abs(angular_difference(longitude, jpl_longitude)) < @longitude_tolerance
        assert abs(latitude - jpl_latitude) < @declination_tolerance
        assert abs(distance - jpl_distance) < @distance_tolerance_km
      end
    end

    test "in right ascension and declination" do
      for dynamical_time <- dynamical_times() do
        {:ok, {jpl_right_ascension, jpl_declination, _distance}} =
          Ephemeris.sun_position_dt(dynamical_time)

        {:ok, {right_ascension, declination, _}} = Meeus.sun_position_dt(dynamical_time)

        assert abs(angular_difference(right_ascension, jpl_right_ascension)) <
                 @right_ascension_tolerance

        assert abs(declination - jpl_declination) < @declination_tolerance
      end
    end
  end

  describe "the Sun far from the present" do
    test "returns a position for dates no ephemeris covers" do
      for year <- [-10_000, -2_000, 1_000, 3_000, 10_000] do
        moment = Calendar.ISO.date_to_iso_days(year, 6, 21) * 1.0
        dynamical_time = Astro.Time.dynamical_time_from_moment(moment)

        assert {:ok, {right_ascension, declination, distance}} =
                 Meeus.sun_position_dt(dynamical_time)

        assert right_ascension >= 0.0 and right_ascension < 360.0
        assert abs(declination) <= 24.5
        assert distance > 1.4e8 and distance < 1.6e8
      end
    end
  end
end
