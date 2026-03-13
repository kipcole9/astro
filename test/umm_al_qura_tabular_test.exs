defmodule Astro.UmmAlQuraTest do
  @moduledoc """
  ExUnit tests for `Astro.UmmAlQura.Tabular.first_day_of_month/2`.

  All expected dates are taken directly from
  `Astro.UmmAlQura.ReferenceData.umm_al_qura_dates/0`, which encodes the
  official Umm al-Qura tables published by KACST and cross-referenced against
  the dataset maintained by R.H. van Gent (Utrecht University).

  Because the implementation embeds the official data at compile time, the
  test suite asserts 100% accuracy with no tolerance for off-by-one errors.
  """

  use ExUnit.Case, async: true

  alias Astro.UmmAlQura
  alias Astro.UmmAlQura.ReferenceData

  # ---------------------------------------------------------------------------
  # Full-dataset validation
  # ---------------------------------------------------------------------------

  test "first_day_of_month/2 is correct for every entry in the official dataset" do
    reference_data = ReferenceData.umm_al_qura_dates()

    assert length(reference_data) > 0,
           "Reference data must not be empty — check Astro.UmmAlQura.ReferenceData"

    failures =
      Enum.reduce(reference_data, [], fn %{
                                           hijri_year: year,
                                           hijri_month: month,
                                           gregorian: expected
                                         },
                                         acc ->
        case UmmAlQura.Tabular.first_day_of_month(year, month) do
          {:ok, ^expected} ->
            acc

          {:ok, actual} ->
            [
              "#{year}/#{month}: expected #{Date.to_iso8601(expected)}, got #{Date.to_iso8601(actual)}"
              | acc
            ]

          {:error, reason} ->
            [
              "#{year}/#{month}: expected #{Date.to_iso8601(expected)}, got error #{inspect(reason)}"
              | acc
            ]
        end
      end)

    if failures != [] do
      flunk("""
      #{length(failures)} of #{length(reference_data)} reference entries failed:

        #{failures |> Enum.reverse() |> Enum.join("\n  ")}
      """)
    end
  end

  test "first_day_of_month/2 achieves 100% accuracy across the full dataset" do
    reference_data = ReferenceData.umm_al_qura_dates()
    total = length(reference_data)

    correct =
      Enum.count(reference_data, fn %{hijri_year: year, hijri_month: month, gregorian: expected} ->
        match?({:ok, ^expected}, UmmAlQura.Tabular.first_day_of_month(year, month))
      end)

    assert correct == total,
           "Expected 100% accuracy (#{total}/#{total}), achieved #{correct}/#{total}"
  end

  # ---------------------------------------------------------------------------
  # Spot checks — era boundaries
  # ---------------------------------------------------------------------------

  describe "Era 1 (1356–1419 AH) spot checks" do
    test "1 Muharram 1356 AH = 14 March 1937 (dataset start)" do
      assert {:ok, ~D[1937-03-14]} = UmmAlQura.Tabular.first_day_of_month(1356, 1)
    end

    test "1 Muharram 1392 AH = 16 February 1972" do
      # Official KACST table value: 1972-02-16
      assert {:ok, ~D[1972-02-16]} = UmmAlQura.Tabular.first_day_of_month(1392, 1)
    end

    test "1 Ramadan 1400 AH = 13 July 1980" do
      # Official KACST table value: 1980-07-13
      assert {:ok, ~D[1980-07-13]} = UmmAlQura.Tabular.first_day_of_month(1400, 9)
    end
  end

  describe "Era 3 (≥ 1423 AH) spot checks" do
    test "1 Muharram 1423 AH = 15 March 2002 (current rule era start)" do
      assert {:ok, ~D[2002-03-15]} = UmmAlQura.Tabular.first_day_of_month(1423, 1)
    end

    test "1 Ramadan 1444 AH = 23 March 2023" do
      assert {:ok, ~D[2023-03-23]} = UmmAlQura.Tabular.first_day_of_month(1444, 9)
    end

    test "1 Muharram 1446 AH = 7 July 2024" do
      assert {:ok, ~D[2024-07-07]} = UmmAlQura.Tabular.first_day_of_month(1446, 1)
    end

    test "1 Ramadan 1446 AH = 1 March 2025" do
      assert {:ok, ~D[2025-03-01]} = UmmAlQura.Tabular.first_day_of_month(1446, 9)
    end
  end

  # ---------------------------------------------------------------------------
  # Regression: months previously wrong with the approximate_29th approach
  # ---------------------------------------------------------------------------

  describe "regression: months that failed with approximate_29th (~25% error rate)" do
    test "all 12 months of 1430 AH" do
      for month <- 1..12 do
        {:ok, result} = UmmAlQura.Tabular.first_day_of_month(1430, month)
        expected = reference_date_for(1430, month)

        assert result == expected,
               "1430/#{month}: expected #{Date.to_iso8601(expected)}, got #{Date.to_iso8601(result)}"
      end
    end

    test "all 12 months of 1440 AH" do
      for month <- 1..12 do
        {:ok, result} = UmmAlQura.Tabular.first_day_of_month(1440, month)
        expected = reference_date_for(1440, month)

        assert result == expected,
               "1440/#{month}: expected #{Date.to_iso8601(expected)}, got #{Date.to_iso8601(result)}"
      end
    end

    test "all 12 months of 1445 AH" do
      for month <- 1..12 do
        {:ok, result} = UmmAlQura.Tabular.first_day_of_month(1445, month)
        expected = reference_date_for(1445, month)

        assert result == expected,
               "1445/#{month}: expected #{Date.to_iso8601(expected)}, got #{Date.to_iso8601(result)}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Structural / edge-case assertions
  # ---------------------------------------------------------------------------

  describe "structural invariants" do
    test "consecutive months in 1446 AH are 29 or 30 days apart" do
      for month <- 1..11 do
        {:ok, first_of_month} = UmmAlQura.Tabular.first_day_of_month(1446, month)
        {:ok, first_of_next_month} = UmmAlQura.Tabular.first_day_of_month(1446, month + 1)

        diff = Date.diff(first_of_next_month, first_of_month)

        assert diff in [29, 30],
               "Month 1446/#{month} has #{diff} days; expected 29 or 30"
      end
    end

    test "1 Muharram of consecutive years are 354–355 days apart (1445→1446)" do
      {:ok, start_1445} = UmmAlQura.Tabular.first_day_of_month(1445, 1)
      {:ok, start_1446} = UmmAlQura.Tabular.first_day_of_month(1446, 1)

      diff = Date.diff(start_1446, start_1445)

      assert diff in 354..355,
             "Expected ~354-355 day Hijri year, got #{diff} days between 1 Muharram 1445 and 1446"
    end

    test "month 12 (Dhu al-Hijja) 1445 AH is correctly bounded" do
      {:ok, result} = UmmAlQura.Tabular.first_day_of_month(1445, 12)
      expected = reference_date_for(1445, 12)
      assert result == expected
    end
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "error cases" do
    test "returns error for a year beyond the dataset" do
      assert {:error, :date_not_in_official_table} = UmmAlQura.Tabular.first_day_of_month(9999, 1)
    end

    test "returns error for month 0" do
      assert {:error, :date_not_in_official_table} = UmmAlQura.Tabular.first_day_of_month(1446, 0)
    end

    test "returns error for month 13" do
      assert {:error, :date_not_in_official_table} =
               UmmAlQura.Tabular.first_day_of_month(1446, 13)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reference_date_for(hijri_year, hijri_month) do
    case Enum.find(ReferenceData.umm_al_qura_dates(), fn %{hijri_year: y, hijri_month: m} ->
           y == hijri_year and m == hijri_month
         end) do
      nil ->
        raise "No reference entry found for #{hijri_year}/#{hijri_month}"

      %{gregorian: date} ->
        date
    end
  end
end
