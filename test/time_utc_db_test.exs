defmodule Astro.Test.Time.UtcDatabase do
  # Not async: these tests mutate the global configured time zone database.
  use ExUnit.Case, async: false

  # A time zone database that, like Tzdata with out-of-range data, cannot
  # resolve dates before 1900 — even for `Etc/UTC`. Reproduces the compile-time
  # failure reported against Calendrical, where ancient era boundaries are
  # computed while `Tzdata.TimeZoneDatabase` is the configured database.
  defmodule OutOfRangeDatabase do
    @behaviour Calendar.TimeZoneDatabase

    @impl true
    def time_zone_period_from_utc_iso_days(iso_days, time_zone) do
      {year, _, _, _, _, _, _} = Calendar.ISO.naive_datetime_from_iso_days(iso_days)

      if year < 1900 do
        {:error, :time_zone_not_found}
      else
        {:ok, %{std_offset: 0, utc_offset: 0, zone_abbr: time_zone}}
      end
    end

    @impl true
    def time_zone_periods_from_wall_datetime(_naive_datetime, _time_zone) do
      {:error, :time_zone_not_found}
    end
  end

  setup do
    previous = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(OutOfRangeDatabase)
    on_exit(fn -> Calendar.put_time_zone_database(previous) end)
    :ok
  end

  test "date_time_from_date_and_minutes/2 ignores the configured database for UTC arithmetic" do
    # ~1243 CE is the Persian calendar era boundary that triggered the report.
    # The configured database cannot resolve it, but the computation is pure UTC
    # and must not consult that database.
    {:ok, datetime} = Astro.Time.date_time_from_date_and_minutes(522.0, ~D[1243-03-20])

    assert datetime.time_zone == "Etc/UTC"
    assert datetime == ~U[1243-03-20 08:42:00Z]
  end

  test "equinox/2 computes ancient events despite an out-of-range configured database" do
    {:ok, equinox} = Astro.equinox(1243, :march)
    assert equinox.year == 1243
    assert equinox.month == 3
  end
end
