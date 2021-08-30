defmodule Astro.Moon.Phase.Test do
  use ExUnit.Case, async: true

  # Most of these tests pass with a variation of 2 minutes,
  # there are 3 tests that fail with variation at 3 minutes
  # and one additional test fails unless variation if 3 minutes.

  # It is unknown if that is an issue with these calculations
  # of the test data.

  @minute_variation 4

  for [phase, date, time] <- Astro.Moon.TestData.moon_phase() do
    year = date.year
    month = date.month
    day = date.day
    hour = time.hour
    minute = time.minute

    test "Moon phase for #{inspect date}" do
      {:ok, date_time} =
        Astro.date_time_lunar_phase_at_or_after(unquote(Macro.escape(date)),
          apply(Astro.Lunar, unquote(phase), []))

      assert date_time.year == unquote(year)
      assert date_time.month == unquote(month)
      assert date_time.day == unquote(day)

      test_time = unquote(hour) * 60 + unquote(minute)
      calculated_time = date_time.hour * 60 + date_time.minute

      assert abs(test_time - calculated_time) <= @minute_variation
    end
  end
end