defmodule Astro.UmmAlQura.EquivalenceTest do
  @moduledoc """
  Property-based test using StreamData to verify that the Tabular and
  Astronomical implementations of `first_day_of_month/2` agree on every
  month in their overlapping range (1423–1500 AH).
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Astro.UmmAlQura.{Tabular, Astronomical}

  # The astronomical rule is valid from 1423 AH; the tabular data
  # covers through ~1500 AH.  Their overlap is 1423..1500.
  @min_year 1423
  @max_year 1500

  @tag timeout: :infinity
  property "Tabular and Astronomical first_day_of_month agree for 1423-1500 AH" do
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
