defmodule Astro.UtcOffsetAndLimbTest do
  use ExUnit.Case, async: true

  @los_angeles {-118.2437, 34.0522}
  @mecca {39.8262, 21.4225}
  @tokyo {139.6917, 35.6895}

  defp local_date(date_time, utc_offset) do
    date_time
    |> DateTime.add(utc_offset, :second)
    |> DateTime.to_date()
  end

  describe ":utc_offset" do
    # Los Angeles sets at about 20:08 on 20 June, which is 03:08 UTC on the
    # 21st. Asked for the 20th in UTC, sunset is the evening before.
    test "chooses the evening of the local day west of Greenwich" do
      assert {:ok, utc_day} = Astro.sunset(@los_angeles, ~D[2024-06-20], time_zone: :utc)
      assert DateTime.to_date(utc_day) == ~D[2024-06-20]
      assert local_date(utc_day, -8 * 3600) == ~D[2024-06-19]

      assert {:ok, local_day} =
               Astro.sunset(@los_angeles, ~D[2024-06-20], time_zone: :utc, utc_offset: -8 * 3600)

      assert local_date(local_day, -8 * 3600) == ~D[2024-06-20]
      assert DateTime.diff(local_day, utc_day, :hour) in 23..24
    end

    test "chooses the event whose date at the offset is the date asked for" do
      for {location, utc_offset} <- [
            {@los_angeles, -8 * 3600},
            {@tokyo, 9 * 3600},
            {@mecca, 3 * 3600}
          ],
          event <- [:sunrise, :sunset, :moonrise, :moonset],
          date <- [~D[2024-03-10], ~D[2024-06-20], ~D[2024-12-21]] do
        options = [time_zone: :utc, utc_offset: utc_offset]

        case apply(Astro, event, [location, date, options]) do
          {:ok, date_time} -> assert local_date(date_time, utc_offset) == date
          {:error, :no_time} -> :ok
        end
      end
    end

    test "returns the event in the requested time zone" do
      assert {:ok, %DateTime{time_zone: "Asia/Tokyo"} = date_time} =
               Astro.sunrise(@tokyo, ~D[2024-06-20],
                 time_zone: "Asia/Tokyo",
                 utc_offset: 9 * 3600
               )

      assert DateTime.to_date(date_time) == ~D[2024-06-20]
    end

    test "is an error unless it is whole seconds within 14 hours of UTC" do
      for utc_offset <- [15 * 3600, -15 * 3600, 3.5, "+03:00", :utc] do
        for event <- [:sunrise, :sunset, :moonrise, :moonset] do
          assert apply(Astro, event, [
                   @mecca,
                   ~D[2024-06-20],
                   [time_zone: :utc, utc_offset: utc_offset]
                 ]) ==
                   {:error, :invalid_utc_offset}
        end
      end
    end
  end

  describe "limb: :center for the Sun" do
    test "is the Sun's centre at 34′ of refraction, before the upper limb sets" do
      {:ok, upper} = Astro.sunset(@mecca, ~D[2024-06-20], time_zone: :utc)
      {:ok, center} = Astro.sunset(@mecca, ~D[2024-06-20], time_zone: :utc, limb: :center)

      {:ok, by_elevation} =
        Astro.sunset(@mecca, ~D[2024-06-20], time_zone: :utc, solar_elevation: 90 + 34 / 60)

      assert center == by_elevation
      assert DateTime.diff(upper, center, :second) in 60..90
    end

    test "does not change the twilights" do
      for limb <- [:upper, :center] do
        assert Astro.sunset(@mecca, ~D[2024-06-20],
                 time_zone: :utc,
                 solar_elevation: :civil,
                 limb: limb
               ) ==
                 Astro.sunset(@mecca, ~D[2024-06-20], time_zone: :utc, solar_elevation: :civil)
      end
    end

    test "is an error for another limb" do
      assert Astro.sunrise(@mecca, ~D[2024-06-20], time_zone: :utc, limb: :middle) ==
               {:error, :invalid_limb}
    end
  end
end
