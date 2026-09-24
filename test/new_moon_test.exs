defmodule Astro.Moon.NewMoon.Test do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "new moon searches" do
    property "bracket a moment between consecutive new moons" do
      check all(t <- StreamData.float(min: -700_000.0, max: 1_500_000.0), max_runs: 2_000) do
        before = Astro.Lunar.date_time_new_moon_before(t)
        at_or_after = Astro.Lunar.date_time_new_moon_at_or_after(t)

        assert before < t
        assert at_or_after >= t
        assert at_or_after - before > 29.0 and at_or_after - before < 30.0
      end
    end

    test "a new moon is its own new moon at or after, and the one before is the previous lunation" do
      for lunation <- [-24_000, -1, 0, 1, 24_724, 25_000, 30_000] do
        moment = Astro.Lunar.nth_new_moon(lunation)

        assert Astro.Lunar.date_time_new_moon_at_or_after(moment) === moment

        assert Astro.Lunar.date_time_new_moon_before(moment) ===
                 Astro.Lunar.nth_new_moon(lunation - 1)
      end
    end

    test "lunation 0 is the moment the searches estimate from" do
      # `@new_moon_zero` in `Astro.Lunar`.
      assert Astro.Lunar.nth_new_moon(0) === 376.46287205875086
    end
  end
end
