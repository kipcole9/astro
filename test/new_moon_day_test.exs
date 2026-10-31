defmodule Astro.NewMoonDayTest do
  use ExUnit.Case, async: true

  alias Astro.{Lunar, Time}

  @beijing_switch Date.to_gregorian_days(~D[1929-01-01])

  # Beijing local mean time before 1929 and UTC+8 after, as the Chinese
  # calendar keeps it.
  defp beijing(moment) do
    if moment < @beijing_switch do
      1397 / 180 / 24
    else
      8 / 24
    end
  end

  defp offset_at(offset, moment) when is_function(offset, 1), do: offset.(moment)
  defp offset_at(offset, _moment), do: offset

  # The local day of the moment search's new moon, as a calendar reckons it:
  # the search from local midnight, the date at the offset in force then.
  defp moment_search_day(search, day, offset) do
    new_moon = search.(day - offset_at(offset, day))
    floor(new_moon + offset_at(offset, new_moon))
  end

  defp day(date), do: Date.to_gregorian_days(date)

  describe "new_moon_day_before/2 and new_moon_day_on_or_after/2" do
    test "are the local days of the moment searches' new moons" do
      offsets = [0.0, 8 / 24, -8 / 24, 5.5 / 24, &beijing/1]

      days =
        for i <- 0..399 do
          day(~D[2000-01-01]) + round((i - 200) * 30_000 * 365.2425 / 200) + rem(i * 7, 31)
        end ++ Enum.to_list(day(~D[1925-01-01])..day(~D[1933-01-01])//3)

      for offset <- offsets, day <- days do
        assert Lunar.new_moon_day_before(day, offset) ==
                 moment_search_day(&Lunar.date_time_new_moon_before/1, day, offset)

        assert Lunar.new_moon_day_on_or_after(day, offset) ==
                 moment_search_day(&Lunar.date_time_new_moon_at_or_after/1, day, offset)
      end
    end

    # These new moons are within 15 seconds of midnight in UTC+8, where one
    # phase cannot decide the day and the new moon is refined.
    test "decide new moons within seconds of local midnight" do
      assert Lunar.new_moon_day_on_or_after(day(~D[2057-09-20]), 8 / 24) == day(~D[2057-09-29])
      assert Lunar.new_moon_day_before(day(~D[2057-09-29]), 8 / 24) == day(~D[2057-08-30])
      assert Lunar.new_moon_day_before(day(~D[2057-09-30]), 8 / 24) == day(~D[2057-09-29])

      assert Lunar.new_moon_day_on_or_after(day(~D[2097-08-01]), 8 / 24) == day(~D[2097-08-07])
      assert Lunar.new_moon_day_before(day(~D[2097-08-08]), 8 / 24) == day(~D[2097-08-07])
    end

    test "a new moon on the day itself is on or after it, not before it" do
      new_moon_day = Lunar.new_moon_day_on_or_after(day(~D[2024-06-01]), 8 / 24)

      assert Lunar.new_moon_day_on_or_after(new_moon_day, 8 / 24) == new_moon_day
      assert Lunar.new_moon_day_before(new_moon_day, 8 / 24) < new_moon_day
      assert Lunar.new_moon_day_before(new_moon_day + 1, 8 / 24) == new_moon_day
    end

    test "consecutive new moons are 29 or 30 days apart" do
      first = Lunar.new_moon_day_on_or_after(day(~D[2024-01-01]), 8 / 24)

      Enum.reduce(1..24, first, fn _month, previous ->
        next = Lunar.new_moon_day_on_or_after(previous + 1, 8 / 24)
        assert (next - previous) in 29..30
        next
      end)
    end

    test "raise beyond 50,000 years of J2000, as the moment searches do" do
      far = floor(Time.j2000() + 50_001 * 365.2425)

      assert_raise ArgumentError, fn -> Lunar.new_moon_day_before(far, 0.0) end
      assert_raise ArgumentError, fn -> Lunar.new_moon_day_on_or_after(-far, 0.0) end
    end
  end
end
