defmodule Astro.OutOfRangeTest do
  use ExUnit.Case, async: true

  # No ephemeris Astro loads, bundled or full, covers the year 1000.
  @date ~D[1000-06-01]
  @date_time ~U[1000-06-01 12:00:00Z]
  @sydney {151.20666584, -33.8559799094}

  for {name, call} <- [
        {"lunar_phase_at/1", quote(do: Astro.lunar_phase_at(@date))},
        {"illuminated_fraction_of_moon_at/1",
         quote(do: Astro.illuminated_fraction_of_moon_at(@date))},
        {"date_time_new_moon_nearest/1", quote(do: Astro.date_time_new_moon_nearest(@date))},
        {"date_time_lunar_phase_at_or_before/2",
         quote(do: Astro.date_time_lunar_phase_at_or_before(@date, 180.0))},
        {"date_time_lunar_phase_at_or_after/2",
         quote(do: Astro.date_time_lunar_phase_at_or_after(@date, 180.0))},
        {"sun_position_at/1", quote(do: Astro.sun_position_at(@date))},
        {"moon_position_at/1", quote(do: Astro.moon_position_at(@date_time))},
        {"sun_apparent_longitude/1", quote(do: Astro.sun_apparent_longitude(@date))},
        {"sun_azimuth_elevation/2", quote(do: Astro.sun_azimuth_elevation(@sydney, @date_time))},
        {"solar_noon/2", quote(do: Astro.solar_noon(@sydney, @date))}
      ] do
    test "#{name} returns {:error, :not_found} outside the ephemeris" do
      assert {:error, :not_found} = unquote(call)
    end
  end

  test "the new moon searches that do not use the ephemeris still succeed" do
    assert {:ok, %DateTime{}} = Astro.date_time_new_moon_before(@date)
    assert {:ok, %DateTime{}} = Astro.date_time_new_moon_at_or_after(@date)
  end
end
