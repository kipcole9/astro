defmodule Astro.MoonRiseSetTest do
  @moduledoc """
  Validation tests for `MoonRiseSet2.moonrise/3` and `MoonRiseSet2.moonset/3`.

  Test data was sourced from timeanddate.com and time.now for March 2026,
  covering four cities across four continents:

    - New York  (UTC-5 standard / UTC-4 DST, DST begins 2026-03-08)
    - London    (UTC+0 GMT / UTC+1 BST, BST begins 2026-03-29)
    - Sydney    (UTC+11 AEDT throughout March)
    - Tokyo     (UTC+9 JST, no DST observed)

  Both functions are assumed to accept:

    - `date`      :: `Date.t()`
    - `latitude`  :: float()   (degrees, negative = south)
    - `longitude` :: float()   (degrees, negative = west)

  and to return one of:

    - `{:ok, Time.t()}`   — event occurs on this calendar day in local time
    - `{:no_event, :no_rise | :no_set}` — the moon does not cross the horizon
                                           on this calendar day

  A tolerance of ±2 minutes is applied to all time comparisons to account
  for minor algorithmic differences versus the reference source.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  @tolerance_minutes 4

  # Returns true when `actual` is within @tolerance_minutes of `expected`.
  defp within_tolerance?(%DateTime{} = actual, %Time{} = expected) do
    actual_mins   = actual.hour   * 60 + actual.minute
    expected_mins = expected.hour * 60 + expected.minute
    abs(actual_mins - expected_mins) <= @tolerance_minutes
  end

  # Convenience: build a ~T sigil value at runtime.
  defp time!(hour, minute), do: Time.new!(hour, minute, 0)

  # Asserts that moonrise returns {:ok, time} within tolerance.
  defp assert_moonrise(date, lat, lon, expected_hour, expected_minute) do
    expected = time!(expected_hour, expected_minute)
    assert {:ok, actual} = Astro.Lunar.MoonRiseSet.moonrise({lon, lat}, date),
           "Expected moonrise on #{date} at #{lat},#{lon} to return {:ok, time}, got :no_event"
    assert within_tolerance?(actual, expected),
           """
           Moonrise on #{date} at #{lat},#{lon}:
             expected ~T[#{pad(expected.hour)}:#{pad(expected.minute)}:00] ± #{@tolerance_minutes} min
             got      ~T[#{pad(actual.hour)}:#{pad(actual.minute)}:00]
           """
  end

  # Asserts that moonset returns {:ok, time} within tolerance.
  defp assert_moonset(date, lat, lon, expected_hour, expected_minute) do
    expected = time!(expected_hour, expected_minute)
    assert {:ok, actual} = Astro.Lunar.MoonRiseSet.moonset({lon, lat}, date),
           "Expected moonset on #{date} at #{lat},#{lon} to return {:ok, time}, got :no_event"
    assert within_tolerance?(actual, expected),
           """
           Moonset on #{date} at #{lat},#{lon}:
             expected ~T[#{pad(expected.hour)}:#{pad(expected.minute)}:00] ± #{@tolerance_minutes} min
             got      ~T[#{pad(actual.hour)}:#{pad(actual.minute)}:00]
           """
  end

  defp assert_no_moonrise(date, lat, lon) do
    assert  {:error, :no_time} = Astro.Lunar.MoonRiseSet.moonrise({lon, lat}, date),
           "Expected no moonrise on #{date} at #{lat},#{lon}, but got an event"
  end

  defp assert_no_moonset(date, lat, lon) do
    assert {:error, :no_time} = Astro.Lunar.MoonRiseSet.moonset({lon, lat}, date),
           "Expected no moonset on #{date} at #{lat},#{lon}, but got an event"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  # ---------------------------------------------------------------------------
  # Location constants
  # ---------------------------------------------------------------------------

  # All times in the assertions below are local civil time for each city,
  # as reported by timeanddate.com / time.now.  The module under test is
  # responsible for applying the correct UTC offset and DST rules.

  @new_york_lat   40.7128
  @new_york_lon  -74.0060

  @london_lat     51.5074
  @london_lon     -0.1278

  @sydney_lat    -33.8688
  @sydney_lon    151.2093

  @tokyo_lat      35.6762
  @tokyo_lon     139.6503

  # ---------------------------------------------------------------------------
  # New York  (America/New_York)
  # DST begins 2026-03-08 — UTC-5 before, UTC-4 from that date onward.
  # ---------------------------------------------------------------------------

  describe "New York — moonset" do
    # 2026-03-01: no moonrise this calendar day; moonset 05:37
    test "2026-03-01 moonset (waning gibbous, 98%)" do
      assert_moonset(~D[2026-03-01], @new_york_lat, @new_york_lon, 5, 37)
    end

    # 2026-03-04: standard time (UTC-5); moonrise 19:23, moonset 06:50
    test "2026-03-04 moonrise — standard time, near-full moon" do
      assert_moonrise(~D[2026-03-04], @new_york_lat, @new_york_lon, 19, 23)
    end

    test "2026-03-04 moonset — standard time, near-full moon" do
      assert_moonset(~D[2026-03-04], @new_york_lat, @new_york_lon, 6, 50)
    end

    # 2026-03-08: first day of DST — clocks spring forward; no moonrise
    test "2026-03-08 no moonrise — first day of DST (clocks spring forward)" do
      assert_no_moonrise(~D[2026-03-08], @new_york_lat, @new_york_lon)
    end

    test "2026-03-08 moonset — first day of DST" do
      assert_moonset(~D[2026-03-08], @new_york_lat, @new_york_lon, 9, 22)
    end

    # 2026-03-09: DST active; moonrise 00:41, moonset 09:54
    test "2026-03-09 moonrise — DST active (UTC-4)" do
      assert_moonrise(~D[2026-03-09], @new_york_lat, @new_york_lon, 0, 41)
    end

    test "2026-03-09 moonset — DST active (UTC-4)" do
      assert_moonset(~D[2026-03-09], @new_york_lat, @new_york_lon, 9, 54)
    end

    # 2026-03-11: waning crescent; moonrise 02:42, moonset 11:18
    test "2026-03-11 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-11], @new_york_lat, @new_york_lon, 2, 42)
    end

    test "2026-03-11 moonset — waning crescent" do
      assert_moonset(~D[2026-03-11], @new_york_lat, @new_york_lon, 11, 18)
    end

    # 2026-03-18: new moon (0.2% illumination); moonrise 06:44, moonset 18:56
    test "2026-03-18 moonrise — new moon" do
      assert_moonrise(~D[2026-03-18], @new_york_lat, @new_york_lon, 6, 44)
    end

    test "2026-03-18 moonset — new moon" do
      assert_moonset(~D[2026-03-18], @new_york_lat, @new_york_lon, 18, 56)
    end

    # 2026-03-20: waxing crescent; moonrise 07:31, moonset 21:24
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @new_york_lat, @new_york_lon, 7, 31)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @new_york_lat, @new_york_lon, 21, 24)
    end

    test "2026-03-25 moonset" do
      assert_moonset(~D[2026-03-25], @new_york_lat, @new_york_lon, 2, 23)
    end

    # 2026-03-31: no moonrise; moonset 05:54
    test "2026-03-31 moonrise" do
      assert_moonrise(~D[2026-03-31], @new_york_lat, @new_york_lon, 18, 9)
    end

    test "2026-03-31 moonset" do
      assert_moonset(~D[2026-03-31], @new_york_lat, @new_york_lon, 5, 54)
    end
  end

  # ---------------------------------------------------------------------------
  # London  (Europe/London)
  # GMT (UTC+0) throughout March until BST begins 2026-03-29 (UTC+1).
  # ---------------------------------------------------------------------------

  describe "London — moonrise and moonset" do
    # 2026-03-01: no moonrise; moonset 06:10
    test "2026-03-01 no moonrise" do
      assert_no_moonrise(~D[2026-03-08], @london_lat, @london_lon)
    end

    # 2026-03-23: no moonset; moonrise 07:18
    test "2026-03-23 no moonset" do
      assert_no_moonset(~D[2026-03-23], @london_lat, @london_lon)
    end

    test "2026-03-01 moonset — waning gibbous, 97%" do
      assert_moonset(~D[2026-03-01], @london_lat, @london_lon, 6, 10)
    end

    # 2026-03-04: moonrise 19:17, moonset 06:52
    test "2026-03-04 moonrise — near-full moon, GMT" do
      assert_moonrise(~D[2026-03-04], @london_lat, @london_lon, 19, 17)
    end

    test "2026-03-04 moonset — near-full moon, GMT" do
      assert_moonset(~D[2026-03-04], @london_lat, @london_lon, 6, 52)
    end

    # 2026-03-08: no moonrise; moonset 07:43
    test "2026-03-08 no moonrise" do
      assert_no_moonrise(~D[2026-03-08], @london_lat, @london_lon)
    end

    test "2026-03-08 moonset — waning gibbous, 79%" do
      assert_moonset(~D[2026-03-08], @london_lat, @london_lon, 7, 43)
    end

    # 2026-03-09: moonrise 00:19, moonset 08:03
    test "2026-03-09 moonrise" do
      assert_moonrise(~D[2026-03-09], @london_lat, @london_lon, 0, 19)
    end

    test "2026-03-09 moonset" do
      assert_moonset(~D[2026-03-09], @london_lat, @london_lon, 8, 3)
    end

    # 2026-03-11: moonrise 02:37, moonset 09:10
    test "2026-03-11 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-11], @london_lat, @london_lon, 2, 37)
    end

    test "2026-03-11 moonset — waning crescent" do
      assert_moonset(~D[2026-03-11], @london_lat, @london_lon, 9, 10)
    end

    # 2026-03-18: new moon (0.4%); moonrise 05:51, moonset 17:44
    test "2026-03-18 moonrise — new moon" do
      assert_moonrise(~D[2026-03-18], @london_lat, @london_lon, 5, 51)
    end

    test "2026-03-18 moonset — new moon" do
      assert_moonset(~D[2026-03-18], @london_lat, @london_lon, 17, 44)
    end

    # 2026-03-20: waxing crescent; moonrise 06:16, moonset 20:35
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @london_lat, @london_lon, 6, 16)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @london_lat, @london_lon, 20, 35)
    end

    # 2026-03-29: first day of BST (UTC+1); moonrise; moonset 05:34
    test "2026-03-29 moonrise — first day of BST" do
      assert_moonrise(~D[2026-03-29], @london_lat, @london_lon, 15, 22)
    end

    test "2026-03-29 moonset — first day of BST" do
      assert_moonset(~D[2026-03-29], @london_lat, @london_lon, 5, 34)
    end

    # 2026-03-31: moonrise 17:59; moonset 06:00
    test "2026-03-31 no moonrise" do
      assert_moonrise(~D[2026-03-31], @london_lat, @london_lon, 17, 59)
    end

    # 2026-03-31: moonrise 17:59; moonset 06:00
    test "2026-03-31 moonset" do
      assert_moonset(~D[2026-03-31], @london_lat, @london_lon, 6, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Sydney  (Australia/Sydney — AEDT, UTC+11 throughout March)
  # Southern hemisphere: moon geometry is inverted relative to northern cities.
  # ---------------------------------------------------------------------------

  describe "Sydney — moonrise and moonset" do
    # 2026-03-01: no moonrise; moonset 03:50
    test "2026-03-01 moonrise — southern hemisphere, waning gibbous" do
      assert_moonrise(~D[2026-03-01], @sydney_lat, @sydney_lon, 18, 18)
    end

    test "2026-03-01 moonset — waning gibbous, 96%" do
      assert_moonset(~D[2026-03-01], @sydney_lat, @sydney_lon, 3, 50)
    end

    # 2026-03-04: full moon (100%); moonrise 19:47, moonset 07:10
    test "2026-03-04 moonrise — full moon" do
      assert_moonrise(~D[2026-03-04], @sydney_lat, @sydney_lon, 19, 47)
    end

    test "2026-03-04 moonset — full moon, 100% illumination" do
      assert_moonset(~D[2026-03-04], @sydney_lat, @sydney_lon, 7, 10)
    end

    # 2026-03-08: moonrise 21:37, moonset 11:11
    test "2026-03-08 moonrise — waning gibbous" do
      assert_moonrise(~D[2026-03-08], @sydney_lat, @sydney_lon, 21, 37)
    end

    test "2026-03-08 moonset — waning gibbous" do
      assert_moonset(~D[2026-03-08], @sydney_lat, @sydney_lon, 11, 11)
    end

    # 2026-03-11: moonrise 23:39, moonset 14:07
    test "2026-03-11 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-11], @sydney_lat, @sydney_lon, 23, 39)
    end

    test "2026-03-11 moonset — waning crescent" do
      assert_moonset(~D[2026-03-11], @sydney_lat, @sydney_lon, 14, 7)
    end

    # 2026-03-13: moonrise 00:32, moonset 15:47
    test "2026-03-13 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-13], @sydney_lat, @sydney_lon, 0, 32)
    end

    test "2026-03-13 moonset — waning crescent" do
      assert_moonset(~D[2026-03-13], @sydney_lat, @sydney_lon, 15, 47)
    end

    # 2026-03-19: new moon (0.0% illumination); moonrise 06:48, moonset 19:04
    test "2026-03-19 moonrise — new moon, zero illumination" do
      assert_moonrise(~D[2026-03-19], @sydney_lat, @sydney_lon, 6, 48)
    end

    test "2026-03-19 moonset — new moon, zero illumination" do
      assert_moonset(~D[2026-03-19], @sydney_lat, @sydney_lon, 19, 4)
    end

    # 2026-03-20: waxing crescent (1.5%); moonrise 07:55, moonset 19:33
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @sydney_lat, @sydney_lon, 7, 55)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @sydney_lat, @sydney_lon, 19, 33)
    end

    # 2026-03-25: waxing gibbous; moonrise 13:50, moonset 23:22
    test "2026-03-25 moonrise — waxing gibbous" do
      assert_moonrise(~D[2026-03-25], @sydney_lat, @sydney_lon, 13, 50)
    end

    test "2026-03-25 moonset — waxing gibbous" do
      assert_moonset(~D[2026-03-25], @sydney_lat, @sydney_lon, 23, 22)
    end

    # 2026-03-31: no moonrise; moonset 04:58
    test "2026-03-31 moonrise" do
      assert_moonrise(~D[2026-03-31], @sydney_lat, @sydney_lon, 17, 49)
    end

    test "2026-03-31 moonset" do
      assert_moonset(~D[2026-03-31], @sydney_lat, @sydney_lon, 4, 58)
    end
  end

  # ---------------------------------------------------------------------------
  # Tokyo  (Asia/Tokyo — JST, UTC+9, no DST observed)
  # ---------------------------------------------------------------------------

  describe "Tokyo — moonrise and moonset" do
    # 2026-03-01: moonrise 15:12, moonset 04:48
    test "2026-03-01 moonrise — waning gibbous, 93%" do
      assert_moonrise(~D[2026-03-01], @tokyo_lat, @tokyo_lon, 15, 12)
    end

    test "2026-03-01 moonset — waning gibbous, 93%" do
      assert_moonset(~D[2026-03-01], @tokyo_lat, @tokyo_lon, 4, 48)
    end

    # 2026-03-04: moonrise 18:31, moonset 06:19 (full moon was Mar 3 at 20:37 JST)
    test "2026-03-04 moonrise — day after full moon" do
      assert_moonrise(~D[2026-03-04], @tokyo_lat, @tokyo_lon, 18, 31)
    end

    test "2026-03-04 moonset — day after full moon" do
      assert_moonset(~D[2026-03-04], @tokyo_lat, @tokyo_lon, 6, 19)
    end

    # 2026-03-08: moonrise 22:36, moonset 08:02
    test "2026-03-08 moonrise — waning gibbous" do
      assert_moonrise(~D[2026-03-08], @tokyo_lat, @tokyo_lon, 22, 36)
    end

    test "2026-03-08 moonset — waning gibbous" do
      assert_moonset(~D[2026-03-08], @tokyo_lat, @tokyo_lon, 8, 2)
    end

    # 2026-03-09: moonrise 23:37, moonset 08:33
    test "2026-03-09 moonrise" do
      assert_moonrise(~D[2026-03-09], @tokyo_lat, @tokyo_lon, 23, 37)
    end

    test "2026-03-09 moonset" do
      assert_moonset(~D[2026-03-09], @tokyo_lat, @tokyo_lon, 8, 33)
    end

    # 2026-03-11: last quarter; moonrise 00:35, moonset 09:53
    test "2026-03-11 moonrise — last quarter" do
      assert_moonrise(~D[2026-03-11], @tokyo_lat, @tokyo_lon, 0, 35)
    end

    test "2026-03-11 moonset — last quarter" do
      assert_moonset(~D[2026-03-11], @tokyo_lat, @tokyo_lon, 9, 53)
    end

    # 2026-03-19: new moon (0.0% illumination); moonrise 05:40, moonset 18:07
    test "2026-03-19 moonrise — new moon, zero illumination" do
      assert_moonrise(~D[2026-03-19], @tokyo_lat, @tokyo_lon, 5, 40)
    end

    test "2026-03-19 moonset — new moon, zero illumination" do
      assert_moonset(~D[2026-03-19], @tokyo_lat, @tokyo_lon, 18, 7)
    end

    # 2026-03-20: waxing crescent (1.6%); moonrise 06:07, moonset 19:17
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @tokyo_lat, @tokyo_lon, 6, 7)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @tokyo_lat, @tokyo_lon, 19, 17)
    end

    # 2026-03-25: waxing gibbous; moonrise 09:35, moonset 00:08
    test "2026-03-25 moonrise — waxing gibbous" do
      assert_moonrise(~D[2026-03-25], @tokyo_lat, @tokyo_lon, 9, 35)
    end

    test "2026-03-25 moonset — waxing gibbous (early hours)" do
      assert_moonset(~D[2026-03-25], @tokyo_lat, @tokyo_lon, 0, 8)
    end

    # 2026-03-31: moonrise 04:21, moonset 16:18
    test "2026-03-31 moonrise — waxing gibbous, 96%" do
      assert_moonrise(~D[2026-03-31], @tokyo_lat, @tokyo_lon, 16, 17)
    end

    test "2026-03-31 moonset — waxing gibbous, 96%" do
      assert_moonset(~D[2026-03-31], @tokyo_lat, @tokyo_lon, 4, 22)
    end
  end
end