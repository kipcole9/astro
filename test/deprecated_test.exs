defmodule Astro.DeprecatedTest do
  use ExUnit.Case, async: true

  # `apply/3` calls the deprecated functions without compile-time
  # deprecation warnings.
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  defp call(module, name, julian_centuries) do
    apply(module, name, [julian_centuries])
  end

  test "mean_obliquity_of_ecliptic/1 is the mean obliquity of Astro.Earth.nutation/1" do
    assert_in_delta call(Astro.Solar, :mean_obliquity_of_ecliptic, 0.0), 23.43929111111111, 1.0e-9
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
