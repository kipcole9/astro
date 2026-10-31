defmodule Astro.OutOfRangeTest do
  use ExUnit.Case, async: true

  # No ephemeris Astro loads, bundled or full, covers the year 1000.
  @date ~D[1000-06-01]
  @date_time ~U[1000-06-01 12:00:00Z]
  @sydney {151.20666584, -33.8559799094}

  describe "the Astro functions answer outside the ephemeris" do
    test "lunar phase searches find the phase they were asked for" do
      for {search, phase} <- [
            {&Astro.date_time_lunar_phase_at_or_before/2, 180.0},
            {&Astro.date_time_lunar_phase_at_or_after/2, 90.0}
          ] do
        assert {:ok, date_time} = search.(@date, phase)
        assert_in_delta Astro.lunar_phase_at(date_time), phase, 0.001
      end

      # The nearest new moon is one of the new moons either side of the date.
      assert {:ok, nearest} = Astro.date_time_new_moon_nearest(@date)
      assert {:ok, before} = Astro.date_time_new_moon_before(@date)
      assert {:ok, at_or_after} = Astro.date_time_new_moon_at_or_after(@date)

      assert Enum.any?([before, at_or_after], fn new_moon ->
               abs(DateTime.diff(nearest, new_moon, :millisecond)) < 1_000
             end)
    end

    test "the phase, illumination and the Sun's longitude are numbers in range" do
      phase = Astro.lunar_phase_at(@date)
      assert phase >= 0.0 and phase < 360.0

      fraction = Astro.illuminated_fraction_of_moon_at(@date)
      assert fraction >= 0.0 and fraction <= 1.0

      # Early June, about 70° along the ecliptic.
      assert_in_delta Astro.sun_apparent_longitude(@date), 70.0, 2.0
    end

    test "the Sun and the Moon have positions" do
      assert %Geo.PointZ{coordinates: {_right_ascension, declination, distance}} =
               Astro.sun_position_at(@date)

      assert_in_delta declination, 22.0, 1.0
      assert distance > 1.5e11 and distance < 1.53e11

      assert %Geo.PointZ{coordinates: {_, moon_declination, moon_distance}} =
               Astro.moon_position_at(@date_time)

      assert abs(moon_declination) <= 30.0
      assert moon_distance > 3.5e8 and moon_distance < 4.1e8

      assert {azimuth, elevation} = Astro.sun_azimuth_elevation(@sydney, @date_time)
      assert azimuth >= 0.0 and azimuth < 360.0
      assert elevation >= -90.0 and elevation <= 90.0
    end

    test "solar noon, sunrise, sunset, moonrise and moonset" do
      # Sydney is about 10 hours east of Greenwich, so its noon is near 02:00 UTC.
      assert {:ok, %DateTime{hour: hour}} = Astro.solar_noon(@sydney, @date)
      assert hour in 1..2

      for event <- [&Astro.sunrise/3, &Astro.sunset/3, &Astro.moonrise/3, &Astro.moonset/3] do
        assert {:ok, %DateTime{}} = event.(@sydney, @date, time_zone: :utc)
      end

      # A June day in Sydney is short.
      assert {:ok, %Time{hour: hours}} = Astro.hours_of_daylight(@sydney, @date)
      assert hours in 9..10
    end
  end

  # `solar_position/1` and `lunar_position/1` give right ascension in the
  # range -180 to 180.
  defp signed(right_ascension) do
    if right_ascension > 180.0 do
      right_ascension - 360.0
    else
      right_ascension
    end
  end

  describe "Astro.Solar and Astro.Lunar answer outside the ephemeris from the analytical series" do
    test "the Sun's position and ecliptic longitude" do
      moment = Astro.Time.date_time_to_moment(@date)
      {longitude, _latitude, _distance} = Astro.Solar.analytical_solar_ecliptic_position(moment)
      {right_ascension, declination, distance} = Astro.Solar.analytical_solar_position(moment)

      assert Astro.Solar.solar_ecliptic_longitude(moment) == longitude

      assert Astro.Solar.solar_position(moment) ==
               {signed(right_ascension), declination, distance}
    end

    test "the Moon's position, ecliptic coordinates and phase" do
      moment = Astro.Time.date_time_to_moment(@date)

      {longitude, latitude, distance} = Astro.Lunar.analytical_lunar_ecliptic_position(moment)
      {right_ascension, declination, _distance} = Astro.Lunar.analytical_lunar_position(moment)

      assert Astro.Lunar.lunar_ecliptic_longitude(moment) == longitude
      assert Astro.Lunar.lunar_latitude(moment) == latitude
      assert Astro.Lunar.lunar_distance(moment) == distance

      assert Astro.Lunar.lunar_position(moment) ==
               {signed(right_ascension), declination, distance}

      solar_longitude = Astro.Solar.solar_ecliptic_longitude(moment)
      expected_phase = Astro.Math.mod(longitude - solar_longitude, 360)
      assert Astro.Lunar.lunar_phase_at(moment) == expected_phase
    end
  end

  test "inside the ephemeris Astro.Solar and Astro.Lunar answer from JPL" do
    moment = Astro.Time.date_time_to_moment(~D[2024-06-01])
    {:ok, {sun_longitude, _, _}} = Astro.Ephemeris.sun_ecliptic_position(moment)
    {:ok, {moon_longitude, _, _}} = Astro.Ephemeris.moon_ecliptic_position(moment)

    assert Astro.Solar.solar_ecliptic_longitude(moment) == sun_longitude
    assert Astro.Lunar.lunar_ecliptic_longitude(moment) == moon_longitude
  end

  test "the solar longitude searches find a solstice outside the ephemeris" do
    after_moment = Astro.Time.date_time_to_moment(~D[1500-11-01])
    prior_moment = Astro.Time.date_time_to_moment(~D[1500-01-01])

    assert {:ok, %DateTime{year: 1500, month: 12, day: 22}} =
             270
             |> Astro.Solar.solar_ecliptic_longitude_after(after_moment)
             |> Astro.Time.date_time_from_moment()

    assert {:ok, %DateTime{year: 1499, month: 12, day: 21}} =
             270
             |> Astro.Solar.estimate_prior_solar_ecliptic_longitude(prior_moment)
             |> Astro.Time.date_time_from_moment()
  end

  test "the new moon searches succeed outside the ephemeris" do
    assert {:ok, %DateTime{}} = Astro.date_time_new_moon_before(@date)
    assert {:ok, %DateTime{}} = Astro.date_time_new_moon_at_or_after(@date)
  end
end
