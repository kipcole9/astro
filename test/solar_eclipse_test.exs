defmodule Astro.SolarEclipseTest do
  use ExUnit.Case, async: true

  doctest Astro.Solar.Eclipse
  doctest Astro.Saros

  # The oracle is NASA's Five Millennium Catalog of Solar Eclipses
  # (Espenak and Meeus), https://eclipse.gsfc.nasa.gov/SEcat5/SEcatalog.html:
  # every eclipse of 1901 to 2100, and every fourth eclipse of four more
  # centuries. NASA computes from VSOP87 and ELP-2000/82, so instants are
  # compared in Terrestrial Time, where ΔT does not enter. Dates before
  # 15 October 1582 are in the Julian calendar.

  @data_dir Path.join([__DIR__, "data", "solar_eclipses"])

  # Tolerances per century: greatest eclipse in seconds, gamma and the
  # magnitude. NASA rounds instants to the second and gamma and
  # magnitudes to 0.0001; beyond the JPL ephemeris the tolerances are
  # those of the series.
  @centuries [
    {"SE1901-2000.csv", %{seconds: 2, gamma: 1.5e-4, magnitude: 1.5e-4}},
    {"SE2001-2100.csv", %{seconds: 2, gamma: 1.5e-4, magnitude: 1.5e-4}},
    {"SE1801-1900.csv", %{seconds: 20, gamma: 1.5e-3, magnitude: 2.0e-3}},
    {"SE2901-3000.csv", %{seconds: 45, gamma: 1.5e-3, magnitude: 2.0e-3}},
    {"SE0001-0100.csv", %{seconds: 90, gamma: 1.5e-3, magnitude: 2.0e-3}},
    {"SE-0999--0900.csv", %{seconds: 150, gamma: 1.5e-3, magnitude: 2.0e-3}}
  ]

  @j2000_moment 730_485.5

  # The Earth turns 360.9856° in a day of Universal Time.
  @sidereal_degrees_per_day 360.98564736629

  for {file, tolerance} <- @centuries do
    @file_name file
    @tolerance tolerance

    test "agrees with NASA's catalogue in #{file}" do
      for row <- rows(@file_name) do
        assert_agrees(row, @tolerance)
      end
    end
  end

  # NASA's polynomial elements for 8 April 2024 from t0 = 18:00 TD,
  # https://eclipse.gsfc.nasa.gov/SEbeselm/SEbeselm2001/SE2024Apr08Tbeselm.html.
  # NASA's μ is the ephemeris hour angle, as if TD were UT; Astro's is
  # the Greenwich hour angle at the moment, ΔT's rotation behind it.
  test "the Besselian elements agree with NASA's for 8 April 2024" do
    td_t0 = Date.to_gregorian_days(~D[2024-04-08]) + 0.75

    nasa = %{
      x: [-0.318157, 0.5117105, 0.0000326, -0.0000085],
      y: [0.219747, 0.2709586, -0.0000594, -0.0000047],
      d: [7.58620, 0.014844, -0.000002],
      l1: [0.535813, 0.0000618, -0.0000128],
      l2: [-0.010274, 0.0000615, -0.0000127],
      mu: [89.59122, 15.004084]
    }

    for hours <- [-3, -1.5, 0, 1.5, 3] do
      td = td_t0 + hours / 24
      t = Astro.Time.dynamical_time_to_moment((td - @j2000_moment) * 86_400)
      elements = Astro.Solar.Eclipse.elements(t)
      expected = Map.new(nasa, fn {key, terms} -> {key, polynomial(terms, hours)} end)

      assert_in_delta elements.x, expected.x, 2.0e-4
      assert_in_delta elements.y, expected.y, 5.0e-5
      assert_in_delta elements.d, expected.d, 1.0e-4
      assert_in_delta elements.l1, expected.l1, 1.0e-5
      assert_in_delta elements.l2, expected.l2, 1.0e-5
      assert_in_delta elements.tan_f1, 0.0046683, 1.0e-6
      assert_in_delta elements.tan_f2, 0.0046450, 1.0e-6

      delta_t_rotation = (td - t) * @sidereal_degrees_per_day
      assert_in_delta elements.mu + delta_t_rotation, expected.mu, 2.0e-3
    end
  end

  test "finds the eclipse before a date and after it" do
    assert {:ok, %Astro.Solar.Eclipse{type: :annular, greatest: greatest}} =
             Astro.solar_eclipse_before(~D[2024-04-01])

    assert DateTime.to_date(greatest) == ~D[2023-10-14]

    # Found from the other side, the same eclipse to within the searches'
    # millisecond.
    {:ok, after_it} = Astro.solar_eclipse_at_or_after(DateTime.add(greatest, -1, :second))
    assert abs(DateTime.diff(after_it.greatest, greatest, :microsecond)) < 1_000
  end

  test "finds hybrid eclipses" do
    for date <- [~D[2005-04-01], ~D[2013-11-01], ~D[2023-04-15]] do
      assert {:ok, %Astro.Solar.Eclipse{type: :hybrid}} = Astro.solar_eclipse_at_or_after(date)
    end
  end

  test "is an error for a bad date or year" do
    assert Astro.solar_eclipse_at_or_after(:not_a_date) == {:error, :invalid_date}
    assert Astro.solar_eclipse_before(:not_a_date) == {:error, :invalid_date}

    {:ok, far} = Date.new(60_000, 1, 1)
    assert Astro.solar_eclipse_at_or_after(far) == {:error, :year_out_of_range}
    assert Astro.solar_eclipse_before(far) == {:error, :year_out_of_range}
  end

  defp assert_agrees(row, tolerance) do
    {:ok, eclipse} = Astro.Solar.Eclipse.eclipse_at_or_after(row.td - 1.0)
    label = "#{row.year}-#{row.month}-#{row.day}"

    assert abs(terrestrial_time(eclipse.greatest) - row.td) * 86_400 <= tolerance.seconds, label
    assert eclipse.type == row.type, label
    assert_in_delta eclipse.gamma, row.gamma, tolerance.gamma, label
    assert_in_delta eclipse.magnitude, row.magnitude, tolerance.magnitude, label
    assert eclipse.saros == row.saros, label

    lunation = Astro.Lunar.lunation_at(eclipse.greatest + Astro.Time.mean_synodic_month() / 2)
    assert lunation == row.lunation, label
  end

  defp polynomial(terms, hours) do
    terms
    |> Enum.with_index()
    |> Enum.map(fn {term, power} -> term * :math.pow(hours, power) end)
    |> Enum.sum()
  end

  defp terrestrial_time(moment) do
    @j2000_moment + Astro.Time.dynamical_time_from_moment(moment) / 86_400
  end

  defp rows(file) do
    [_header | lines] =
      @data_dir
      |> Path.join(file)
      |> File.read!()
      |> String.split("\n", trim: true)

    Enum.map(lines, &row/1)
  end

  defp row(line) do
    [year, month, day, td, _delta_t, lunation, saros, type, gamma, magnitude | _rest] =
      String.split(line, ",")

    {year, month, day} =
      {String.to_integer(year), String.to_integer(month), String.to_integer(day)}

    [hours, minutes, seconds] =
      td
      |> String.split(":")
      |> Enum.map(&String.to_integer/1)

    %{
      year: year,
      month: month,
      day: day,
      td: days(year, month, day) + (hours * 3_600 + minutes * 60 + seconds) / 86_400,
      type: eclipse_type(String.first(type)),
      gamma: String.to_float(gamma),
      magnitude: String.to_float(magnitude),
      lunation: String.to_integer(lunation),
      saros: String.to_integer(saros)
    }
  end

  defp eclipse_type("P") do
    :partial
  end

  defp eclipse_type("A") do
    :annular
  end

  defp eclipse_type("T") do
    :total
  end

  defp eclipse_type("H") do
    :hybrid
  end

  # Gregorian days of a Julian calendar date before 1582-10-15, and of a
  # Gregorian date after it.
  defp days(year, month, day) when {year, month, day} < {1582, 10, 15} do
    a = div(14 - month, 12)
    y = year + 4_800 - a
    m = month + 12 * a - 3
    day + div(153 * m + 2, 5) + 365 * y + Integer.floor_div(y, 4) - 32_083 - 1_721_060
  end

  defp days(year, month, day) do
    {:ok, date} = Date.new(year, month, day)
    Date.to_gregorian_days(date)
  end
end
