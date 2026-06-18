defmodule Astro.HoursOfDaylightTest do
  use ExUnit.Case, async: true

  # Fairbanks, Alaska — 64.84°N, just below the Arctic Circle (~66.56°N).
  @fairbanks {-147.7164, 64.8378}

  # Sydney, Australia — a normal mid-latitude location.
  @sydney {151.20666584, -33.8559799094}

  # Alert, Nunavut, Canada — 82.5°N, deep inside the Arctic Circle.
  @alert {-62.3481, 82.5018}

  describe "normal latitudes" do
    test "returns sunset minus sunrise for an ordinary day" do
      assert {:ok, ~T[14:19:29]} = Astro.hours_of_daylight(@sydney, ~D[2019-12-08])
    end
  end

  describe "sub-polar latitudes near the summer solstice (issue #11)" do
    # On these days the Sun sets shortly after local midnight and rises again
    # a few hours later, so the day's sunset precedes its sunrise. Before the
    # fix this returned {:error, :invalid_time}.
    test "the reported Fairbanks case returns the correct daylight" do
      assert {:ok, ~T[21:34:55]} = Astro.hours_of_daylight(@fairbanks, ~D[2026-06-13])
    end

    test "every day across the solstice window returns a valid Time" do
      for date <- Date.range(~D[2026-05-31], ~D[2026-07-15]) do
        assert {:ok, %Time{} = time} = Astro.hours_of_daylight(@fairbanks, date),
               "expected a valid Time for #{date}"

        # The Sun is up for most of the day but still sets, so daylight is
        # long but strictly less than 24 hours.
        assert Time.compare(time, ~T[19:00:00]) == :gt
        assert Time.compare(time, ~T[23:59:59]) == :lt
      end
    end

    test "daylight peaks at the solstice and is symmetric around it" do
      {:ok, before_solstice} = Astro.hours_of_daylight(@fairbanks, ~D[2026-06-10])
      {:ok, at_solstice} = Astro.hours_of_daylight(@fairbanks, ~D[2026-06-20])
      {:ok, after_solstice} = Astro.hours_of_daylight(@fairbanks, ~D[2026-06-30])

      assert Time.compare(at_solstice, before_solstice) == :gt
      assert Time.compare(at_solstice, after_solstice) == :gt
    end
  end

  describe "polar day and polar night" do
    test "polar day reports 24 hours capped to 23:59:59" do
      assert {:ok, ~T[23:59:59]} = Astro.hours_of_daylight(@alert, ~D[2019-06-07])
    end

    test "polar night reports zero" do
      assert {:ok, ~T[00:00:00]} = Astro.hours_of_daylight(@alert, ~D[2019-12-07])
    end
  end

  describe "time zone resolution failures" do
    test "propagates :time_zone_not_found when the location has no resolvable zone" do
      # A point in the open ocean has no TzWorld time zone.
      assert {:error, :time_zone_not_found} = Astro.hours_of_daylight({0.0, 0.0}, ~D[2026-06-13])
    end
  end

  # `duration_of_daylight/2` is only defined on Elixir 1.17+, so the tests are
  # compiled only when the `Duration` module is available.
  if Code.ensure_loaded?(Duration) do
    describe "duration_of_daylight/2" do
      test "returns the same value as hours_of_daylight/2 for an ordinary day" do
        assert {:ok, %Duration{hour: 14, minute: 19, second: 29}} =
                 Astro.duration_of_daylight(@sydney, ~D[2019-12-08])
      end

      test "handles the sub-polar reversed-event case (issue #11)" do
        assert {:ok, %Duration{hour: 21, minute: 34, second: 55}} =
                 Astro.duration_of_daylight(@fairbanks, ~D[2026-06-13])
      end

      test "reports a full, uncapped 24 hours for polar day" do
        assert {:ok, %Duration{hour: 24} = duration} =
                 Astro.duration_of_daylight(@alert, ~D[2019-06-07])

        # Unlike hours_of_daylight/2 which caps at ~T[23:59:59].
        assert Duration.to_string(duration) == "24h"
      end

      test "reports zero for polar night" do
        assert {:ok, %Duration{} = duration} =
                 Astro.duration_of_daylight(@alert, ~D[2019-12-07])

        assert Duration.to_string(duration) == "0s"
      end

      test "agrees with hours_of_daylight/2 across the solstice window" do
        for date <- Date.range(~D[2026-05-31], ~D[2026-07-15]) do
          {:ok, %Time{} = time} = Astro.hours_of_daylight(@fairbanks, date)
          {:ok, %Duration{} = duration} = Astro.duration_of_daylight(@fairbanks, date)

          assert {duration.hour, duration.minute, duration.second} ==
                   {time.hour, time.minute, time.second},
                 "mismatch for #{date}"
        end
      end

      test "propagates :time_zone_not_found when the location has no resolvable zone" do
        assert {:error, :time_zone_not_found} =
                 Astro.duration_of_daylight({0.0, 0.0}, ~D[2026-06-13])
      end
    end
  end
end
