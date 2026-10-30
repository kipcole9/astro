defmodule Astro.CoordinatesTest do
  use ExUnit.Case, async: true

  # The Sun's ecliptic latitude never exceeds about 1.2″ (Meeus,
  # Astronomical Algorithms, chapter 25). An error in the precession tilts
  # the ecliptic of date, which shows as an annual latitude that grows
  # with the time from J2000: with the epoch-dependent coefficients of
  # Meeus 21.2 taken for the t² terms it reached 2.4″ by 1900 and 2100.
  @maximum_solar_latitude 1.2 / 3600.0

  describe "precession and nutation keep the Sun on the ecliptic of date" do
    for year <- [1901, 1925, 1950, 1975, 2000, 2025, 2050, 2075, 2099] do
      test "in #{year}" do
        for day <- 0..364//3 do
          dynamical_time =
            unquote(year)
            |> Date.new!(1, 1)
            |> Date.add(day)
            |> Astro.Time.date_time_to_moment()
            |> Astro.Time.dynamical_time_from_moment()

          {:ok, {_longitude, latitude, _distance}} =
            Astro.Ephemeris.sun_ecliptic_position_dt(dynamical_time)

          assert abs(latitude) < @maximum_solar_latitude
        end
      end
    end
  end
end
