defmodule Astro.DeltaTTest do
  use ExUnit.Case, async: true

  alias Astro.Time

  # Morrison and Stephenson's (2004) values of ΔT and their standard
  # errors, as NASA publishes them at
  # https://eclipse.gsfc.nasa.gov/SEhelp/deltat2004.html. The Espenak and
  # Meeus polynomials are fitted to them.
  @historical [
    {-500, 17_190, 430},
    {-400, 15_530, 390},
    {-300, 14_080, 360},
    {-200, 12_790, 330},
    {-100, 11_640, 290},
    {0, 10_580, 260},
    {100, 9600, 240},
    {200, 8640, 210},
    {300, 7680, 180},
    {400, 6700, 160},
    {500, 5710, 140},
    {600, 4740, 120},
    {700, 3810, 100},
    {800, 2960, 80},
    {900, 2200, 70},
    {1000, 1570, 55},
    {1100, 1090, 40},
    {1200, 740, 30},
    {1300, 490, 20},
    {1400, 320, 20},
    {1500, 200, 20},
    {1600, 120, 20},
    {1700, 9, 5},
    {1750, 13, 2},
    {1800, 14, 1},
    {1850, 7, 1},
    {1900, -3, 1},
    {1950, 29, 0.1}
  ]

  # The years where one formula hands over to the next.
  @boundaries [-500, 500, 1600, 1700, 1800, 1860, 1900, 1920, 1941, 1961, 1972, 2025, 2150]

  defp long_term(year) do
    centuries = (year - 1820) / 100
    -20 + 32 * centuries * centuries
  end

  test "agrees with Morrison and Stephenson's historical values within their standard error" do
    for {year, delta_t, standard_error} <- @historical do
      assert_in_delta Time.delta_t(year * 1.0),
                      delta_t,
                      standard_error,
                      "#{year}: #{Time.delta_t(year * 1.0)} against #{delta_t} ± #{standard_error}"
    end
  end

  test "is continuous where one formula hands over to the next" do
    for year <- @boundaries do
      jump = Time.delta_t(year * 1.0) - Time.delta_t(year - 1.0e-6)
      assert abs(jump) < 0.3, "#{year}: a jump of #{jump} s"
    end
  end

  test "follows the long-term parabola before −500 and after 2150" do
    for year <- [-10_000, -2000, -501, 2150, 2500, 3000, 10_000] do
      assert_in_delta Time.delta_t(year * 1.0), long_term(year), 1.0e-6
    end
  end

  test "starts from the observed values after 2025" do
    assert_in_delta Time.delta_t(2025.0), 69.30, 1.0e-9

    # The Earth's rotation barely changed ΔT over 2020–2025, and the join
    # keeps it close for the next few years.
    assert_in_delta Time.delta_t(2030.0), 70.1, 0.1
    assert Time.delta_t(2050.0) < Time.delta_t(2100.0)
    assert Time.delta_t(2100.0) < long_term(2100)
  end

  test "keeps the IERS observed values for 1972 to 2025" do
    assert Time.delta_t(1972.0) == 42.23
    assert Time.delta_t(2000.0) == 63.83
    assert Time.delta_t(2025.0) == 69.30
  end
end
