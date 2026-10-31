defmodule Astro.SolarEclipsePathTest do
  use ExUnit.Case, async: true

  doctest Astro.Solar.Eclipse.Path

  # The oracle is NASA's path tables, for eight eclipses from 1999 to
  # 2027: total, annular, hybrid, one over Antarctica and one whose axis
  # misses the Earth. Its times are in UT with its own ΔT. A larger ΔT
  # turns the Earth further behind the shadow, the same as taking the
  # path a moment later and moving it east by the Earth's rotation in
  # that moment, so the comparison does that and is free of ΔT.
  #
  # The two ephemerides put the shadow up to about 0.7 km apart, and a
  # point at a given instant moves fast along the path, very fast near
  # sunrise and sunset, so each difference is split into the part
  # across the path, in kilometres, and the part along it, as the time
  # the shadow takes to move that far. Where the Sun is low the ground
  # is tilted to the shadow and the part across is larger.

  @nasa Path.join([__DIR__, "data", "solar_eclipses", "nasa_paths.csv"])

  @earth_equatorial_radius_km 6378.137
  @earth_eccentricity_squared 0.00669438

  # The Earth turns 360.9856° in a day of Universal Time.
  @sidereal_degrees_per_second 360.98564736629 / 86_400

  @low_sun 20
  @across_km 1.0
  @across_low_sun_km 3.0
  @along_seconds 2.5

  # A wide path curves with the Earth across its width, where NASA's
  # width and Astro's measure it differently, by up to 0.6%.
  @width_km 1.0
  @width_fraction 0.006
  @duration_seconds 0.7
  @altitude_degrees 0.6

  # NASA names a hybrid eclipse's limits by the sign of the umbra's
  # radius, so where it is total NASA's northern limit is the southern.
  @hybrid "2023-04-20"

  test "agrees with NASA's path tables" do
    for row <- nasa_rows(), {line, nasa} <- row.points do
      assert_on_path(row, line, nasa)
    end
  end

  test "agrees with NASA's width, duration and Sun's altitude on the central line" do
    for %{central: %{} = nasa} = row <- nasa_rows() do
      %{central_line: ours} = Astro.Solar.Eclipse.Path.at(row.moment)
      label = "#{row.date} #{row.time}"
      width_tolerance = @width_km + @width_fraction * nasa.width

      assert_in_delta ours.width, nasa.width, width_tolerance, label
      assert_in_delta ours.duration, nasa.duration, @duration_seconds, label
      assert_in_delta ours.sun_altitude, row.altitude, @altitude_degrees, label
    end
  end

  test "a total eclipse's path, its limits beginning and ending together on the horizon" do
    {:ok, path} = Astro.solar_eclipse_path(~D[2024-04-01])

    assert path.type == :total
    assert Enum.all?(path.central_line, &(&1.type == :total))

    for line <- [path.central_line, path.northern_limit, path.southern_limit] do
      times = Enum.map(line, & &1.time)
      assert times == Enum.sort(times, DateTime)
    end

    assert_near(List.first(path.northern_limit), List.first(path.southern_limit))
    assert_near(List.last(path.northern_limit), List.last(path.southern_limit))

    for point <- [List.first(path.central_line), List.last(path.central_line)] do
      assert_in_delta point.sun_altitude, 0.0, 0.01
    end
  end

  test "a hybrid eclipse is total in the middle of its path and annular at its ends" do
    {:ok, path} = Astro.solar_eclipse_path(~D[2023-04-01])

    assert path.type == :hybrid
    types = Enum.map(path.central_line, & &1.type)
    assert List.first(types) == :annular
    assert List.last(types) == :annular
    assert :total in types
  end

  test "an eclipse whose axis misses the Earth has no central line" do
    {:ok, path} = Astro.solar_eclipse_path(~D[2014-04-01])

    assert path.type == :annular
    assert path.central_line == []
    assert match?([_ | _], path.northern_limit)
    assert_near(List.first(path.northern_limit), List.first(path.southern_limit))
    assert_near(List.last(path.northern_limit), List.last(path.southern_limit))
  end

  test "a partial eclipse has no path" do
    assert Astro.solar_eclipse_path(~D[2025-03-01]) == {:error, :no_path}
  end

  test "the points are at whole multiples of the interval, longitude first" do
    {:ok, eclipse} = Astro.solar_eclipse_at_or_after(~D[2024-04-01])
    {:ok, path} = Astro.solar_eclipse_path(eclipse, interval: 300)

    interior =
      path.central_line
      |> Enum.drop(1)
      |> Enum.drop(-1)
      |> Enum.reject(&(abs(DateTime.diff(&1.time, eclipse.greatest, :millisecond)) <= 1))

    assert Enum.all?(interior, &(rem(&1.time.minute, 5) == 0 and &1.time.second == 0))
    assert Enum.all?(interior, &(&1.time.microsecond == {0, 3}))

    for point <- path.central_line ++ path.northern_limit ++ path.southern_limit do
      {longitude, latitude} = point.location.coordinates
      assert longitude >= -180.0 and longitude < 180.0
      assert latitude >= -90.0 and latitude <= 90.0
    end

    # Over Mexico, west of Greenwich and north of the equator.
    middle = Enum.at(interior, div(length(interior), 2))
    {longitude, latitude} = middle.location.coordinates
    assert longitude < 0.0 and latitude > 0.0
  end

  test "the same path from a date or from the eclipse" do
    {:ok, eclipse} = Astro.solar_eclipse_at_or_after(~D[2024-04-01])
    {:ok, from_date} = Astro.solar_eclipse_path(~D[2024-04-01], interval: 600)
    {:ok, from_eclipse} = Astro.solar_eclipse_path(eclipse, interval: 600)

    assert Enum.map(from_date.northern_limit, & &1.time) ==
             Enum.map(from_eclipse.northern_limit, & &1.time)
  end

  test "is an error for a bad date or option" do
    assert Astro.solar_eclipse_path(:not_a_date) == {:error, :invalid_date}
    assert Astro.solar_eclipse_path(~D[2024-04-01], :none) == {:error, :invalid_options}
    assert Astro.solar_eclipse_path(~D[2024-04-01], interval: 0.5) == {:error, :invalid_interval}
    assert Astro.solar_eclipse_path(~D[2024-04-01], interval: "60") == {:error, :invalid_interval}
    assert Astro.solar_eclipse_path(~D[2024-04-01], interval: nil) == {:error, :invalid_interval}

    {:ok, far} = Date.new(60_000, 1, 1)
    assert Astro.solar_eclipse_path(far) == {:error, :year_out_of_range}
  end

  defp assert_on_path(row, line, nasa) do
    label = "#{row.date} #{row.time} #{line}"
    ours = shifted_point(row, line, 0.0)
    before = shifted_point(row, line, -1.0)
    later = shifted_point(row, line, 1.0)

    assert ours && before && later, label

    # The shadow's motion along the line, in kilometres a second.
    {east, north} = kilometres(later, before)
    speed = :math.sqrt(east * east + north * north) / 2
    {error_east, error_north} = kilometres(nasa, ours)
    along = (error_east * east + error_north * north) / (2 * speed)
    across = abs(error_east * north - error_north * east) / (2 * speed)

    across_tolerance =
      if is_nil(row.altitude) or row.altitude >= @low_sun do
        @across_km
      else
        @across_low_sun_km
      end

    assert across <= across_tolerance, "#{label} across #{across} km"
    assert abs(along / speed) <= @along_seconds, "#{label} along #{along / speed} s"
  end

  # Our point a few seconds either side of NASA's instant, in NASA's ΔT.
  defp shifted_point(row, line, seconds) do
    case Astro.Solar.Eclipse.Path.at(row.moment + seconds / 86_400)[line] do
      nil ->
        nil

      %{location: %Geo.Point{coordinates: {longitude, latitude}}} ->
        {longitude + @sidereal_degrees_per_second * row.delta, latitude}
    end
  end

  # East and north kilometres from one `{longitude, latitude}` to another
  # nearby, on the ellipsoid.
  defp kilometres({longitude, latitude}, {from_longitude, from_latitude}) do
    radians = from_latitude * :math.pi() / 180
    w = 1 - @earth_eccentricity_squared * :math.sin(radians) ** 2
    prime_vertical = @earth_equatorial_radius_km / :math.sqrt(w)
    meridian = @earth_equatorial_radius_km * (1 - @earth_eccentricity_squared) / w ** 1.5
    longitude_change = Astro.Math.mod(longitude - from_longitude + 180.0, 360.0) - 180.0

    {
      longitude_change * prime_vertical * :math.cos(radians) * :math.pi() / 180,
      (latitude - from_latitude) * meridian * :math.pi() / 180
    }
  end

  defp assert_near(%{location: %{coordinates: a}}, %{location: %{coordinates: b}}) do
    {east, north} = kilometres(a, b)
    assert :math.sqrt(east * east + north * north) < 2.0
  end

  defp nasa_rows do
    [_header | lines] =
      @nasa
      |> File.read!()
      |> String.split("\n", trim: true)

    Enum.map(lines, &nasa_row/1)
  end

  defp nasa_row(line) do
    [date, delta_t, time | fields] = String.split(line, ",")

    [
      north_latitude,
      north_longitude,
      south_latitude,
      south_longitude,
      central_latitude,
      central_longitude
    ] =
      Enum.take(fields, 6)

    [ratio, altitude, width, duration] = Enum.drop(fields, 6)
    moment = moment(date, time)
    delta = String.to_float(delta_t) - delta_t(moment)

    {north, south} =
      limits(
        date,
        number(ratio),
        point(north_longitude, north_latitude),
        point(south_longitude, south_latitude)
      )

    points =
      [
        northern_limit: north,
        southern_limit: south,
        central_line: point(central_longitude, central_latitude)
      ]
      |> Enum.reject(fn {_line, point} -> is_nil(point) end)

    %{
      date: date,
      time: time,
      moment: moment + delta / 86_400,
      delta: delta,
      altitude: number(altitude),
      points: points,
      central: central(number(width), number(duration))
    }
  end

  defp limits(@hybrid, ratio, north, south) when ratio >= 1.0 do
    {south, north}
  end

  defp limits(_date, _ratio, north, south) do
    {north, south}
  end

  defp central(nil, _duration) do
    nil
  end

  defp central(_width, nil) do
    nil
  end

  defp central(width, duration) do
    %{width: width, duration: duration}
  end

  defp point("", _latitude) do
    nil
  end

  defp point(longitude, latitude) do
    {String.to_float(longitude), String.to_float(latitude)}
  end

  defp number("") do
    nil
  end

  defp number(value) do
    {number, ""} = Float.parse(value)
    number
  end

  defp moment(date, time) do
    [hours, minutes] = String.split(time, ":")
    days = Date.to_gregorian_days(Date.from_iso8601!(date))
    days + (String.to_integer(hours) * 60 + String.to_integer(minutes)) / 1_440
  end

  defp delta_t(moment) do
    (730_485.5 + Astro.Time.dynamical_time_from_moment(moment) / 86_400 - moment) * 86_400
  end
end
