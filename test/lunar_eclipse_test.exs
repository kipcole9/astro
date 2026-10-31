defmodule Astro.LunarEclipseTest do
  use ExUnit.Case, async: true

  doctest Astro.Lunar.Eclipse

  # The oracle is NASA's Five Millennium Catalog of Lunar Eclipses
  # (Espenak and Meeus), https://eclipse.gsfc.nasa.gov/LEcat5/LEcatalog.html:
  # every eclipse of 1901 to 2100, and every fourth eclipse of four more
  # centuries. NASA computes from VSOP87 and ELP-2000/82, so instants are
  # compared in Terrestrial Time, where ΔT does not enter. Dates before
  # 15 October 1582 are in the Julian calendar.

  @data_dir Path.join([__DIR__, "data", "lunar_eclipses"])

  # Tolerances per century: greatest eclipse in seconds, gamma, magnitudes,
  # and the durations of the penumbral, partial and total phases in
  # minutes. NASA rounds instants to the second, gamma and magnitudes to
  # 0.0001 and durations to 0.1 minute; beyond the JPL ephemeris the
  # tolerances are those of the series.
  @centuries [
    {"LE1901-2000.csv",
     %{seconds: 4, gamma: 2.0e-4, magnitude: 5.0e-4, minutes: {1.1, 0.1, 0.1}}},
    {"LE2001-2100.csv",
     %{seconds: 4, gamma: 2.0e-4, magnitude: 5.0e-4, minutes: {1.1, 0.1, 0.1}}},
    {"LE1801-1900.csv",
     %{seconds: 20, gamma: 1.5e-3, magnitude: 3.0e-3, minutes: {2.0, 1.0, 1.0}}},
    {"LE2901-3000.csv",
     %{seconds: 45, gamma: 1.5e-3, magnitude: 3.0e-3, minutes: {2.0, 1.0, 1.0}}},
    {"LE0001-0100.csv",
     %{seconds: 90, gamma: 1.5e-3, magnitude: 3.0e-3, minutes: {2.0, 1.0, 1.0}}},
    {"LE-0999--0900.csv",
     %{seconds: 150, gamma: 1.5e-3, magnitude: 3.0e-3, minutes: {2.0, 1.0, 1.0}}}
  ]

  @j2000_moment 730_485.5

  # A phase the Moon barely enters lasts a time that grows as the square
  # root of how far it enters, so a graze, under 0.05 of the Moon's
  # diameter, is only required to happen.
  @graze 0.05

  for {file, tolerance} <- @centuries do
    @file_name file
    @tolerance tolerance

    test "agrees with NASA's catalogue in #{file}" do
      for row <- rows(@file_name) do
        assert_agrees(row, @tolerance)
      end
    end
  end

  test "finds the eclipse before a date and after it" do
    assert {:ok, %Astro.Lunar.Eclipse{type: :partial, greatest: greatest}} =
             Astro.lunar_eclipse_before(~D[2025-03-14])

    assert DateTime.to_date(greatest) == ~D[2024-09-18]

    # Found from the other side, the same eclipse to within the searches'
    # millisecond.
    {:ok, after_it} = Astro.lunar_eclipse_at_or_after(DateTime.add(greatest, -1, :second))
    assert abs(DateTime.diff(after_it.greatest, greatest, :microsecond)) < 1_000
  end

  test "has the contacts of its type, in order" do
    for date <- [~D[2024-03-01], ~D[2024-09-01], ~D[2025-03-01]] do
      {:ok, eclipse} = Astro.lunar_eclipse_at_or_after(date)

      contacts =
        [
          eclipse.penumbral_begins,
          eclipse.partial_begins,
          eclipse.total_begins,
          eclipse.greatest,
          eclipse.total_ends,
          eclipse.partial_ends,
          eclipse.penumbral_ends
        ]
        |> Enum.reject(&is_nil/1)

      assert contacts == Enum.sort(contacts, DateTime)

      expected =
        case eclipse.type do
          :penumbral -> 3
          :partial -> 5
          :total -> 7
        end

      assert length(contacts) == expected
    end
  end

  test "Chauvenet's shadow makes the umbral magnitude larger" do
    {:ok, danjon} = Astro.lunar_eclipse_before(~D[2025-03-14])
    {:ok, chauvenet} = Astro.lunar_eclipse_before(~D[2025-03-14], shadow: :chauvenet)

    assert_in_delta chauvenet.umbral_magnitude - danjon.umbral_magnitude, 0.006, 0.001
  end

  test "is an error for a bad date, option or year" do
    assert Astro.lunar_eclipse_at_or_after(:not_a_date) == {:error, :invalid_date}
    assert Astro.lunar_eclipse_before(~D[2025-03-14], shadow: :none) == {:error, :invalid_shadow}
    assert Astro.lunar_eclipse_before(~D[2025-03-14], :none) == {:error, :invalid_options}

    {:ok, far} = Date.new(60_000, 1, 1)
    assert Astro.lunar_eclipse_at_or_after(far) == {:error, :year_out_of_range}
  end

  defp assert_agrees(row, tolerance) do
    {:ok, eclipse} = Astro.Lunar.Eclipse.eclipse_at_or_after(row.td - 1.0, :danjon)
    label = "#{row.year}-#{row.month}-#{row.day}"

    assert abs(terrestrial_time(eclipse.greatest) - row.td) * 86_400 <= tolerance.seconds, label
    assert eclipse.type == row.type, label
    assert_in_delta eclipse.gamma, row.gamma, tolerance.gamma, label

    assert_in_delta eclipse.penumbral_magnitude,
                    row.penumbral_magnitude,
                    tolerance.magnitude,
                    label

    assert_in_delta eclipse.umbral_magnitude, row.umbral_magnitude, tolerance.magnitude, label

    {penumbral, partial, total} = tolerance.minutes
    penumbral_depth = row.penumbral_magnitude
    partial_depth = row.umbral_magnitude
    total_depth = row.umbral_magnitude - 1

    assert_duration(
      {eclipse.penumbral_begins, eclipse.penumbral_ends},
      row.penumbral,
      {penumbral, penumbral_depth},
      label
    )

    assert_duration(
      {eclipse.partial_begins, eclipse.partial_ends},
      row.partial,
      {partial, partial_depth},
      label
    )

    assert_duration(
      {eclipse.total_begins, eclipse.total_ends},
      row.total,
      {total, total_depth},
      label
    )
  end

  defp assert_duration({nil, nil}, nil, _tolerance, _label) do
    :ok
  end

  defp assert_duration({begins, ends}, minutes, {_tolerance, depth}, label) when depth < @graze do
    assert is_number(begins) and is_number(ends) and is_number(minutes), label
  end

  defp assert_duration({begins, ends}, minutes, {tolerance, _depth}, label) do
    assert is_number(begins) and is_number(minutes), label
    assert_in_delta (ends - begins) * 1_440, minutes, tolerance, label
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
    [year, month, day, td, _delta_t, _lunation, _saros, type, gamma, pen, um, pen_d, par_d, tot_d] =
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
      penumbral_magnitude: String.to_float(pen),
      umbral_magnitude: String.to_float(um),
      penumbral: minutes(pen_d),
      partial: minutes(par_d),
      total: minutes(tot_d)
    }
  end

  defp eclipse_type("N") do
    :penumbral
  end

  defp eclipse_type("P") do
    :partial
  end

  defp eclipse_type("T") do
    :total
  end

  defp minutes("-") do
    nil
  end

  defp minutes(value) do
    String.to_float(value)
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
