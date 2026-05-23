defmodule Astro.Test.Time do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "julian day / calendar date round-trip" do
    property "date_time_from_julian_days/1 inverts julian_day_from_date/1 for proleptic-Gregorian dates" do
      # Julian days roughly spanning years 1 CE through 9999 CE — the full
      # range `Date.new/3` accepts under Calendar.ISO.
      check all(jd_int <- StreamData.integer(1_721_426..5_373_483), max_runs: 2_000) do
        jd = jd_int + 0.5

        {:ok, datetime} = Astro.Time.date_time_from_julian_days(jd)
        date = DateTime.to_date(datetime)
        assert Astro.Time.julian_day_from_date(date) == jd
      end
    end

    test "round-trips across the 1582-10-15 Gregorian reform boundary" do
      # 2_299_161 is the historical Julian-day cut-over; the function must
      # treat dates on either side of it as proleptic-Gregorian and round-trip.
      for jd_int <- 2_299_155..2_299_170 do
        jd = jd_int + 0.5
        {:ok, datetime} = Astro.Time.date_time_from_julian_days(jd)
        date = DateTime.to_date(datetime)
        assert Astro.Time.julian_day_from_date(date) == jd
      end
    end

    test "1582 vernal equinox is reported in proleptic-Gregorian dating" do
      # The astronomical event is at ~23:56 UTC on 1582-03-20 proleptic-Gregorian
      # (equivalent to 1582-03-10 in the historical Julian calendar — which is
      # what the old code mistakenly returned).
      {:ok, equinox} = Astro.equinox(1582, :march)
      assert equinox.year == 1582
      assert equinox.month == 3
      assert equinox.day == 20
    end

    test "successive March equinoxes around the reform boundary are ~365 days apart" do
      {:ok, e1581} = Astro.equinox(1581, :march)
      {:ok, e1582} = Astro.equinox(1582, :march)
      {:ok, e1583} = Astro.equinox(1583, :march)

      assert Date.diff(DateTime.to_date(e1582), DateTime.to_date(e1581)) in 364..366
      assert Date.diff(DateTime.to_date(e1583), DateTime.to_date(e1582)) in 364..366
    end
  end
end
