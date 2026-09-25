defmodule Astro.UtcOnlyTimeZoneDatabaseTest do
  # The time zone database is global, so these tests cannot run alongside others.
  use ExUnit.Case, async: false

  # An application that configures no time zone database gets
  # `Calendar.UTCOnlyTimeZoneDatabase`, which knows only `Etc/UTC`. Astro's own
  # config installs `Tz`, which would hide any dependence on a full database,
  # so these run under the default.
  setup do
    previous = Calendar.get_time_zone_database()
    Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)
    on_exit(fn -> Calendar.put_time_zone_database(previous) end)
  end

  describe "without a time zone database" do
    test "the sun's azimuth and elevation are computed" do
      assert {azimuth, elevation} =
               Astro.sun_azimuth_elevation(
                 {151.20666584, -33.8559799094},
                 ~U[2019-12-04 02:00:00Z]
               )

      assert is_float(azimuth) and is_float(elevation)
    end

    test "sidereal time is computed" do
      assert Float.round(Astro.Time.greenwich_mean_sidereal_time(~U[2000-01-01 12:00:00Z]), 4) ==
               280.4606

      assert is_float(Astro.Time.local_sidereal_time({0.0, 51.5}, ~U[2000-01-01 12:00:00Z]))
    end

    test "instants in UTC are computed" do
      assert {:ok, %DateTime{time_zone: "Etc/UTC"}} = Astro.equinox(2019, :march)

      assert {:ok, %DateTime{time_zone: "Etc/UTC"}} =
               Astro.date_time_new_moon_nearest(~U[2024-06-21 12:00:00Z])

      assert is_float(Astro.lunar_phase_at(~U[2024-06-21 12:00:00Z]))
    end

    test "an instant in a named zone is an error, not an exception" do
      assert Astro.equinox(2019, :march, time_zone: "Asia/Tokyo") ==
               {:error, :utc_only_time_zone_database}
    end
  end
end
