defmodule Astro.Test.EquinoxTimeZone do
  use ExUnit.Case, async: true

  @events [equinox: :march, equinox: :september, solstice: :june, solstice: :december]

  describe "the :time_zone option" do
    test "defaults to UTC" do
      for {function, event} <- @events do
        assert apply(Astro, function, [2024, event]) ==
                 apply(Astro, function, [2024, event, [time_zone: :utc]])

        assert {:ok, %DateTime{time_zone: "Etc/UTC"}} = apply(Astro, function, [2024, event])
      end
    end

    test "gives the same instant in the requested time zone" do
      for {function, event} <- @events do
        {:ok, utc} = apply(Astro, function, [2024, event])
        {:ok, tokyo} = apply(Astro, function, [2024, event, [time_zone: "Asia/Tokyo"]])

        assert tokyo.time_zone == "Asia/Tokyo"
        assert DateTime.compare(tokyo, utc) == :eq
      end
    end

    test "decides the civil date of the event" do
      {:ok, utc} = Astro.equinox(2019, :march)
      {:ok, tokyo} = Astro.equinox(2019, :march, time_zone: "Asia/Tokyo")
      assert DateTime.to_date(utc) == ~D[2019-03-20]
      assert DateTime.to_date(tokyo) == ~D[2019-03-21]

      {:ok, santiago} = Astro.solstice(2021, :june, time_zone: "America/Santiago")
      assert DateTime.to_date(santiago) == ~D[2021-06-20]
    end

    test "gives the Tokyo date of every equinox from 2000 to 2100" do
      for year <- 2000..2100, event <- [:march, :september] do
        {:ok, utc} = Astro.equinox(year, event)
        {:ok, tokyo} = Astro.equinox(year, event, time_zone: "Asia/Tokyo")

        # Japan keeps +09:00 all year
        assert DateTime.to_date(tokyo) == utc |> DateTime.add(9, :hour) |> DateTime.to_date()
      end
    end
  end

  describe "the :time_zone_database option" do
    test "is used for a named time zone" do
      assert {:ok, %DateTime{time_zone: "Asia/Tokyo"}} =
               Astro.equinox(2024, :march,
                 time_zone: "Asia/Tokyo",
                 time_zone_database: Tz.TimeZoneDatabase
               )
    end

    test "a named time zone without a time zone database is an error" do
      assert Astro.equinox(2024, :march,
               time_zone: "Asia/Tokyo",
               time_zone_database: Calendar.UTCOnlyTimeZoneDatabase
             ) == {:error, :utc_only_time_zone_database}
    end

    test "UTC needs no time zone database" do
      assert {:ok, %DateTime{time_zone: "Etc/UTC"}} =
               Astro.solstice(2024, :june,
                 time_zone: "Etc/UTC",
                 time_zone_database: Calendar.UTCOnlyTimeZoneDatabase
               )
    end
  end

  describe "options that are not valid are errors, not exceptions" do
    test "a time zone that does not exist" do
      assert Astro.equinox(2024, :march, time_zone: "Mars/Olympus") ==
               {:error, :time_zone_not_found}
    end

    test "a time zone that is not a name" do
      for time_zone <- [:default, nil, 123, :"", ""] do
        assert {:error, _reason} = Astro.solstice(2024, :december, time_zone: time_zone)
      end
    end

    test "a time zone database that is not one" do
      for database <- [String, nil, "Tz.TimeZoneDatabase", :not_a_module] do
        assert Astro.equinox(2024, :march, time_zone: "Asia/Tokyo", time_zone_database: database) ==
                 {:error, :invalid_time_zone_database}
      end
    end

    test "options that are not a keyword list" do
      assert Astro.equinox(2024, :march, "Asia/Tokyo") == {:error, :time_zone_not_found}
    end

    test "a year out of range is still reported first" do
      assert Astro.solstice(900, :june, time_zone: "Mars/Olympus") == {:error, :year_out_of_range}
    end
  end
end
