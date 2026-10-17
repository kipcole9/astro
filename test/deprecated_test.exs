defmodule Astro.DeprecatedTest do
  use ExUnit.Case, async: true

  # `apply/3` calls the deprecated functions without compile-time
  # deprecation warnings.
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  defp call(module, name, julian_centuries), do: apply(module, name, [julian_centuries])

  describe "deprecated mean elements return their defining polynomials" do
    for {module, name, expected} <- [
          {Astro.Solar, :sun_geometric_mean_anomaly, 357.52911},
          {Astro.Solar, :earth_orbit_eccentricity, 0.016708634},
          {Astro.Solar, :sun_equation_of_center, -0.08430148943719645},
          {Astro.Solar, :mean_obliquity_of_ecliptic, 23.43929111111111},
          {Astro.Lunar, :mean_lunar_ecliptic_longitude, 218.3164477},
          {Astro.Lunar, :lunar_elongation, 297.8501921}
        ] do
      test "#{inspect(module)}.#{name}/1 at J2000" do
        assert_in_delta call(unquote(module), unquote(name), 0.0), unquote(expected), 1.0e-9
      end
    end
  end

  describe "deprecated positions agree with the JPL-based functions" do
    test "sun_apparent_longitude/1 is solar_ecliptic_longitude/1 at the same instant" do
      for julian_centuries <- [-0.5, 0.0, 0.19, 0.25] do
        moment = Astro.Time.moment_from_julian_centuries(julian_centuries)

        assert call(Astro.Solar, :sun_apparent_longitude, julian_centuries) ==
                 Astro.Solar.solar_ecliptic_longitude(moment)
      end
    end

    test "solar_declination/1 is the declination from solar_position/1" do
      moment = Astro.Time.moment_from_julian_centuries(0.19)
      {_right_ascension, declination, _distance} = Astro.Solar.solar_position(moment)

      assert call(Astro.Solar, :solar_declination, 0.19) == declination
    end

    # Meeus's low-precision series, which these functions used to evaluate,
    # is accurate to about 0.01°.
    test "sun_true_longitude/1 and obliquity_correction/1 stay within the old series' accuracy" do
      assert_in_delta call(Astro.Solar, :sun_true_longitude, 0.0), 280.38215851056276, 0.01
      assert_in_delta call(Astro.Solar, :obliquity_correction, 0.0), 23.437821291789415, 0.001
    end
  end
end
