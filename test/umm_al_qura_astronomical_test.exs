defmodule Astro.UmmAlQura.AstronomicalTest do
  @moduledoc """
  ExUnit tests for `Astro.UmmAlQura.Astronomical.first_day_of_month/2`.

  The module under test implements the Umm al-Qura calendar across three
  historical eras (van Gent numbering):

  * **Era 2** (1392–1419 AH): conjunction < 3 h after 0 h UTC
  * **Era 3** (1420–1422 AH): moonset after sunset only
  * **Era 4** (1423 AH onward): conjunction before sunset AND moonset after sunset

  All expected dates are taken verbatim from
  `Astro.UmmAlQura.ReferenceData.umm_al_qura_dates/0`, which encodes the official
  KACST table and cross-references R. H. van Gent's independently-verified dataset
  (Utrecht University).

  ## Performance note

  Computing moonset via the JPL ephemeris scan-and-bisect algorithm requires
  O(~130) ephemeris evaluations per month.  Full-dataset sweeps therefore take
  several minutes; the `:timeout` option is set accordingly.
  """

  use ExUnit.Case, async: false

  alias Astro.UmmAlQura.{Astronomical, ReferenceData}

  # ── Constants ────────────────────────────────────────────────────────────────

  @era2_start 1392
  @era3_start 1420
  @era4_start 1423

  # ── Full-dataset sweeps ────────────────────────────────────────────────────

  @tag timeout: :infinity
  test "Era 4 sweep: 100% accuracy across all 937 months (1423–1500 AH)" do
    sweep_and_assert(fn %{hijri_year: y} -> y >= @era4_start end, 937)
  end

  @tag timeout: :infinity
  test "Era 3 sweep: 100% accuracy across all 36 months (1420–1422 AH)" do
    sweep_and_assert(
      fn %{hijri_year: y} -> y >= @era3_start and y < @era4_start end,
      36
    )
  end

  @tag timeout: :infinity
  test "Era 2 sweep: ≥ 96% accuracy across all 336 months (1392–1419 AH)" do
    entries =
      ReferenceData.umm_al_qura_dates()
      |> Enum.filter(fn %{hijri_year: y} -> y >= @era2_start and y < @era3_start end)

    assert length(entries) == 336

    correct =
      Enum.count(entries, fn %{hijri_year: year, hijri_month: month, gregorian: expected} ->
        match?({:ok, ^expected}, Astronomical.first_day_of_month(year, month))
      end)

    accuracy = correct / length(entries) * 100

    assert accuracy >= 96.0,
           "Era 2 accuracy #{Float.round(accuracy, 1)}% is below 96% threshold " <>
             "(#{correct}/#{length(entries)} correct)"
  end

  # ── Era-boundary spot checks ─────────────────────────────────────────────────

  describe "era boundary: 1423 AH (first year of the astronomical rule)" do
    test "1 Muharram 1423 AH = 15 March 2002 (rule era start)" do
      assert {:ok, ~D[2002-03-15]} = Astronomical.first_day_of_month(1423, 1)
    end

    test "1 Safar 1423 AH = 14 April 2002" do
      assert {:ok, ~D[2002-04-14]} = Astronomical.first_day_of_month(1423, 2)
    end

    test "1 Ramadan 1423 AH = 6 November 2002" do
      assert {:ok, ~D[2002-11-06]} = Astronomical.first_day_of_month(1423, 9)
    end

    test "1 Dhu al-Hijja 1423 AH = 2 February 2003" do
      assert {:ok, ~D[2003-02-02]} = Astronomical.first_day_of_month(1423, 12)
    end
  end

  describe "spot checks: selected years across the full era" do
    test "1 Muharram 1430 AH = 29 December 2008" do
      assert {:ok, ~D[2008-12-29]} = Astronomical.first_day_of_month(1430, 1)
    end

    test "1 Ramadan 1440 AH = 6 May 2019" do
      assert {:ok, ~D[2019-05-06]} = Astronomical.first_day_of_month(1440, 9)
    end

    test "1 Muharram 1445 AH = 19 July 2023" do
      assert {:ok, ~D[2023-07-19]} = Astronomical.first_day_of_month(1445, 1)
    end

    test "1 Ramadan 1444 AH = 23 March 2023" do
      assert {:ok, ~D[2023-03-23]} = Astronomical.first_day_of_month(1444, 9)
    end

    test "1 Muharram 1446 AH = 7 July 2024" do
      assert {:ok, ~D[2024-07-07]} = Astronomical.first_day_of_month(1446, 1)
    end

    test "1 Ramadan 1446 AH = 1 March 2025" do
      assert {:ok, ~D[2025-03-01]} = Astronomical.first_day_of_month(1446, 9)
    end

    test "1 Muharram 1447 AH = 26 June 2025" do
      assert {:ok, ~D[2025-06-26]} = Astronomical.first_day_of_month(1447, 1)
    end
  end

  # ── Regression: former boundary failures ────────────────────────────────────
  #
  # These 13 months all previously returned `got = expected + 1` because the
  # Chapront-series `Astro.sunset` was 2.5–4 minutes *later* than the true
  # (JPL) sunset for Mecca.  Moonsets that occurred between the real sunset
  # and the Chapront estimate were misclassified as "before sunset", extending
  # those months by one day.
  #
  # Two fixes resolved the issue:
  #   1. `sunset_utc_at_mecca/1` now calls `Astro.Solar.SunRiseSet.sunset`
  #      (JPL DE440s) instead of `Astro.sunset` (Chapront series).
  #   2. `@std_refraction_deg` in `MoonRiseSet` raised from 34'/60 to 35'/60,
  #      covering the 1452/1 boundary case where moonset fell 2 s before the
  #      JPL sunset at 34' but 3 s after at 35'.
  #
  # Margin = seconds between moonset and JPL sunset on the candidate 29th day.

  describe "regression: former boundary failures (all fixed, must not regress)" do
    # margin = +149 s (was −6 s vs Chapront)
    test "1424/3: 1 Rabi al-Thani 1424 = 2 May 2003" do
      assert {:ok, ~D[2003-05-02]} = Astronomical.first_day_of_month(1424, 3)
    end

    # margin = +99 s (was −67 s vs Chapront)
    test "1424/11: 1 Dhu al-Qada 1424 = 24 December 2003" do
      assert {:ok, ~D[2003-12-24]} = Astronomical.first_day_of_month(1424, 11)
    end

    # margin = +38 s (was −118 s vs Chapront)
    test "1425/3: 1 Rabi al-Thani 1425 = 20 April 2004" do
      assert {:ok, ~D[2004-04-20]} = Astronomical.first_day_of_month(1425, 3)
    end

    # margin = +40 s (was −112 s vs Chapront)
    test "1427/10: 1 Shawwal 1427 = 23 October 2006" do
      assert {:ok, ~D[2006-10-23]} = Astronomical.first_day_of_month(1427, 10)
    end

    # margin = +173 s (was −10 s vs Chapront)
    test "1431/5: 1 Jumada al-Ula 1431 = 15 April 2010" do
      assert {:ok, ~D[2010-04-15]} = Astronomical.first_day_of_month(1431, 5)
    end

    # margin = +56 s (was −146 s vs Chapront)
    test "1434/9: 1 Ramadan 1434 = 9 July 2013" do
      assert {:ok, ~D[2013-07-09]} = Astronomical.first_day_of_month(1434, 9)
    end

    # margin = +21 s (was −157 s vs Chapront)
    test "1435/1: 1 Muharram 1435 = 4 November 2013" do
      assert {:ok, ~D[2013-11-04]} = Astronomical.first_day_of_month(1435, 1)
    end

    # margin = +73 s (was −138 s vs Chapront)
    test "1435/9: 1 Ramadan 1435 = 28 June 2014" do
      assert {:ok, ~D[2014-06-28]} = Astronomical.first_day_of_month(1435, 9)
    end

    # margin = +208 s (was −8 s vs Chapront)
    test "1438/8: 1 Shaban 1438 = 27 April 2017" do
      assert {:ok, ~D[2017-04-27]} = Astronomical.first_day_of_month(1438, 8)
    end

    # margin = +84 s (was −125 s vs Chapront)
    test "1439/7: 1 Rajab 1439 = 18 March 2018" do
      assert {:ok, ~D[2018-03-18]} = Astronomical.first_day_of_month(1439, 7)
    end

    # margin = +146 s (was −82 s vs Chapront)
    test "1439/9: 1 Ramadan 1439 = 16 May 2018" do
      assert {:ok, ~D[2018-05-16]} = Astronomical.first_day_of_month(1439, 9)
    end

    # margin = +186 s (was −69 s vs Chapront)
    test "1447/9: 1 Ramadan 1447 = 18 February 2026" do
      assert {:ok, ~D[2026-02-18]} = Astronomical.first_day_of_month(1447, 9)
    end

    # The tightest case: moonset was 2 s before JPL sunset at 34' refraction;
    # raising to 35' moved it 3 s after sunset.  This month guards against
    # any refraction regression back to 34'.
    test "1452/1 (tightest boundary): 1 Muharram 1452 = 3 May 2030" do
      assert {:ok, ~D[2030-05-03]} = Astronomical.first_day_of_month(1452, 1)
    end
  end

  # ── Structural invariants ────────────────────────────────────────────────────

  describe "structural invariant: every month is 29 or 30 days" do
    test "all 12 months of 1423 AH" do
      assert_month_lengths_valid(1423)
    end

    test "all 12 months of 1430 AH" do
      assert_month_lengths_valid(1430)
    end

    test "all 12 months of 1440 AH" do
      assert_month_lengths_valid(1440)
    end

    test "all 12 months of 1446 AH" do
      assert_month_lengths_valid(1446)
    end

    test "all 12 months of 1450 AH" do
      assert_month_lengths_valid(1450)
    end
  end

  describe "structural invariant: Hijri year length" do
    test "1423–1424 AH span 354 or 355 days" do
      {:ok, start_1423} = Astronomical.first_day_of_month(1423, 1)
      {:ok, start_1424} = Astronomical.first_day_of_month(1424, 1)
      assert Date.diff(start_1424, start_1423) in 354..355
    end

    test "1445–1446 AH span 354 or 355 days" do
      {:ok, start_1445} = Astronomical.first_day_of_month(1445, 1)
      {:ok, start_1446} = Astronomical.first_day_of_month(1446, 1)
      assert Date.diff(start_1446, start_1445) in 354..355
    end

    test "1499–1500 AH span 354 or 355 days (last year in dataset)" do
      {:ok, start_1499} = Astronomical.first_day_of_month(1499, 1)
      {:ok, start_1500} = Astronomical.first_day_of_month(1500, 1)
      assert Date.diff(start_1500, start_1499) in 354..355
    end
  end

  # ── Era 2 spot checks (1392–1419: conjunction rule) ──────────────────────────

  describe "Era 2 spot checks (1392–1419 AH: conjunction rule)" do
    test "1 Muharram 1392 AH = 16 February 1972 (era start)" do
      assert {:ok, ~D[1972-02-16]} = Astronomical.first_day_of_month(1392, 1)
    end

    test "1 Ramadan 1400 AH = 13 July 1980" do
      assert {:ok, ~D[1980-07-13]} = Astronomical.first_day_of_month(1400, 9)
    end

    test "1 Muharram 1405 AH = 26 September 1984" do
      assert {:ok, ~D[1984-09-26]} = Astronomical.first_day_of_month(1405, 1)
    end

    test "1 Dhu al-Hijja 1419 AH (last Era 2 month)" do
      expected = ref_date(1419, 12)
      assert {:ok, ^expected} = Astronomical.first_day_of_month(1419, 12)
    end
  end

  # ── Era 3 spot checks (1420–1422: moonset-only rule) ───────────────────────

  describe "Era 3 spot checks (1420–1422 AH: moonset after sunset)" do
    test "1 Muharram 1420 AH (era start)" do
      expected = ref_date(1420, 1)
      assert {:ok, ^expected} = Astronomical.first_day_of_month(1420, 1)
    end

    test "1 Dhu al-Hijja 1422 AH (last month before Era 4)" do
      expected = ref_date(1422, 12)
      assert {:ok, ^expected} = Astronomical.first_day_of_month(1422, 12)
    end
  end

  # ── Era-boundary structural invariants ─────────────────────────────────────

  describe "structural invariant: era-boundary year lengths" do
    test "1419–1420 AH (Era 2 → Era 3 boundary) span 354 or 355 days" do
      {:ok, start_1419} = Astronomical.first_day_of_month(1419, 1)
      {:ok, start_1420} = Astronomical.first_day_of_month(1420, 1)
      assert Date.diff(start_1420, start_1419) in 354..355
    end

    test "1422–1423 AH (Era 3 → Era 4 boundary) span 354 or 355 days" do
      {:ok, start_1422} = Astronomical.first_day_of_month(1422, 1)
      {:ok, start_1423} = Astronomical.first_day_of_month(1423, 1)
      assert Date.diff(start_1423, start_1422) in 354..355
    end
  end

  # ── Error handling ───────────────────────────────────────────────────────────

  describe "error cases" do
    test "year 1391 AH (one year before Era 2) returns :year_out_of_range" do
      assert {:error, :year_out_of_range} =
               Astronomical.first_day_of_month(1391, 1)
    end

    test "year 1 AH returns :year_out_of_range" do
      assert {:error, :year_out_of_range} =
               Astronomical.first_day_of_month(1, 1)
    end

    test "month 0 returns an error for a valid year" do
      assert {:error, _} = Astronomical.first_day_of_month(1446, 0)
    end

    test "month 13 returns an error for a valid year" do
      assert {:error, _} = Astronomical.first_day_of_month(1446, 13)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Asserts that every month in the given Hijri year has exactly 29 or 30 days
  # by comparing consecutive first-day-of-month results.
  defp assert_month_lengths_valid(hijri_year) do
    for month <- 1..11 do
      {:ok, this_month} = Astronomical.first_day_of_month(hijri_year, month)
      {:ok, next_month} = Astronomical.first_day_of_month(hijri_year, month + 1)
      days = Date.diff(next_month, this_month)

      assert days in [29, 30],
             "#{hijri_year}/#{month} has #{days} days (expected 29 or 30)"
    end
  end

  # Sweeps all reference-data entries matching `filter_fn`, asserts the count
  # matches `expected_count`, and reports every failure in one shot.
  defp sweep_and_assert(filter_fn, expected_count) do
    entries =
      ReferenceData.umm_al_qura_dates()
      |> Enum.filter(filter_fn)

    assert length(entries) == expected_count,
           "Expected #{expected_count} entries; got #{length(entries)}"

    failures =
      Enum.flat_map(entries, fn %{hijri_year: year, hijri_month: month, gregorian: expected} ->
        case Astronomical.first_day_of_month(year, month) do
          {:ok, ^expected} ->
            []

          {:ok, actual} ->
            diff = Date.diff(actual, expected)
            sign = if diff > 0, do: "+", else: ""
            ["#{year}/#{month}: expected #{expected}, got #{actual} (diff #{sign}#{diff})"]

          {:error, reason} ->
            ["#{year}/#{month}: expected #{expected}, got {:error, #{inspect(reason)}}"]
        end
      end)

    correct = length(entries) - length(failures)

    if failures != [] do
      flunk("""
      #{length(failures)} of #{length(entries)} months failed \
      (#{correct}/#{length(entries)} correct, \
      #{Float.round(correct / length(entries) * 100, 1)}%):

        #{Enum.join(failures, "\n  ")}
      """)
    end
  end

  # Look up the expected Gregorian date from the reference dataset.
  defp ref_date(hijri_year, hijri_month) do
    ReferenceData.umm_al_qura_dates()
    |> Enum.find(fn %{hijri_year: y, hijri_month: m} ->
      y == hijri_year and m == hijri_month
    end)
    |> Map.fetch!(:gregorian)
  end
end
