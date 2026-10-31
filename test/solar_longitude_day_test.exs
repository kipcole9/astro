defmodule Astro.SolarLongitudeDayTest do
  use ExUnit.Case, async: true

  alias Astro.{Math, Solar}

  @beijing_switch Date.to_gregorian_days(~D[1929-01-01])

  defp beijing(moment) do
    if moment < @beijing_switch do
      1397 / 180 / 24
    else
      8 / 24
    end
  end

  defp offset_at(offset, moment) when is_function(offset, 1), do: offset.(moment)
  defp offset_at(offset, _moment), do: offset

  defp day(date), do: Date.to_gregorian_days(date)

  # The local day of the crossing found to its moment: at or after local
  # midnight starting `day`, or the last before local midnight ending it.
  defp moment_day_on_or_after(lambda, day, offset) do
    crossing = Solar.solar_ecliptic_longitude_after(lambda, day - offset_at(offset, day))
    floor(crossing + offset_at(offset, crossing))
  end

  defp moment_day_on_or_before(lambda, day, offset) do
    finish = day + 1 - offset_at(offset, day + 1)
    degrees = Math.mod(Solar.solar_ecliptic_longitude(finish) - lambda, 360)
    estimate = finish - 365.242189 / 360 * degrees

    crossing =
      Math.invert_angular(
        &Solar.solar_ecliptic_longitude/1,
        lambda,
        estimate - 5,
        min(finish, estimate + 5),
        1.0e-9
      )

    floor(crossing + offset_at(offset, crossing))
  end

  describe "solar_longitude_day_on_or_after/3 and solar_longitude_day_on_or_before/3" do
    test "are the local days of the crossings found to their moments" do
      days =
        for i <- 0..159 do
          day(~D[2000-01-01]) + round((i - 80) * 40_000 * 365.2425 / 80) + rem(i * 13, 365)
        end ++ Enum.to_list(day(~D[1926-01-01])..day(~D[1932-01-01])//23)

      for offset <- [0.0, 8 / 24, -8 / 24, &beijing/1],
          lambda <- [0, 90, 180, 270, 315],
          day <- days do
        after_day = Solar.solar_longitude_day_on_or_after(lambda, day, offset)
        before_day = Solar.solar_longitude_day_on_or_before(lambda, day, offset)

        assert after_day == moment_day_on_or_after(lambda, day, offset)
        assert before_day == moment_day_on_or_before(lambda, day, offset)
        assert after_day >= day
        assert before_day <= day
      end
    end

    # Within seconds of midnight in UTC+8: 300° at 23:59:56 on 1979-01-20 and
    # 270° at 00:00:05 on 1951-12-23.
    test "decide crossings within seconds of local midnight" do
      assert Solar.solar_longitude_day_on_or_after(300, day(~D[1979-01-10]), 8 / 24) ==
               day(~D[1979-01-20])

      assert Solar.solar_longitude_day_on_or_before(270, day(~D[1952-01-10]), 8 / 24) ==
               day(~D[1951-12-23])
    end

    # 15,600 years before present the Sun moves at 0.9487° a day near the
    # September equinox, slower than any rate it reaches today.
    test "hold where the Sun moves more slowly than it does today" do
      {:ok, date} = Date.new(-15_600, 12, 23)
      day = day(date)

      assert Solar.solar_longitude_day_on_or_after(180, day, 0.0) ==
               moment_day_on_or_after(180, day, 0.0)
    end

    test "the December solstice of 2024 in Beijing" do
      assert Solar.solar_longitude_day_on_or_before(270, day(~D[2025-03-01]), 8 / 24) ==
               day(~D[2024-12-21])

      assert Solar.solar_longitude_day_on_or_after(270, day(~D[2024-12-21]), 8 / 24) ==
               day(~D[2024-12-21])
    end
  end
end
