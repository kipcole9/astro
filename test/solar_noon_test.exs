defmodule Astro.SolarNoonTest do
  use ExUnit.Case, async: true

  alias Astro.{Math, Solar, Time}

  @longitudes [-179.9, -122.4, -0.1, 0.0, 151.2, 179.9]

  # The Sun's local hour angle in degrees at a moment, from the same
  # apparent position solar noon uses: zero when it crosses the meridian.
  defp local_hour_angle(moment, longitude) do
    {right_ascension, _declination, _distance} = Solar.solar_position(moment)
    local_sidereal_time = Time.apparent_sidereal_from_moment(moment) + longitude

    Math.mod(local_sidereal_time - right_ascension + 180.0, 360.0) - 180.0
  end

  describe "Astro.solar_noon/2" do
    # 2.9.0 evaluated the equation of time twelve hours early, putting solar
    # noon up to 18 seconds from the meridian transit, most in December.
    test "is the moment the Sun's hour angle is zero, within a millisecond" do
      for year <- [1900, 1950, 2000, 2019, 2050, 2100],
          month <- 1..12,
          longitude <- @longitudes do
        date = Date.new!(year, month, 15)
        assert {:ok, noon} = Astro.solar_noon({longitude, 0.0}, date)

        hour_angle = local_hour_angle(Time.date_time_to_moment(noon), longitude)

        # 360° a day is 0.00417° a second, so 4.2e-6° is a millisecond.
        assert abs(hour_angle) < 4.2e-6, "#{date} at #{longitude}: #{hour_angle}°"
      end
    end

    test "is the meridian transit far from the present" do
      for year <- [-3000, -500, 1000, 3000, 6000], longitude <- [-122.4, 151.2] do
        {:ok, date} = Date.new(year, 12, 15)
        assert {:ok, noon} = Astro.solar_noon({longitude, 0.0}, date)

        hour_angle = local_hour_angle(Time.date_time_to_moment(noon), longitude)
        assert abs(hour_angle) < 4.2e-6, "#{year} at #{longitude}: #{hour_angle}°"
      end
    end

    test "falls on the requested UTC day, earlier in the day to the east" do
      date = ~D[2024-06-21]

      assert {:ok, east} = Astro.solar_noon({151.2, -33.9}, date)
      assert {:ok, west} = Astro.solar_noon({-122.4, 37.8}, date)

      assert DateTime.to_date(east) == date
      assert DateTime.to_date(west) == date
      assert east.hour == 1
      assert west.hour == 20
    end

    test "keeps sub-second precision" do
      assert {:ok, %DateTime{microsecond: {_microsecond, 6}}} =
               Astro.solar_noon({151.20666584, -33.8559799094}, ~D[2019-12-06])
    end
  end

  describe "Astro.Solar.equation_of_time/1" do
    # Solar noon is 12:00 local mean time less the equation of time. The
    # Meeus chapter 28 form agrees with the meridian transit to well under
    # a second near the present.
    test "accounts for the gap between mean noon and solar noon" do
      for year <- [1950, 2000, 2050], month <- 1..12, longitude <- @longitudes do
        date = Date.new!(year, month, 15)
        midnight = Time.date_time_to_moment(date)
        noon = Solar.solar_noon(midnight, longitude)

        equation_of_time =
          noon
          |> Time.julian_centuries_from_moment()
          |> Solar.equation_of_time()

        mean_noon = 720.0 - 4.0 * longitude
        minutes = (noon - midnight) * Time.minutes_per_day()

        assert_in_delta minutes, mean_noon - equation_of_time, 0.5 / 60.0
      end
    end
  end

  describe "Astro.Solar.solar_noon_utc/2" do
    test "takes west as negative, as documented" do
      julian_centuries =
        ~D[2024-06-21]
        |> Time.julian_day_from_date()
        |> Time.julian_centuries_from_julian_day()

      # Sydney's noon is near 02:00 UTC, San Francisco's near 20:00 UTC.
      assert_in_delta Solar.solar_noon_utc(julian_centuries, 151.2), 115.0, 10.0
      assert_in_delta Solar.solar_noon_utc(julian_centuries, -122.4), 1210.0, 10.0
    end
  end
end
