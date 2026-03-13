defmodule AstroTest do
  use ExUnit.Case
  doctest Astro
  doctest Astro.Time
  doctest Astro.Solar
  doctest Astro.Earth
  doctest Astro.Lunar

  test "A time zone not found for a location returns an error" do
    assert Astro.sunrise({1.1, 3.5}, Date.utc_today()) == {:error, :time_zone_not_found}
  end

  test "An invalid timezone returns an error" do
    assert Astro.sunrise({0.0, 51.0}, Date.utc_today(), time_zone: "no_such_time_zone") ==
             {:error, :time_zone_not_found}
  end

  test "sunset in Urbana IL" do
    {:ok, date} = Date.new(1945, 11, 12)

    {:ok, test_date} =
      DateTime.from_naive(
        ~N[1945-11-12 16:39:06],
        "America/Chicago",
        Tzdata.TimeZoneDatabase
      )

    assert {:ok, actual} = Astro.sunset({-88.2073, 40.1106}, date)
    assert DateTime.truncate(actual, :second) == test_date
  end

  test "sunset in Nunavut" do
    {:ok, date} = Date.new(1945, 11, 12)

    {:ok, test_date} =
      DateTime.from_naive(
        ~N[1945-11-12 14:24:07-05:00],
        "America/Iqaluit",
        Tzdata.TimeZoneDatabase
      )

    assert {:ok, actual} = Astro.sunset({-83.1076, 70.2998}, date)
    assert DateTime.truncate(actual, :second) == test_date
  end

  test "sunset and sunrise in Alert NU doesn't happen in winter" do
    {:ok, date} = Date.new(2019, 12, 4)

    assert Astro.sunset({-62.3481, 82.5018}, date) == {:error, :no_time}
    assert Astro.sunrise({-62.3481, 82.5018}, date) == {:error, :no_time}
  end

  test "sunrise and sunset in Alert NU doesn't happen in summer" do
    {:ok, date} = Date.new(2019, 7, 1)

    assert Astro.sunset({-62.3481, 82.5018}, date) == {:error, :no_time}
    assert Astro.sunrise({-62.3481, 82.5018}, date) == {:error, :no_time}
  end

  test "Time zone offset for float t" do
    assert Astro.Time.offset_for_zone(63_794_995_200.96832, "Europe/London") ==
             {:ok, 0.041666666666666664}
  end

  test "sunrise and sunset handle date gaps gracefully" do
    {:ok, date} = Date.new(2025, 09, 07)

    santiago_chile = {-70.673676, -33.447487}

    {:ok, test_date} =
      DateTime.new(
        ~D[2025-09-07],
        ~T[19:29:25],
        "America/Santiago"
      )

    assert {:ok, actual} = Astro.sunset(santiago_chile, date)
    assert DateTime.truncate(actual, :second) == test_date
  end
end
