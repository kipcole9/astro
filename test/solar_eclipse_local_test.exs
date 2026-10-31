defmodule Astro.SolarEclipseLocalTest do
  use ExUnit.Case, async: true

  doctest Astro.Solar.Eclipse.Local

  # The oracle is the USNO's solar eclipse computer,
  # https://aa.usno.navy.mil/data/SolarEclipses, for 17 eclipses and
  # places from 1999 to 2026 and two places that see no eclipse. Its
  # times are in UT with its own ΔT, which differs from Astro's by up to
  # 4.6 s. A larger ΔT turns the Earth further behind the shadow, the
  # same as moving the observer west by the Earth's rotation in that
  # time and reporting every instant that much earlier, so the
  # comparison does exactly that and is free of ΔT.

  @usno Path.join([__DIR__, "data", "solar_eclipses", "usno_local.csv"])

  @j2000_moment 730_485.5

  # The Earth turns 360.9856° in a day of Universal Time.
  @sidereal_degrees_per_second 360.98564736629 / 86_400

  # Tolerances in seconds. The USNO's maximum is a second before the
  # midpoint of its own second and third contacts, and its Moon is a
  # little larger than NASA's for the umbra, which moves the contacts of
  # totality and annularity by about a second each.
  @tolerance %{
    partial_begins: 1.5,
    partial_ends: 1.5,
    maximum: 1.5,
    total_begins: 2.5,
    total_ends: 2.5,
    annular_begins: 2.5,
    annular_ends: 2.5
  }

  # Singapore was near the edge of the 2019 annular path, where the
  # contacts of annularity move by seconds for a small change in the
  # shadow's size.
  @near_the_edge {"2019-12-26", :annular}
  @near_the_edge_tolerance 5.0

  test "agrees with the USNO's local circumstances" do
    for {place, rows} <- usno_cases() do
      assert_agrees(place, rows)
    end
  end

  test "the same eclipse from a date or from the eclipse" do
    {:ok, eclipse} = Astro.solar_eclipse_at_or_after(~D[2024-04-01])
    {:ok, from_date} = Astro.solar_eclipse_at({-96.80, 32.78}, ~D[2024-04-01], time_zone: :utc)
    {:ok, from_eclipse} = Astro.solar_eclipse_at({-96.80, 32.78}, eclipse, time_zone: :utc)

    # Found by searches from different moments, to within their millisecond.
    assert from_date.type == from_eclipse.type
    assert abs(DateTime.diff(from_date.maximum, from_eclipse.maximum, :microsecond)) < 1_000
  end

  test "the contacts are in order and in the requested time zone" do
    {:ok, local} =
      Astro.solar_eclipse_at({-96.80, 32.78}, ~D[2024-04-01], time_zone: "America/Chicago")

    contacts = [
      local.partial_begins,
      local.total_begins,
      local.maximum,
      local.total_ends,
      local.partial_ends
    ]

    assert contacts == Enum.sort(contacts, DateTime)
    assert Enum.all?(contacts, &(&1.time_zone == "America/Chicago"))
    assert is_nil(local.annular_begins) and is_nil(local.annular_ends)
    altitudes = Map.keys(local.sun_altitudes)
    assert Enum.sort(altitudes) == Enum.sort(contact_names(local))
  end

  test "a contact before sunrise has a negative altitude" do
    {:ok, local} = Astro.solar_eclipse_at({-79.38, 43.65}, ~D[2021-06-10], time_zone: :utc)

    assert local.type == :partial
    assert local.sun_altitudes.partial_begins < 0.0
    assert local.sun_altitudes.partial_ends > 0.0
  end

  test "is an error for a bad location, date or option" do
    assert Astro.solar_eclipse_at({200.0, 0.0}, ~D[2024-04-01]) == {:error, :invalid_location}
    assert Astro.solar_eclipse_at({0.0, 0.0}, :not_a_date) == {:error, :invalid_date}
    assert Astro.solar_eclipse_at({0.0, 0.0}, ~D[2024-04-01], :none) == {:error, :invalid_options}

    assert Astro.solar_eclipse_at({-96.80, 32.78}, ~D[2024-04-01], time_zone: :none) ==
             {:error, :time_zone_not_found}

    {:ok, far} = Date.new(60_000, 1, 1)
    assert Astro.solar_eclipse_at({0.0, 0.0}, far) == {:error, :year_out_of_range}
  end

  defp assert_agrees(place, [%{type: :none}]) do
    {date, latitude, longitude, height} = place
    {:ok, eclipse} = eclipse_on(date)
    point = %Geo.PointZ{coordinates: {longitude, latitude, height}}

    assert Astro.Solar.Eclipse.Local.circumstances(eclipse.greatest, point) ==
             {:error, :not_visible},
           inspect(place)
  end

  defp assert_agrees(place, [first | _rest] = rows) do
    {date, latitude, longitude, height} = place
    {:ok, eclipse} = eclipse_on(date)
    delta = first.delta_t - delta_t(eclipse.greatest)
    shifted = longitude - @sidereal_degrees_per_second * delta
    point = %Geo.PointZ{coordinates: {shifted, latitude, height}}
    label = inspect(place)

    {:ok, local} = Astro.Solar.Eclipse.Local.circumstances(eclipse.greatest, point)

    assert local.type == first.type, label
    assert_in_delta local.magnitude, first.magnitude, 1.0e-3, label
    assert_in_delta local.obscuration, first.obscuration, 2.0e-3, label

    for row <- rows do
      seconds = (Map.fetch!(local, row.contact) - row.moment) * 86_400 - delta
      assert abs(seconds) <= tolerance(date, local.type, row.contact), "#{label} #{row.contact}"

      assert_in_delta local.sun_altitudes[row.contact],
                      row.altitude,
                      0.1,
                      "#{label} #{row.contact}"
    end
  end

  defp tolerance(date, type, contact) when contact in [:annular_begins, :annular_ends] do
    if {date, type} == @near_the_edge do
      @near_the_edge_tolerance
    else
      Map.fetch!(@tolerance, contact)
    end
  end

  defp tolerance(_date, _type, contact) do
    Map.fetch!(@tolerance, contact)
  end

  defp contact_names(local) do
    [
      :partial_begins,
      :annular_begins,
      :total_begins,
      :maximum,
      :total_ends,
      :annular_ends,
      :partial_ends
    ]
    |> Enum.reject(&is_nil(Map.fetch!(local, &1)))
  end

  defp eclipse_on(date) do
    days = Date.to_gregorian_days(Date.from_iso8601!(date))
    Astro.Solar.Eclipse.eclipse_at_or_after(days - 0.5)
  end

  defp delta_t(moment) do
    (@j2000_moment + Astro.Time.dynamical_time_from_moment(moment) / 86_400 - moment) * 86_400
  end

  defp usno_cases do
    [_header | lines] =
      @usno
      |> File.read!()
      |> String.split("\n", trim: true)

    lines
    |> Enum.map(&row/1)
    |> Enum.chunk_by(& &1.place)
    |> Enum.map(fn [%{place: place} | _] = rows -> {place, rows} end)
  end

  defp row(line) do
    [date, latitude, longitude, height, delta_t, type, magnitude, obscuration | contact] =
      String.split(line, ",")

    place =
      {date, String.to_float(latitude), String.to_float(longitude),
       String.to_integer(height) * 1.0}

    if type == "none" do
      %{place: place, type: :none}
    else
      [name, contact_date, time, altitude] = contact

      %{
        place: place,
        delta_t: String.to_float(delta_t),
        type: String.to_existing_atom(type),
        magnitude: String.to_float(magnitude),
        obscuration: String.to_float(obscuration) / 100,
        contact: String.to_existing_atom(name),
        moment: moment(contact_date, time),
        altitude: String.to_float(altitude)
      }
    end
  end

  defp moment(date, time) do
    [hours, minutes, seconds] = String.split(time, ":")
    days = Date.to_gregorian_days(Date.from_iso8601!(date))

    days +
      (String.to_integer(hours) * 3_600 + String.to_integer(minutes) * 60 +
         String.to_float(seconds)) / 86_400
  end
end
