defmodule Astro.EquinoxSolsticeInputTest do
  use ExUnit.Case, async: true

  @not_years [nil, "", :"", 2024.0, "2024", %{}, [], {2024}, :march]
  @not_events [nil, "", :"", :april, "march", 3, %{}, [], {:march}]

  describe "an invalid year" do
    test "is an error, not an exception" do
      for year <- @not_years do
        assert Astro.equinox(year, :march) == {:error, :invalid_year}
        assert Astro.solstice(year, :june) == {:error, :invalid_year}
      end
    end
  end

  describe "an invalid event" do
    test "is an error, not an exception" do
      for event <- @not_events do
        assert Astro.equinox(2024, event) == {:error, :invalid_event}
        assert Astro.solstice(2024, event) == {:error, :invalid_event}
      end
    end

    test "a solstice is not an equinox, nor the reverse" do
      assert Astro.equinox(2024, :june) == {:error, :invalid_event}
      assert Astro.solstice(2024, :march) == {:error, :invalid_event}
    end
  end

  describe "invalid options" do
    test "are an error, not an exception" do
      for options <- [nil, "", :"", %{}, [time_zone: nil], [time_zone: :"Asia/Tokyo"]] do
        assert {:error, _reason} = Astro.equinox(2024, :march, options)
        assert {:error, _reason} = Astro.solstice(2024, :june, options)
      end
    end
  end

  describe "the range of years" do
    test "is 50,000 years either side of 2000" do
      assert {:ok, _march} = Astro.equinox(-48_000, :march)
      assert {:ok, _december} = Astro.solstice(52_000, :december)

      for year <- [-48_001, 52_001, 1_000_000, -1_000_000, 1_000_000_000_000] do
        assert Astro.equinox(year, :september) == {:error, :year_out_of_range}
        assert Astro.solstice(year, :june) == {:error, :year_out_of_range}
      end
    end

    # The search starts ΔT before the event's month, so it finds the event
    # of the requested year even where ΔT is weeks; in 2.10.0 development the
    # March equinox of −50,000 was found in November.
    test "far in the past, the event is in its month in dynamical time" do
      for year <- [-48_000, -40_000, -30_000, -20_000] do
        assert {:ok, equinox} = Astro.equinox(year, :march)

        dynamical_time =
          equinox
          |> Astro.Time.date_time_to_moment()
          |> Astro.Time.dynamical_from_universal()

        assert {:ok, %DateTime{year: ^year, month: month}} =
                 Astro.Time.date_time_from_moment(dynamical_time)

        assert month in 3..4
      end
    end
  end
end
