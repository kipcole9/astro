defmodule Astro.MoonRiseSetTest do
  @moduledoc """
  Validation tests for `MoonRiseSet2.moonrise/3` and `MoonRiseSet2.moonset/3`.

  All test data is sourced from the USNO Astronomical Applications Department
  API (aa.usno.navy.mil, body=1 Moon, DE430-based, queried 2026-03-11),
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
    - `{:error, :no_time}` — the moon does not cross the horizon on this day

  A tolerance of ±2 or ±3 minutes is applied to all time comparisons.
  The wider ±3 window arises from the combination of USNO's nearest-minute
  rounding (DE430) with the Moon's shallow horizon-crossing angle —
  especially at higher latitudes where the diurnal arc is most oblique.
  A ±4 minute tolerance is used for a handful of London moonrise events where
  the Moon's oblique diurnal arc at 51.5 °N produces the widest model spread.
  """

  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------------------

  @two_minutes_tolerance 2
  @three_minutes_tolerance 3
  @four_minutes_tolerance 4

  defp within_tolerance?(%DateTime{} = actual, %Time{} = expected, tolerance) do
    actual_mins = actual.hour * 60 + actual.minute
    expected_mins = expected.hour * 60 + expected.minute
    abs(actual_mins - expected_mins) <= tolerance
  end

  defp time!(hour, minute), do: Time.new!(hour, minute, 0)

  defp assert_moonrise(
         date,
         lat,
         lon,
         expected_hour,
         expected_minute,
         tolerance \\ @two_minutes_tolerance
       ) do
    expected = time!(expected_hour, expected_minute)

    assert {:ok, actual} = Astro.Lunar.MoonRiseSet.moonrise({lon, lat}, date),
           "Expected moonrise on #{date} at #{lat},#{lon} to return {:ok, time}, got :no_event"

    assert within_tolerance?(actual, expected, tolerance),
           """
           Moonrise on #{date} at #{lat},#{lon}:
             expected ~T[#{pad(expected.hour)}:#{pad(expected.minute)}:00] ± #{tolerance} min
             got      ~T[#{pad(actual.hour)}:#{pad(actual.minute)}:00]
           """
  end

  defp assert_moonset(
         date,
         lat,
         lon,
         expected_hour,
         expected_minute,
         tolerance \\ @two_minutes_tolerance
       ) do
    expected = time!(expected_hour, expected_minute)

    assert {:ok, actual} = Astro.Lunar.MoonRiseSet.moonset({lon, lat}, date),
           "Expected moonset on #{date} at #{lat},#{lon} to return {:ok, time}, got :no_event"

    assert within_tolerance?(actual, expected, tolerance),
           """
           Moonset on #{date} at #{lat},#{lon}:
             expected ~T[#{pad(expected.hour)}:#{pad(expected.minute)}:00] ± #{tolerance} min
             got      ~T[#{pad(actual.hour)}:#{pad(actual.minute)}:00]
           """
  end

  defp assert_no_moonrise(date, lat, lon) do
    assert {:error, :no_time} = Astro.Lunar.MoonRiseSet.moonrise({lon, lat}, date),
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

  # All times are local civil time as reported by the USNO API.
  # The module under test is responsible for applying the correct UTC offset
  # and DST rules.

  @new_york_lat 40.7128
  @new_york_lon -74.0060

  @london_lat 51.5074
  @london_lon -0.1278

  @sydney_lat -33.8688
  @sydney_lon 151.2093

  @tokyo_lat 35.6762
  @tokyo_lon 139.6503

  # ---------------------------------------------------------------------------
  # New York  (America/New_York — UTC-5 before 2026-03-08, UTC-4 from 2026-03-08)
  # ---------------------------------------------------------------------------

  describe "New York — moonrise and moonset" do
    # 2026-03-01: no moonrise; USNO moonset 05:38
    test "2026-03-01 moonset — waning gibbous, 98%" do
      assert_moonset(~D[2026-03-01], @new_york_lat, @new_york_lon, 5, 38)
    end

    # 2026-03-04: standard time (UTC-5); USNO moonrise 19:24, moonset 06:50
    test "2026-03-04 moonrise — standard time, near-full moon" do
      assert_moonrise(~D[2026-03-04], @new_york_lat, @new_york_lon, 19, 24, @three_minutes_tolerance)
    end

    test "2026-03-04 moonset — standard time, near-full moon" do
      assert_moonset(~D[2026-03-04], @new_york_lat, @new_york_lon, 6, 50)
    end

    # 2026-03-08: first day of DST — clocks spring forward; no moonrise; USNO moonset 09:23
    test "2026-03-08 no moonrise — first day of DST (clocks spring forward)" do
      assert_no_moonrise(~D[2026-03-08], @new_york_lat, @new_york_lon)
    end

    test "2026-03-08 moonset — first day of DST" do
      assert_moonset(~D[2026-03-08], @new_york_lat, @new_york_lon, 9, 23)
    end

    # 2026-03-09: DST active (UTC-4); USNO moonrise 00:42, moonset 09:54
    test "2026-03-09 moonrise — DST active (UTC-4)" do
      assert_moonrise(~D[2026-03-09], @new_york_lat, @new_york_lon, 0, 42, @three_minutes_tolerance)
    end

    test "2026-03-09 moonset — DST active (UTC-4)" do
      assert_moonset(~D[2026-03-09], @new_york_lat, @new_york_lon, 9, 54)
    end

    # 2026-03-11: waning crescent; USNO moonrise 02:43, moonset 11:19
    test "2026-03-11 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-11], @new_york_lat, @new_york_lon, 2, 43, @three_minutes_tolerance)
    end

    test "2026-03-11 moonset — waning crescent" do
      assert_moonset(~D[2026-03-11], @new_york_lat, @new_york_lon, 11, 19, @three_minutes_tolerance)
    end

    # 2026-03-18: new moon; USNO moonrise 06:45, moonset 18:57
    test "2026-03-18 moonrise — new moon" do
      assert_moonrise(~D[2026-03-18], @new_york_lat, @new_york_lon, 6, 45)
    end

    test "2026-03-18 moonset — new moon" do
      assert_moonset(~D[2026-03-18], @new_york_lat, @new_york_lon, 18, 57, @three_minutes_tolerance)
    end

    # 2026-03-20: waxing crescent; USNO moonrise 07:32, moonset 21:24
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @new_york_lat, @new_york_lon, 7, 32)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @new_york_lat, @new_york_lon, 21, 24, @three_minutes_tolerance)
    end

    # 2026-03-25: USNO moonset 02:24
    test "2026-03-25 moonset — waxing gibbous" do
      assert_moonset(~D[2026-03-25], @new_york_lat, @new_york_lon, 2, 24, @three_minutes_tolerance)
    end

    # 2026-03-31: USNO moonrise 18:09, moonset 05:54
    test "2026-03-31 moonrise — waxing gibbous, 96%" do
      assert_moonrise(~D[2026-03-31], @new_york_lat, @new_york_lon, 18, 9, @three_minutes_tolerance)
    end

    test "2026-03-31 moonset — waxing gibbous, 96%" do
      assert_moonset(~D[2026-03-31], @new_york_lat, @new_york_lon, 5, 54)
    end
  end

  # ---------------------------------------------------------------------------
  # London  (Europe/London — UTC+0 GMT until 2026-03-29, UTC+1 BST from 2026-03-29)
  # Several moonrise events need ±4 min: the Moon's oblique diurnal arc at 51.5 °N
  # amplifies the DE440s-vs-DE430 residual on dates of high lunar declination.
  # ---------------------------------------------------------------------------

  describe "London — moonrise and moonset" do
    # 2026-03-01: USNO moonset 06:11
    test "2026-03-01 moonset — waning gibbous, 97%" do
      assert_moonset(~D[2026-03-01], @london_lat, @london_lon, 6, 11)
    end

    # 2026-03-04: USNO moonrise 19:18, moonset 06:52
    test "2026-03-04 moonrise — near-full moon, GMT" do
      assert_moonrise(~D[2026-03-04], @london_lat, @london_lon, 19, 18, @four_minutes_tolerance)
    end

    test "2026-03-04 moonset — near-full moon, GMT" do
      assert_moonset(~D[2026-03-04], @london_lat, @london_lon, 6, 52)
    end

    # 2026-03-08: no moonrise; USNO moonset 07:43
    test "2026-03-08 no moonrise — waning gibbous" do
      assert_no_moonrise(~D[2026-03-08], @london_lat, @london_lon)
    end

    test "2026-03-08 moonset — waning gibbous, 79%" do
      assert_moonset(~D[2026-03-08], @london_lat, @london_lon, 7, 43)
    end

    # 2026-03-09: USNO moonrise 00:20, moonset 08:04
    test "2026-03-09 moonrise" do
      assert_moonrise(~D[2026-03-09], @london_lat, @london_lon, 0, 20, @four_minutes_tolerance)
    end

    test "2026-03-09 moonset" do
      assert_moonset(~D[2026-03-09], @london_lat, @london_lon, 8, 4)
    end

    # 2026-03-11: USNO moonrise 02:37, moonset 09:11
    test "2026-03-11 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-11], @london_lat, @london_lon, 2, 37, @three_minutes_tolerance)
    end

    test "2026-03-11 moonset — waning crescent" do
      assert_moonset(~D[2026-03-11], @london_lat, @london_lon, 9, 11)
    end

    # 2026-03-18: new moon; USNO moonrise 05:52, moonset 17:45
    test "2026-03-18 moonrise — new moon" do
      assert_moonrise(~D[2026-03-18], @london_lat, @london_lon, 5, 52)
    end

    test "2026-03-18 moonset — new moon" do
      assert_moonset(~D[2026-03-18], @london_lat, @london_lon, 17, 45, @four_minutes_tolerance)
    end

    # 2026-03-20: waxing crescent; USNO moonrise 06:17, moonset 20:35
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @london_lat, @london_lon, 6, 17)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @london_lat, @london_lon, 20, 35, @three_minutes_tolerance)
    end

    # 2026-03-23: no moonset
    test "2026-03-23 no moonset — waxing gibbous" do
      assert_no_moonset(~D[2026-03-23], @london_lat, @london_lon)
    end

    # 2026-03-29: first day of BST; USNO moonrise 15:22, moonset 05:34
    test "2026-03-29 moonrise — first day of BST" do
      assert_moonrise(~D[2026-03-29], @london_lat, @london_lon, 15, 22, @four_minutes_tolerance)
    end

    test "2026-03-29 moonset — first day of BST" do
      assert_moonset(~D[2026-03-29], @london_lat, @london_lon, 5, 34)
    end

    # 2026-03-31: USNO moonrise 17:59, moonset 06:00
    test "2026-03-31 moonrise — waxing gibbous, 97%" do
      assert_moonrise(~D[2026-03-31], @london_lat, @london_lon, 17, 59, @three_minutes_tolerance)
    end

    test "2026-03-31 moonset — waxing gibbous, 97%" do
      assert_moonset(~D[2026-03-31], @london_lat, @london_lon, 6, 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Sydney  (Australia/Sydney — AEDT, UTC+11 throughout March)
  # Southern hemisphere: moon geometry is inverted relative to northern cities.
  # ---------------------------------------------------------------------------

  describe "Sydney — moonrise and moonset" do
    # 2026-03-01: USNO moonrise 18:19, moonset 03:50
    test "2026-03-01 moonrise — waning gibbous, 96%" do
      assert_moonrise(~D[2026-03-01], @sydney_lat, @sydney_lon, 18, 19)
    end

    test "2026-03-01 moonset — waning gibbous, 96%" do
      assert_moonset(~D[2026-03-01], @sydney_lat, @sydney_lon, 3, 50, @three_minutes_tolerance)
    end

    # 2026-03-04: full moon (100%); USNO moonrise 19:47, moonset 07:10
    test "2026-03-04 moonrise — full moon" do
      assert_moonrise(~D[2026-03-04], @sydney_lat, @sydney_lon, 19, 47)
    end

    test "2026-03-04 moonset — full moon" do
      assert_moonset(~D[2026-03-04], @sydney_lat, @sydney_lon, 7, 10, @three_minutes_tolerance)
    end

    # 2026-03-08: USNO moonrise 21:37, moonset 11:11
    test "2026-03-08 moonrise — waning gibbous" do
      assert_moonrise(~D[2026-03-08], @sydney_lat, @sydney_lon, 21, 37)
    end

    test "2026-03-08 moonset — waning gibbous" do
      assert_moonset(~D[2026-03-08], @sydney_lat, @sydney_lon, 11, 11, @three_minutes_tolerance)
    end

    # 2026-03-11: USNO moonrise 23:39, moonset 14:07
    test "2026-03-11 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-11], @sydney_lat, @sydney_lon, 23, 39)
    end

    test "2026-03-11 moonset — waning crescent" do
      assert_moonset(~D[2026-03-11], @sydney_lat, @sydney_lon, 14, 7, @three_minutes_tolerance)
    end

    # 2026-03-13: USNO moonrise 00:32, moonset 15:48
    test "2026-03-13 moonrise — waning crescent" do
      assert_moonrise(~D[2026-03-13], @sydney_lat, @sydney_lon, 0, 32, @three_minutes_tolerance)
    end

    test "2026-03-13 moonset — waning crescent" do
      assert_moonset(~D[2026-03-13], @sydney_lat, @sydney_lon, 15, 48)
    end

    # 2026-03-19: new moon (0% illumination); USNO moonrise 06:49, moonset 19:05
    test "2026-03-19 moonrise — new moon" do
      assert_moonrise(~D[2026-03-19], @sydney_lat, @sydney_lon, 6, 49, @three_minutes_tolerance)
    end

    test "2026-03-19 moonset — new moon" do
      assert_moonset(~D[2026-03-19], @sydney_lat, @sydney_lon, 19, 5)
    end

    # 2026-03-20: waxing crescent (1.5%); USNO moonrise 07:56, moonset 19:34
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @sydney_lat, @sydney_lon, 7, 56, @three_minutes_tolerance)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @sydney_lat, @sydney_lon, 19, 34)
    end

    # 2026-03-25: waxing gibbous; USNO moonrise 13:50, moonset 23:23
    test "2026-03-25 moonrise — waxing gibbous" do
      assert_moonrise(~D[2026-03-25], @sydney_lat, @sydney_lon, 13, 50, @three_minutes_tolerance)
    end

    test "2026-03-25 moonset — waxing gibbous" do
      assert_moonset(~D[2026-03-25], @sydney_lat, @sydney_lon, 23, 23, @three_minutes_tolerance)
    end

    # 2026-03-31: USNO moonrise 17:49, moonset 04:58
    test "2026-03-31 moonrise — waxing gibbous, 96%" do
      assert_moonrise(~D[2026-03-31], @sydney_lat, @sydney_lon, 17, 49)
    end

    test "2026-03-31 moonset — waxing gibbous, 96%" do
      assert_moonset(~D[2026-03-31], @sydney_lat, @sydney_lon, 4, 58)
    end
  end

  # ---------------------------------------------------------------------------
  # Tokyo  (Asia/Tokyo — JST, UTC+9, no DST observed)
  # ---------------------------------------------------------------------------

  describe "Tokyo — moonrise and moonset" do
    # 2026-03-01: USNO moonrise 15:11, moonset 04:51
    test "2026-03-01 moonrise — waning gibbous, 93%" do
      assert_moonrise(~D[2026-03-01], @tokyo_lat, @tokyo_lon, 15, 11, @three_minutes_tolerance)
    end

    test "2026-03-01 moonset — waning gibbous, 93%" do
      assert_moonset(~D[2026-03-01], @tokyo_lat, @tokyo_lon, 4, 51)
    end

    # 2026-03-04: full moon; USNO moonrise 18:30, moonset 06:21
    test "2026-03-04 moonrise — full moon" do
      assert_moonrise(~D[2026-03-04], @tokyo_lat, @tokyo_lon, 18, 30, @three_minutes_tolerance)
    end

    test "2026-03-04 moonset — full moon" do
      assert_moonset(~D[2026-03-04], @tokyo_lat, @tokyo_lon, 6, 21)
    end

    # 2026-03-08: USNO moonrise 22:35, moonset 08:04
    test "2026-03-08 moonrise — waning gibbous" do
      assert_moonrise(~D[2026-03-08], @tokyo_lat, @tokyo_lon, 22, 35, @three_minutes_tolerance)
    end

    test "2026-03-08 moonset — waning gibbous" do
      assert_moonset(~D[2026-03-08], @tokyo_lat, @tokyo_lon, 8, 4)
    end

    # 2026-03-09: USNO moonrise 23:36, moonset 08:35
    test "2026-03-09 moonrise — waning gibbous" do
      assert_moonrise(~D[2026-03-09], @tokyo_lat, @tokyo_lon, 23, 36, @three_minutes_tolerance)
    end

    test "2026-03-09 moonset — waning gibbous" do
      assert_moonset(~D[2026-03-09], @tokyo_lat, @tokyo_lon, 8, 35)
    end

    # 2026-03-11: USNO moonrise 00:34, moonset 09:55
    test "2026-03-11 moonrise — last quarter" do
      assert_moonrise(~D[2026-03-11], @tokyo_lat, @tokyo_lon, 0, 34, @three_minutes_tolerance)
    end

    test "2026-03-11 moonset — last quarter" do
      assert_moonset(~D[2026-03-11], @tokyo_lat, @tokyo_lon, 9, 55)
    end

    # 2026-03-19: new moon (0% illumination); USNO moonrise 05:39, moonset 18:10
    test "2026-03-19 moonrise — new moon" do
      assert_moonrise(~D[2026-03-19], @tokyo_lat, @tokyo_lon, 5, 39)
    end

    test "2026-03-19 moonset — new moon" do
      assert_moonset(~D[2026-03-19], @tokyo_lat, @tokyo_lon, 18, 10, @three_minutes_tolerance)
    end

    # 2026-03-20: waxing crescent (1.6%); USNO moonrise 06:06, moonset 19:19
    test "2026-03-20 moonrise — waxing crescent" do
      assert_moonrise(~D[2026-03-20], @tokyo_lat, @tokyo_lon, 6, 6)
    end

    test "2026-03-20 moonset — waxing crescent" do
      assert_moonset(~D[2026-03-20], @tokyo_lat, @tokyo_lon, 19, 19, @three_minutes_tolerance)
    end

    # 2026-03-25: waxing gibbous; USNO moonrise 09:34, moonset 00:10
    test "2026-03-25 moonrise — waxing gibbous" do
      assert_moonrise(~D[2026-03-25], @tokyo_lat, @tokyo_lon, 9, 34, @three_minutes_tolerance)
    end

    test "2026-03-25 moonset — waxing gibbous (early hours)" do
      assert_moonset(~D[2026-03-25], @tokyo_lat, @tokyo_lon, 0, 10, @three_minutes_tolerance)
    end

    # 2026-03-31: USNO moonrise 16:18, moonset 04:23
    test "2026-03-31 moonrise — waxing gibbous, 96%" do
      assert_moonrise(~D[2026-03-31], @tokyo_lat, @tokyo_lon, 16, 18, @three_minutes_tolerance)
    end

    test "2026-03-31 moonset — waxing gibbous, 96%" do
      assert_moonset(~D[2026-03-31], @tokyo_lat, @tokyo_lon, 4, 23)
    end
  end
end
