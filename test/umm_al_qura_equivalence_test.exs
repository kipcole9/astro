defmodule Astro.UmmAlQura.EquivalenceTest do
  @moduledoc """
  Property-based test using StreamData to verify that the Tabular and
  Astronomical implementations of `first_day_of_month/2` agree on every
  month in their overlapping range, except for a small number of known
  boundary cases where the astronomical algorithm's precision limits
  produce a different result from the reference data.

  Era 3 (1420–1422 AH) achieves 100 % accuracy.  Era 4 (1423–1500 AH)
  achieves 99.7 % accuracy (933/936), with 3 known boundary-case months
  where moonset-sunset or conjunction-sunset timing falls within a few
  seconds — below the noise floor of any rise/set computation.

  Era 2 (1392–1419 AH) is excluded because the astronomical rule is a
  best-effort approximation (~96.7 % match) and is expected to diverge
  from the tabular data for ≈ 11 of 336 months.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Astro.UmmAlQura.{Tabular, Astronomical}

  # Era 3 starts at 1420 AH (moonset-only rule, 100% accurate).
  # The tabular data covers through ~1500 AH.
  @min_year 1420
  @max_year 1500

  # Known boundary cases where the astronomical model disagrees with
  # the van Gent reference data due to sub-minute event timing sensitivity.
  @known_boundary_cases MapSet.new([{1427, 6}, {1446, 6}, {1485, 10}])

  @tag timeout: :infinity
  property "Tabular and Astronomical first_day_of_month agree for 1420-1500 AH (Era 3 + Era 4)" do
    check all hijri_year <- integer(@min_year..@max_year),
              hijri_month <- integer(1..12),
              max_runs: 500 do
      {:ok, tabular_date} = Tabular.first_day_of_month(hijri_year, hijri_month)
      {:ok, astronomical_date} = Astronomical.first_day_of_month(hijri_year, hijri_month)

      if MapSet.member?(@known_boundary_cases, {hijri_year, hijri_month}) do
        # Known boundary case: astronomical may differ by exactly 1 day
        assert abs(Date.diff(astronomical_date, tabular_date)) <= 1,
               "Known boundary case #{hijri_year}/#{hijri_month} differs by more than 1 day: " <>
                 "tabular=#{tabular_date}, astronomical=#{astronomical_date}"
      else
        assert tabular_date == astronomical_date,
               "Mismatch at #{hijri_year}/#{hijri_month}: " <>
                 "tabular=#{tabular_date}, astronomical=#{astronomical_date}, " <>
                 "diff=#{Date.diff(astronomical_date, tabular_date)} days"
      end
    end
  end
end
