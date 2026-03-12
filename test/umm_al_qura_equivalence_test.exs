defmodule Astro.UmmAlQura.EquivalenceTest do
  @moduledoc """
  Property-based test using StreamData to verify that the Tabular and
  Astronomical implementations of `first_day_of_month/2` agree on every
  month in their overlapping range.

  Era 3 (1420–1422 AH) and Era 4 (1423–1500 AH) both achieve 100 %
  accuracy against the KACST reference data, so the two implementations
  must return identical dates across the combined 1420–1500 AH range.

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

  @tag timeout: :infinity
  property "Tabular and Astronomical first_day_of_month agree for 1420-1500 AH (Era 3 + Era 4)" do
    check all hijri_year <- integer(@min_year..@max_year),
              hijri_month <- integer(1..12),
              max_runs: 500 do
      {:ok, tabular_date} = Tabular.first_day_of_month(hijri_year, hijri_month)
      {:ok, astronomical_date} = Astronomical.first_day_of_month(hijri_year, hijri_month)

      assert tabular_date == astronomical_date,
             "Mismatch at #{hijri_year}/#{hijri_month}: " <>
               "tabular=#{tabular_date}, astronomical=#{astronomical_date}, " <>
               "diff=#{Date.diff(astronomical_date, tabular_date)} days"
    end
  end
end
