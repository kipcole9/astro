defmodule Astro.LunarEclipseLocalTest do
  use ExUnit.Case, async: true

  doctest Astro.Lunar.Eclipse.Local

  # There is no published oracle for the Moon's altitude at a lunar
  # eclipse's contacts, so the altitude is checked against Astro's
  # moonrise and moonset, which are tested against the USNO and
  # Skyfield: at those instants the Moon's centre is 34′ of refraction
  # and its semi-diameter below the horizon.

  @places [
    {{-0.13, 51.5, 0.0}, ~D[2025-03-14]},
    {{151.21, -33.87, 0.0}, ~D[2025-03-14]},
    {{-96.80, 32.78, 1_000.0}, ~D[2025-09-07]},
    {{139.69, 35.68, 0.0}, ~D[2025-09-07]},
    {{18.42, -33.92, 0.0}, ~D[2026-03-03]}
  ]

  @horizon_refraction 34 / 60

  # A minute, in days.
  @minute 1 / 1_440

  test "the Moon's altitude at moonrise and moonset is the horizon" do
    for {coordinates, date} <- @places, event <- [:moonrise, :moonset] do
      {:ok, date_time} = apply(Astro, event, [coordinates, date, [time_zone: :utc]])
      t = Astro.Time.date_time_to_moment(date_time)
      horizon = -(@horizon_refraction + Astro.Lunar.angular_semi_diameter(t))

      assert_in_delta altitude_at(coordinates, t), horizon, 1.0e-4, inspect({coordinates, event})
    end
  end

  test "an eclipse is seen if the Moon has risen before its last contact" do
    coordinates = {-0.13, 51.5, 0.0}
    point = %Geo.PointZ{coordinates: coordinates}
    {:ok, date_time} = Astro.moonrise(coordinates, ~D[2025-03-14], time_zone: :utc)
    moonrise = Astro.Time.date_time_to_moment(date_time)

    before_moonrise = eclipse_between(moonrise - 120 * @minute, moonrise - @minute)
    after_moonrise = eclipse_between(moonrise - 120 * @minute, moonrise + @minute)

    assert Astro.Lunar.Eclipse.Local.circumstances(before_moonrise, point) ==
             {:error, :not_visible}

    assert {:ok, _local} = Astro.Lunar.Eclipse.Local.circumstances(after_moonrise, point)
  end

  test "an eclipse the Moon rises during is seen, its earlier contacts below the horizon" do
    {:ok, local} = Astro.lunar_eclipse_at({151.21, -33.87}, ~D[2025-03-01], time_zone: :utc)

    assert local.moon_altitudes.penumbral_begins < 0.0
    assert local.moon_altitudes.penumbral_ends > 0.0
  end

  test "the same eclipse from a date or from the eclipse, in the requested time zone" do
    {:ok, eclipse} = Astro.lunar_eclipse_at_or_after(~D[2025-03-01])
    options = [time_zone: "America/Chicago"]
    {:ok, from_date} = Astro.lunar_eclipse_at({-96.80, 32.78}, ~D[2025-03-01], options)
    {:ok, from_eclipse} = Astro.lunar_eclipse_at({-96.80, 32.78}, eclipse, options)

    # Found by searches from different moments, to within their millisecond.
    assert from_date.type == from_eclipse.type
    assert abs(DateTime.diff(from_date.greatest, from_eclipse.greatest, :microsecond)) < 1_000
    assert from_date.greatest.time_zone == "America/Chicago"
    assert map_size(from_date.moon_altitudes) == 7
  end

  test "Chauvenet's shadow is used where asked" do
    {:ok, danjon} = Astro.lunar_eclipse_at({-96.80, 32.78}, ~D[2025-03-01], time_zone: :utc)

    {:ok, chauvenet} =
      Astro.lunar_eclipse_at({-96.80, 32.78}, ~D[2025-03-01],
        time_zone: :utc,
        shadow: :chauvenet
      )

    assert chauvenet.umbral_magnitude > danjon.umbral_magnitude
  end

  test "is an error for a bad location, date or option" do
    assert Astro.lunar_eclipse_at({200.0, 0.0}, ~D[2025-03-01]) == {:error, :invalid_location}
    assert Astro.lunar_eclipse_at({0.0, 0.0}, :not_a_date) == {:error, :invalid_date}
    assert Astro.lunar_eclipse_at({0.0, 0.0}, ~D[2025-03-01], :none) == {:error, :invalid_options}

    assert Astro.lunar_eclipse_at({0.0, 0.0}, ~D[2025-03-01], shadow: :none) ==
             {:error, :invalid_shadow}

    assert Astro.lunar_eclipse_at({-96.80, 32.78}, ~D[2025-03-01], time_zone: :none) ==
             {:error, :time_zone_not_found}

    {:ok, far} = Date.new(60_000, 1, 1)
    assert Astro.lunar_eclipse_at({0.0, 0.0}, far) == {:error, :year_out_of_range}
  end

  # The local circumstances of an eclipse that is all greatest eclipse,
  # which gives the Moon's altitude at one moment.
  defp altitude_at({longitude, latitude, height}, t) do
    eclipse = eclipse_between(t, t)
    point = %Geo.PointZ{coordinates: {longitude, latitude, height}}

    case Astro.Lunar.Eclipse.Local.circumstances(eclipse, point) do
      {:ok, local} -> local.moon_altitudes.greatest
      {:error, :not_visible} -> below_the_horizon(eclipse, point)
    end
  end

  # An eclipse that is not seen has no altitudes; one six hours longer
  # each way, which the Moon is above the horizon for some of, has them
  # all.
  defp below_the_horizon(eclipse, point) do
    seen = %{
      eclipse
      | penumbral_begins: eclipse.penumbral_begins - 0.25,
        penumbral_ends: eclipse.penumbral_ends + 0.25
    }

    {:ok, local} = Astro.Lunar.Eclipse.Local.circumstances(seen, point)
    local.moon_altitudes.greatest
  end

  defp eclipse_between(begins, ends) do
    %{penumbral_begins: begins, greatest: (begins + ends) / 2, penumbral_ends: ends}
  end
end
