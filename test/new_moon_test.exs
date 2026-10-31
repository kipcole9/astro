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
        new_moon =
          Astro.Lunar.date_time_new_moon_at_or_after(Astro.Lunar.nth_new_moon(lunation) - 1.0)

        assert Astro.Lunar.date_time_new_moon_at_or_after(new_moon) === new_moon

        previous = Astro.Lunar.date_time_new_moon_before(new_moon)
        assert new_moon - previous > 29.2 and new_moon - previous < 29.9
        assert Astro.Lunar.date_time_new_moon_at_or_after(previous) === previous
      end
    end

    test "the date-time searches find new moons before AD 1" do
      assert {:ok, new_moon} = Astro.date_time_new_moon_before(~D[-0349-06-21])
      assert DateTime.truncate(new_moon, :second) == ~U[-0349-06-04 18:31:27Z]

      assert {:ok, next} = Astro.date_time_new_moon_at_or_after(~D[-0349-06-21])
      assert DateTime.diff(next, new_moon, :day) in 29..30
    end

    test "a date time and a date find the same new moon before them" do
      assert Astro.date_time_new_moon_before(~U[2021-08-23 00:00:00Z]) ==
               Astro.date_time_new_moon_before(~D[2021-08-23])

      # The date-time clause was once defined under this deprecated name.
      # `apply/3` calls it without a compile-time deprecation warning.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert apply(Astro, :date_time_new_moon_at_or_before, [~U[2021-08-23 00:00:00Z]]) ==
               Astro.date_time_new_moon_before(~U[2021-08-23 00:00:00Z])
    end

    test "lunation 0 is the moment the searches estimate from" do
      # `@new_moon_zero` in `Astro.Lunar`.
      assert Astro.Lunar.nth_new_moon(0) === 376.46287205875086
    end
  end
end
