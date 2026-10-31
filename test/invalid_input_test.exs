defmodule Astro.InvalidInputTest do
  use ExUnit.Case, async: true

  # Every function in Astro that returns `{:ok, _}` or `{:error, _}` returns
  # an error for invalid arguments rather than raising.

  @location {151.20666584, -33.8559799094}
  @date ~D[2024-06-21]
  @utc [time_zone: :utc]

  @not_locations [nil, "", :"", 2024, "Sydney", %{}, [], {200.0, 0.0}, {0.0, 95.0}, {"0", "0"}]
  @not_dates [
    nil,
    "",
    :"",
    2024,
    "2024-06-21",
    %{},
    [],
    %{year: 2024, month: 2, day: 30, calendar: Calendar.ISO},
    %{year: 2024, month: 2, day: 3, calendar: NotACalendar},
    %{year: "2024", month: 2, day: 3, calendar: Calendar.ISO}
  ]
  @not_options [nil, "", :"", %{}, {:time_zone, :utc}, 1]

  describe "rise and set" do
    for function <- [:sunrise, :sunset, :moonrise, :moonset] do
      test "#{function} returns errors for an invalid location, date or options" do
        function = unquote(function)

        for location <- @not_locations do
          assert apply(Astro, function, [location, @date, @utc]) == {:error, :invalid_location}
        end

        for date <- @not_dates do
          assert apply(Astro, function, [@location, date, @utc]) == {:error, :invalid_date}
        end

        for options <- @not_options do
          assert apply(Astro, function, [@location, @date, options]) == {:error, :invalid_options}
        end
      end

      test "#{function} returns errors for an invalid resolver or database" do
        function = unquote(function)

        for resolver <- ["", :utc, fn -> "UTC" end, fn _a, _b -> "UTC" end] do
          options = [time_zone_resolver: resolver]

          assert apply(Astro, function, [@location, @date, options]) ==
                   {:error, :invalid_time_zone_resolver}
        end

        for result <- [:bad, nil, {:ok, 1}, {:ok, :utc}] do
          options = [time_zone_resolver: fn _point -> result end]

          assert apply(Astro, function, [@location, @date, options]) ==
                   {:error, :time_zone_not_resolved}
        end

        for database <- [nil, "", Enum, 123] do
          options = [time_zone: "Australia/Sydney", time_zone_database: database]

          assert apply(Astro, function, [@location, @date, options]) ==
                   {:error, :invalid_time_zone_database}
        end
      end
    end
  end

  describe "solar noon and daylight" do
    test "return errors for an invalid location or date" do
      for location <- @not_locations do
        assert Astro.solar_noon(location, @date) == {:error, :invalid_location}
        assert Astro.hours_of_daylight(location, @date) == {:error, :invalid_location}
        assert Astro.duration_of_daylight(location, @date) == {:error, :invalid_location}
      end

      for date <- @not_dates do
        assert {:error, reason} = Astro.solar_noon(@location, date)
        assert reason in [:invalid_date, :incompatible_calendars]
        assert Astro.hours_of_daylight(@location, date) == {:error, :invalid_date}
        assert Astro.duration_of_daylight(@location, date) == {:error, :invalid_date}
      end
    end
  end

  describe "new moon and phase searches" do
    test "return errors for an invalid date" do
      for date <- @not_dates do
        assert Astro.date_time_new_moon_before(date) == {:error, :invalid_date}
        assert Astro.date_time_new_moon_nearest(date) == {:error, :invalid_date}
        assert Astro.date_time_new_moon_at_or_after(date) == {:error, :invalid_date}
        assert Astro.date_time_lunar_phase_at_or_before(date, 90.0) == {:error, :invalid_date}
        assert Astro.date_time_lunar_phase_at_or_after(date, 90.0) == {:error, :invalid_date}
      end
    end

    test "return an error for a phase that is not from 0 to 360" do
      for phase <- [nil, "", :"", "90", -1, 360.5, 1.0e300] do
        assert Astro.date_time_lunar_phase_at_or_before(@date, phase) == {:error, :invalid_phase}
        assert Astro.date_time_lunar_phase_at_or_after(@date, phase) == {:error, :invalid_phase}
      end
    end
  end

  describe "crescent visibility" do
    test "returns errors for an invalid location, date, method or options" do
      for location <- @not_locations do
        assert Astro.new_visible_crescent(location, @date) == {:error, :invalid_location}

        assert Astro.new_visible_crescent(location, @date, :schaefer, []) ==
                 {:error, :invalid_location}
      end

      for date <- @not_dates do
        assert Astro.new_visible_crescent(@location, date) == {:error, :invalid_date}
      end

      for method <- [nil, "", :"", :odeh_2006, "odeh"] do
        assert Astro.new_visible_crescent(@location, @date, method) == {:error, :invalid_method}
      end

      assert Astro.new_visible_crescent(@location, @date, :odeh, []) == {:error, :invalid_method}

      for options <- @not_options do
        assert Astro.new_visible_crescent(@location, @date, :schaefer, options) ==
                 {:error, :invalid_options}
      end
    end
  end
end
