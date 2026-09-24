defmodule Astro.Test.Time do
  use ExUnit.Case, async: true
  use ExUnitProperties

  describe "moments before 0000-01-01" do
    property "convert to a date time that converts back to the moment" do
      check all(t <- StreamData.float(min: -800_000.0, max: 0.0), max_runs: 2_000) do
        assert {:ok, datetime} = Astro.Time.date_time_from_moment(t)
        assert abs(Astro.Time.date_time_to_moment(datetime) - t) < 1.0e-9
      end
    end

    test "keep the time of day of the day before 0000-01-01" do
      assert Astro.Time.date_time_from_moment(-0.25) == {:ok, ~U[-0001-12-31 18:00:00.000000Z]}
      assert Astro.Time.date_time_from_moment(-1.0) == {:ok, ~U[-0001-12-31 00:00:00.000000Z]}
    end
  end

  describe "hours_and_date_to_date_time/2" do
    test "an invalid date or a time of day of 24 hours or more is an error" do
      assert {:error, :invalid_time} =
               Astro.Time.hours_and_date_to_date_time(25.0, ~D[2024-06-21])

      assert {:error, :invalid_date} =
               Astro.Time.hours_and_date_to_date_time(12.0, %{year: 2024, month: 2, day: 30})
    end
  end

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

  describe "tz_world error mapping" do
    test "the bare POSIX :enoent becomes :tz_world_data_not_installed" do
      assert Astro.Time.map_tz_world_result({:error, :enoent}) ==
               {:error, :tz_world_data_not_installed}
    end

    test ":time_zone_not_found is a real result and is not reported as missing data" do
      assert Astro.Time.map_tz_world_result({:error, :time_zone_not_found}) ==
               {:error, :time_zone_not_found}
    end

    test "a resolved time zone passes through unchanged" do
      assert Astro.Time.map_tz_world_result({:ok, "Australia/Sydney"}) ==
               {:ok, "Australia/Sydney"}
    end

    test "other tz_world errors pass through unchanged" do
      for reason <- [:timeout, :empty_file, :corrupt_header, :connection_timeout] do
        assert Astro.Time.map_tz_world_result({:error, reason}) == {:error, reason}
      end
    end

    @tag :tz_world
    test "a real location resolves through the mapped path" do
      sydney = %Geo.Point{coordinates: {151.20666584, -33.8559799094}}
      assert {:ok, "Australia/Sydney"} = Astro.Time.tz_world_timezone_at(sydney)
    end
  end

  describe "ΔT conversions" do
    property "apply ΔT for the decimal year of the moment's calendar date" do
      first = Date.to_gregorian_days(~D[-9999-01-01])
      last = Date.to_gregorian_days(~D[9999-12-31])

      check all(
              day <- StreamData.integer(first..last),
              fraction <- StreamData.float(min: 0.0, max: 0.999),
              max_runs: 5_000
            ) do
        assert_delta_t_from_calendar(day + fraction)
      end
    end

    test "apply ΔT for the decimal year at year, mid-year and leap-day boundaries" do
      years = [
        -9999,
        -401,
        -400,
        -101,
        -100,
        -5,
        -4,
        -1,
        0,
        1,
        4,
        100,
        400,
        1582,
        1900,
        2000,
        2100,
        9999
      ]

      for year <- years, {month, day} <- [{1, 1}, {2, 28}, {3, 1}, {6, 30}, {7, 1}, {12, 31}] do
        {:ok, date} = Date.new(year, month, day)
        assert_delta_t_from_calendar(Date.to_gregorian_days(date))
      end
    end
  end

  # ΔT is looked up by decimal year: the year of the moment's calendar date,
  # offset from its 1 July. Built here from `Date`s as the independent oracle
  # for the day arithmetic in `Astro.Time`.
  defp assert_delta_t_from_calendar(t) do
    %{year: year} = Date.from_gregorian_days(floor(t))
    {:ok, july_first} = Date.new(year, 7, 1)
    decimal_year = year + (0.5 - (Date.to_gregorian_days(july_first) - floor(t)) / 365.25)
    delta = Astro.Time.delta_t(decimal_year) / Astro.Time.seconds_per_day()

    assert Astro.Time.dynamical_from_universal(t) === t + delta
    assert Astro.Time.universal_from_dynamical(t) === t - delta
  end
end
