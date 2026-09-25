defmodule Astro.LunarGeometryTest do
  use ExUnit.Case, async: true

  alias Astro.Lunar

  @degrees_per_radian 180 / :math.pi()
  @lunar_radius_m 1_737_400.0

  # Each expected value here is computed independently of the function under
  # test: from the JPL ephemeris, or from the defining formula.
  describe "lunar geometry" do
    test "lunar_altitude/2 matches the altitude from the JPL ephemeris" do
      for day <- 0..364//13,
          hour <- [0, 6, 12, 18],
          {lng, lat} <- [{151.2, -33.86}, {-0.13, 51.5}, {39.86, 21.39}] do
        date_time = DateTime.add(~U[2024-01-01 00:00:00Z], day * 86_400 + hour * 3600, :second)
        moment = Astro.Time.date_time_to_moment(date_time)

        {:ok, {right_ascension, declination, _distance}} =
          Astro.Ephemeris.moon_position(date_time)

        hour_angle = Astro.Time.mean_sidereal_from_moment(moment) + lng - right_ascension

        expected =
          :math.asin(
            :math.sin(lat / @degrees_per_radian) * :math.sin(declination / @degrees_per_radian) +
              :math.cos(lat / @degrees_per_radian) * :math.cos(declination / @degrees_per_radian) *
                :math.cos(hour_angle / @degrees_per_radian)
          ) * @degrees_per_radian

        location = %Geo.PointZ{coordinates: {lng, lat, 0.0}}
        assert_in_delta Lunar.lunar_altitude(moment, location), expected, 0.01
      end
    end

    test "angular_semi_diameter/1 and equatorial_horizontal_parallax/1 are the angles the Moon's and Earth's radii subtend" do
      for day <- 0..364//30 do
        moment =
          Astro.Time.date_time_to_moment(
            DateTime.add(~U[2024-01-01 00:00:00Z], day * 86_400, :second)
          )

        distance = Lunar.lunar_distance(moment)

        assert_in_delta Lunar.angular_semi_diameter(moment),
                        :math.asin(@lunar_radius_m / distance) * @degrees_per_radian,
                        1.0e-9

        assert_in_delta Lunar.equatorial_horizontal_parallax(moment),
                        :math.asin(Astro.Earth.earth_radius_m() / distance) * @degrees_per_radian,
                        1.0e-9
      end
    end

    test "lunar_node/1 is the Moon's argument of latitude reduced to ±90°" do
      for moment <- [Astro.Time.j2000(), 738_000.25, 700_000.0] do
        c = Astro.Time.julian_centuries_from_moment(moment)
        argument_of_latitude = Lunar.moon_node(c)

        expected =
          :math.fmod(:math.fmod(argument_of_latitude + 90.0, 180.0) + 180.0, 180.0) - 90.0

        assert_in_delta Lunar.lunar_node(moment), expected, 1.0e-9
      end
    end
  end

  describe "sidereal time" do
    # Meeus, Astronomical Algorithms, examples 12.a and 12.b.
    test "mean sidereal time matches Meeus's worked examples" do
      for {date_time, expected} <- [
            {~U[1987-04-10 00:00:00Z], 197.693195},
            {~U[1987-04-10 19:21:00Z], 128.7378734}
          ] do
        moment = Astro.Time.date_time_to_moment(date_time)
        assert_in_delta Astro.Time.mean_sidereal_from_moment(moment), expected, 1.0e-6
      end
    end

    test "apparent sidereal time matches Meeus's worked example" do
      moment = Astro.Time.date_time_to_moment(~U[1987-04-10 00:00:00Z])
      assert_in_delta Astro.Time.apparent_sidereal_from_moment(moment), 197.6922296, 1.0e-6
    end
  end

  describe "new crescent visibility" do
    # A crescent a few hours old, or an evening before conjunction, cannot be
    # seen by any method.
    for {name, location, date} <- [
          {"0.8 hours old at London", {-0.1275, 51.5072}, ~D[2025-07-24]},
          {"4.7 hours old at Cape Town", {18.4241, -33.9249}, ~D[2024-11-01]},
          {"before conjunction at London", {-0.1275, 51.5072}, ~D[2025-04-27]}
        ] do
      test "Schaefer does not see a crescent #{name}" do
        assert Astro.new_visible_crescent(
                 unquote(location),
                 unquote(Macro.escape(date)),
                 :schaefer
               ) ==
                 {:ok, :E}
      end
    end

    # A crescent a day and a half old, low in the evening sky of a low latitude,
    # is easily seen with the naked eye.
    for method <- [:odeh, :yallop] do
      test "a crescent 36 hours old at Mecca is visible to the naked eye (#{method})" do
        mecca = {39.8579, 21.3891}

        assert Astro.new_visible_crescent(mecca, ~D[2024-12-02], unquote(method)) == {:ok, :A}
        assert Astro.new_visible_crescent(mecca, ~D[2025-03-01], unquote(method)) == {:ok, :A}
      end
    end
  end
end
