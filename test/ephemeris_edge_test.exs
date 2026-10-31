defmodule Astro.EphemerisEdgeTest do
  use ExUnit.Case, async: true

  # At the edges of the loaded ephemeris (1900 and 2100 for the bundled
  # kernel, 1849 and 2150 for the full one) the positions switch from JPL to
  # the analytical series. The edges are found from the kernel itself, so
  # these tests run against whichever kernel is loaded.

  @sydney {151.20666584, -33.8559799094}
  @half_second 0.5 / 86_400

  # The series' largest differences from JPL over 1900-2100 (see
  # `Astro.AnalyticalSeriesTest`), plus the Moon's motion over a second.
  @sun_tolerance %{longitude: 4.0, right_ascension: 4.5, declination: 2.5}
  @moon_tolerance %{longitude: 20.0, latitude: 6.0, right_ascension: 20.0, declination: 9.0}

  @earliest ~D[1800-01-01]
  @middle ~D[2000-01-01]
  @latest ~D[2200-01-01]

  defp moment(date) do
    Astro.Time.date_time_to_moment(date)
  end

  # The moment the kernel's coverage of a body begins (searching from before
  # it) or ends (searching from after it), by bisection between a moment it
  # does not cover and one it does.
  defp edge(covered?, outside, inside) do
    {_outside, edge} =
      Enum.reduce(1..60, {outside, inside}, fn _step, {uncovered, covered} ->
        middle = (uncovered + covered) / 2

        if covered?.(middle) do
          {uncovered, middle}
        else
          {middle, covered}
        end
      end)

    edge
  end

  defp sun_covered?(t) do
    match?({:ok, _}, Astro.Ephemeris.sun_ecliptic_position(t))
  end

  defp moon_covered?(t) do
    match?({:ok, _}, Astro.Ephemeris.moon_ecliptic_position(t))
  end

  defp edges(covered?) do
    [
      start: edge(covered?, moment(@earliest), moment(@middle)),
      end: edge(covered?, moment(@latest), moment(@middle))
    ]
  end

  # Moments half a second inside and half a second beyond an edge.
  defp either_side(:start, edge) do
    {edge + @half_second, edge - @half_second}
  end

  defp either_side(:end, edge) do
    {edge - @half_second, edge + @half_second}
  end

  defp arcseconds(a, b) do
    difference = a - b
    abs(difference - 360.0 * Float.round(difference / 360.0)) * 3600.0
  end

  defp sun_position(t) do
    {right_ascension, declination, _distance} = Astro.Solar.solar_position(t)

    %{
      longitude: Astro.Solar.solar_ecliptic_longitude(t),
      right_ascension: right_ascension,
      declination: declination
    }
  end

  defp moon_position(t) do
    {right_ascension, declination, _distance} = Astro.Lunar.lunar_position(t)

    %{
      longitude: Astro.Lunar.lunar_ecliptic_longitude(t),
      latitude: Astro.Lunar.lunar_latitude(t),
      right_ascension: right_ascension,
      declination: declination
    }
  end

  describe "positions are continuous across the edges of the ephemeris" do
    test "for the Sun" do
      for {side, edge} <- edges(&sun_covered?/1) do
        {inside, beyond} = either_side(side, edge)
        assert sun_covered?(inside) and not sun_covered?(beyond)

        inside_position = sun_position(inside)
        beyond_position = sun_position(beyond)

        for {coordinate, tolerance} <- @sun_tolerance do
          assert arcseconds(inside_position[coordinate], beyond_position[coordinate]) < tolerance,
                 "the Sun's #{coordinate} jumps at the #{side} of the ephemeris"
        end
      end
    end

    test "for the Moon" do
      for {side, edge} <- edges(&moon_covered?/1) do
        {inside, beyond} = either_side(side, edge)
        assert moon_covered?(inside) and not moon_covered?(beyond)

        inside_position = moon_position(inside)
        beyond_position = moon_position(beyond)

        for {coordinate, tolerance} <- @moon_tolerance do
          assert arcseconds(inside_position[coordinate], beyond_position[coordinate]) < tolerance,
                 "the Moon's #{coordinate} jumps at the #{side} of the ephemeris"
        end
      end
    end
  end

  # A rise or set can legitimately not happen on a UTC day: the Moon rises
  # and sets about 50 minutes later each day, so once a month it skips one.
  @rise_and_set [:sunrise, :sunset, :moonrise, :moonset]

  defp calls do
    [
      sunrise: &Astro.sunrise(@sydney, &1, time_zone: :utc),
      sunset: &Astro.sunset(@sydney, &1, time_zone: :utc),
      moonrise: &Astro.moonrise(@sydney, &1, time_zone: :utc),
      moonset: &Astro.moonset(@sydney, &1, time_zone: :utc),
      solar_noon: &Astro.solar_noon(@sydney, &1),
      sun_position_at: &Astro.sun_position_at/1,
      moon_position_at: &Astro.moon_position_at/1,
      sun_azimuth_elevation:
        &Astro.sun_azimuth_elevation(@sydney, DateTime.new!(&1, ~T[03:00:00], "Etc/UTC")),
      lunar_phase_at: &Astro.lunar_phase_at/1,
      illuminated_fraction_of_moon_at: &Astro.illuminated_fraction_of_moon_at/1,
      date_time_new_moon_before: &Astro.date_time_new_moon_before/1,
      date_time_new_moon_at_or_after: &Astro.date_time_new_moon_at_or_after/1,
      date_time_new_moon_nearest: &Astro.date_time_new_moon_nearest/1,
      date_time_lunar_phase_at_or_before: &Astro.date_time_lunar_phase_at_or_before(&1, 90.0),
      date_time_lunar_phase_at_or_after: &Astro.date_time_lunar_phase_at_or_after(&1, 270.0),
      sun_apparent_longitude: &Astro.sun_apparent_longitude/1,
      new_visible_crescent: &Astro.new_visible_crescent(@sydney, &1)
    ]
  end

  defp answered?(name, {:error, :no_time}) do
    name in @rise_and_set
  end

  defp answered?(_name, {:error, _reason}) do
    false
  end

  defp answered?(_name, _result) do
    true
  end

  test "every function answers on the days either side of each edge" do
    edges = edges(&sun_covered?/1) ++ edges(&moon_covered?/1)

    for {_side, edge} <- edges,
        {:ok, %DateTime{} = at_edge} = Astro.Time.date_time_from_moment(edge),
        day <-
          Date.range(
            Date.add(DateTime.to_date(at_edge), -3),
            Date.add(DateTime.to_date(at_edge), 3)
          ),
        {name, call} <- calls() do
      result = call.(day)
      assert answered?(name, result), "#{name} on #{day} returned #{inspect(result)}"
    end
  end
end
