defmodule Astro.UmmAlQura.Comparison do
  @moduledoc """
  Runs the Umm al-Qura first-day calculation against the complete reference
  dataset and emits a formatted comparison table to stdout, followed by a
  summary of match / mismatch counts and the detailed astronomical conditions
  for any disagreeing entries.

  Run from the project root with:

      mix run -e "UmmAlQura.Comparison.run()"
  """

  alias Astro.UmmAlQura.ReferenceData
  alias Astro.UmmAlQura

  @doc """
  Executes the comparison and prints results to stdout.
  """
  def run do
    IO.puts("""
    ┌─────────────────────────────────────────────────────────────────────────┐
    │     Umm al-Qura Calendar — First-Day Calculation vs. Reference Data     │
    │     Mecca 21.4225°N 39.8262°E                                           │
    └─────────────────────────────────────────────────────────────────────────┘
    """)

    Astro.Supervisor.start_link()

    rows =
      ReferenceData.all()
      |> Enum.map(&evaluate_row/1)

    print_table(rows)
    print_summary(rows)
    print_mismatches(rows)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp evaluate_row({hijri_year, hijri_month, reference_date}) do
    month_name = Astro.UmmAlQura.MonthNames.month_name(hijri_month)

    result =
      case UmmAlQura.first_day_of_month(hijri_year, hijri_month) do
        {:ok, calculated_date} ->
          delta = Date.diff(calculated_date, reference_date)
          match = delta == 0

          %{
            hijri_year: hijri_year,
            hijri_month: hijri_month,
            month_name: month_name,
            reference_date: reference_date,
            calculated_date: calculated_date,
            delta_days: delta,
            match: match,
            error: nil
          }

        {:error, reason} ->
          %{
            hijri_year: hijri_year,
            hijri_month: hijri_month,
            month_name: month_name,
            reference_date: reference_date,
            calculated_date: nil,
            delta_days: nil,
            match: false,
            error: reason
          }
      end

    result
  end

  defp print_table(rows) do
    header = ["AH Year", "Month", "Month Name", "Reference", "Calculated", "Δ days", "Match?"]

    data =
      Enum.map(rows, fn row ->
        [
          Integer.to_string(row.hijri_year),
          Integer.to_string(row.hijri_month),
          row.month_name,
          Date.to_iso8601(row.reference_date),
          if(row.calculated_date, do: Date.to_iso8601(row.calculated_date), else: "ERROR"),
          if(row.delta_days, do: format_delta(row.delta_days), else: "—"),
          if(row.match, do: "✓", else: "✗")
        ]
      end)

    TableRex.quick_render!(data, header)
    |> IO.puts()
  end

  defp print_summary(rows) do
    total    = length(rows)
    matches  = Enum.count(rows, & &1.match)
    errors   = Enum.count(rows, & &1.error != nil)
    off_by_1 = Enum.count(rows, &(not &1.match and &1.delta_days != nil and abs(&1.delta_days) == 1))

    pct = Float.round(matches / total * 100, 1)

    IO.puts("""
    ─────────────────────────────────────────────────────────────────────────────
    Summary
    ─────────────────────────────────────────────────────────────────────────────
      Total entries evaluated : #{total}
      Exact matches           : #{matches}  (#{pct}%)
      Off by ±1 day           : #{off_by_1}
      Computation errors      : #{errors}
      Total discrepancies     : #{total - matches}
    ─────────────────────────────────────────────────────────────────────────────
    """)
  end

  defp print_mismatches(rows) do
    mismatches = Enum.reject(rows, & &1.match)

    if mismatches == [] do
      IO.puts("All calculated dates match the reference data exactly. ✓\n")
    else
      IO.puts("Discrepancy details:\n")

      Enum.each(mismatches, fn row ->
        IO.puts("  #{row.hijri_year} AH / Month #{row.hijri_month} (#{row.month_name})")
        IO.puts("    Reference  : #{Date.to_iso8601(row.reference_date)}")

        if row.error do
          IO.puts("    Error      : #{inspect(row.error)}")
        else
          IO.puts("    Calculated : #{Date.to_iso8601(row.calculated_date)}  (Δ #{format_delta(row.delta_days)} day(s))")
        end

        IO.puts("")
      end)
    end
  end

  defp format_delta(d) when d > 0, do: "+#{d}"
  defp format_delta(d),             do: Integer.to_string(d)
end
