defmodule Astro.Solar.Eclipse.Path do
  @moduledoc """
  The path of a solar eclipse: where on the Earth it is total or
  annular, as the central line and the northern and southern limits of
  the umbra, or the antumbra, through the time the shadow is on the
  Earth.

  The Besselian elements (see `Astro.Solar.Eclipse`) put the shadow on
  the fundamental plane, through the centre of the Earth and
  perpendicular to the shadow axis. On it the Earth is an ellipse, and
  a point `(ξ, η)` inside it is on the surface at a height `ζ` above
  the plane. Following the *Explanatory Supplement*, the auxiliary
  declinations `d1` and `d2` turn the ellipsoid into a unit sphere,
  `η1 = η / ρ1` and `ζ1 = √(1 − ξ² − η1²)`, and then

  * `ζ = ρ2 (ζ1 cos(d1 − d2) − η1 sin(d1 − d2))`,

  * `sin φ1 = η1 cos d1 + ζ1 sin d1`, the latitude on the sphere, and
    `tan φ = tan φ1 / √(1 − e²)` the geodetic latitude, and

  * `H = atan2(ξ, ζ1 cos d1 − η1 sin d1)`, the hour angle of the
    shadow axis there, and `λ = H − μ` the east longitude.

  ### The central line

  The *central line* is where the shadow axis meets the surface,
  `ξ = x` and `η = y`. It begins and ends at sunrise and sunset, where
  the axis grazes the Earth. Along it:

  * The eclipse is *total* where the umbra's radius at the surface,
    `L2 = l2 − ζ tan f2`, is negative, and *annular* where it is
    positive. A hybrid eclipse changes from one to the other.

  * The shadow moves over the observer at `(a, b)` on the plane, its
    own motion `(x′, y′)` less the observer's, which the Earth's
    rotation carries at `ξ′ = μ′ (ζ cos d − η sin d)` and
    `η′ = μ′ ξ sin d − ζ d′`. The *duration* of totality or annularity
    is the time to cross the shadow, `2 |L2| / √(a² + b²)`.

  * The *path width* is the width of the band whose observers come
    within `|L2|` of the axis: `2 |L2|` across the motion on the plane,
    lengthened where the ground is tilted to the plane, so
    `2 |L2| / √(1 − (q · n)²)`, where `q` is the unit vector across the
    motion and `n` the vertical at the central line.

  * The Sun's *altitude* is that of the shadow axis,
    `sin h = sin d sin φ + cos d cos φ cos H`, geometric.

  ### The limits

  A *limit* is where the shadow's edge just grazes an observer: at the
  moment the observer is nearest the axis, `m = |L2|`. The observers
  nearest the axis at a moment lie on the line through the axis across
  the shadow's motion `(a, b)`, turned slightly along it as the cone's
  radius changes, `u a + v b = L2 L2′` for `(u, v)` the axis less the
  observer. On that line the Earth is a chord, every point of which is
  on the surface, and the limit is where the chord leaves the shadow:
  where the distance from the axis overtakes the cone's radius at that
  point's height, found by bisection. The motion and `L2′` depend a
  little on where the observer is, so the limit is found again from
  where it was. The *northern limit* is to the left of the shadow's
  motion, which is always eastward, and the *southern limit* to the
  right.

  Where the shadow reaches past the end of the chord, the edge of the
  path is the horizon: the place on the limb having its greatest
  eclipse at sunrise or sunset, the curve NASA's path tables give as
  the second limit of an eclipse whose axis misses the Earth. So near
  the ends of a path the limits follow the horizon, and they begin
  together where the shadow first touches the Earth and end together
  where it leaves. The cone's radius changes with the height above the
  plane, which changes quickly near the limb, so the shadow first
  touches the Earth a little inside the limb, where the chord is
  deepest in the shadow. There the ground is so tilted to the shadow
  that a hundred metres on the plane is tens of kilometres on the
  Earth, so at those two instants the limits are found from the line
  straight across the motion at the axis, the same for both, and they
  meet.

  The limits are those of the umbra of the mean lunar limb, `k2`. The
  mountains and valleys of the limb move a limit by a kilometre or two
  and are not included, as NASA's path tables do not include them.

  Because `μ` is the Greenwich hour angle at the moment, longitudes need
  no correction for ΔT. NASA's path tables use an ephemeris hour angle
  with ΔT applied to it, so they agree when they use the same ΔT.

  """

  alias Astro.{Earth, Math}
  alias Astro.Solar.Eclipse

  import Astro.Math, only: [sin: 1, cos: 1, asin: 1, atan: 2]

  @typedoc """
  A point on the central line at a moment: its `t:Geo.Point.t/0`, the
  eclipse there, the path's width in kilometres, the duration of
  totality or annularity in seconds and the Sun's geometric altitude in
  degrees.

  """
  @type central_point :: %{
          time: Astro.Time.moment(),
          location: Geo.Point.t(),
          type: :total | :annular,
          width: float(),
          duration: float(),
          sun_altitude: float()
        }

  @typedoc """
  A point on a limit of the path at a moment.

  """
  @type limit_point :: %{time: Astro.Time.moment(), location: Geo.Point.t()}

  @typedoc """
  The path of a solar eclipse, as `Astro.solar_eclipse_path/2` returns
  it: the eclipse's type and its central line and limits as lists of
  points in time order, each point's `:time` a UTC `t:DateTime.t/0`.

  """
  @type t :: %__MODULE__{
          type: :total | :annular | :hybrid,
          central_line: [map()],
          northern_limit: [map()],
          southern_limit: [map()]
        }

  defstruct [:type, :central_line, :northern_limit, :southern_limit]

  # The square of the eccentricity of the Earth's meridian ellipse (WGS 84).
  @earth_eccentricity_squared 0.00669438

  # The rates of the elements are central differences over a minute
  # either side.
  @rate_step_days 1 / 1_440

  @seconds_per_day 86_400

  @lines [:central_line, :northern_limit, :southern_limit]

  # The umbra is on the Earth within six hours of greatest eclipse. The
  # ends of each line are found to about a tenth of a millisecond: at the
  # horizon the shadow crosses the ground at hundreds of kilometres a
  # second.
  @days_around_greatest 0.25
  @end_tolerance_days 1.0e-9

  # An edge is found to a micrometre, in Earth radii, and found again
  # from itself this many times; the line it is on turns by about 0.1%
  # for a change in the observer the size of the shadow.
  @edge_tolerance 1.0e-13
  @edge_iterations 3

  # The golden section of an interval.
  @golden_section 0.381966011250105

  @doc """
  Returns the points of the path of a solar eclipse at a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0`.

  ### Returns

  * A map with keys `:central_line`, a `t:central_point/0`, and
    `:northern_limit` and `:southern_limit`, each a `t:limit_point/0`.
    A point is `nil` where it is not on the Earth at the moment.

  ### Examples

  At 18:00 UT on 8 April 2024 the central line of the total eclipse
  was over the Pacific, south-west of Mazatlán. NASA's path table, whose ΔT is 1.4 s larger, puts
  it at 20°19.2′N 108°45.8′W, about 2 km east. Locations are
  `{longitude, latitude}`:

      iex> points = Astro.Solar.Eclipse.Path.at(739_349.75)
      iex> {longitude, latitude} = points.central_line.location.coordinates
      iex> {Float.round(longitude, 2), Float.round(latitude, 2)}
      {-108.78, 20.31}

  """
  @spec at(Astro.Time.moment()) :: %{
          central_line: central_point() | nil,
          northern_limit: limit_point() | nil,
          southern_limit: limit_point() | nil
        }
  def at(t) do
    points_at(t, @edge_iterations)
  end

  defp points_at(t, edge_iterations) do
    elements = Eclipse.elements(t)
    rates = rates(t)
    surface = surface_geometry(elements.d)
    limit = fn side -> limit_point(t, elements, rates, surface, side, edge_iterations) end

    %{
      central_line: central_point(t, elements, rates, surface),
      northern_limit: limit.(1.0),
      southern_limit: limit.(-1.0)
    }
  end

  @doc """
  Returns the path of a solar eclipse: its central line and its
  northern and southern limits.

  The points are at whole multiples of `interval` from midnight, and at
  greatest eclipse, while the shadow is on the Earth. Each line also has
  a point where it begins and where it ends, found by bisection.

  ### Arguments

  * `eclipse` is a solar eclipse's circumstances as
    `Astro.Solar.Eclipse.eclipse_at_or_after/1` returns them, every
    instant a moment.

  * `interval` is the time between points, in days.

  ### Returns

  * `{:ok, path}`, a map of the eclipse's `:type` and its
    `:central_line`, a list of `t:central_point/0`, and
    `:northern_limit` and `:southern_limit`, each a list of
    `t:limit_point/0`, in time order. The central line is empty for an
    eclipse whose shadow axis misses the Earth.

  * `{:error, :no_path}` for a partial eclipse, whose umbra and
    antumbra miss the Earth.

  ### Examples

      iex> {:ok, eclipse} = Astro.Solar.Eclipse.eclipse_at_or_after(739_300.0)
      iex> {:ok, path} = Astro.Solar.Eclipse.Path.path(eclipse, 1 / 1_440)
      iex> greatest = Enum.max_by(path.central_line, & &1.duration)
      iex> Float.round(greatest.duration, 0)
      268.0

  """
  @spec path(map(), number()) ::
          {:ok,
           %{
             type: Eclipse.eclipse_type(),
             central_line: [central_point()],
             northern_limit: [limit_point()],
             southern_limit: [limit_point()]
           }}
          | {:error, :no_path}
  def path(%{type: :partial}, _interval) do
    {:error, :no_path}
  end

  def path(%{type: type, greatest: greatest}, interval) do
    samples =
      greatest
      |> sample_times(interval)
      |> Enum.map(fn t -> {t, at(t)} end)

    lines = Map.new(@lines, fn line -> {line, line(samples, line)} end)

    if Enum.all?(Map.values(lines), &Enum.empty?/1) do
      {:error, :no_path}
    else
      {:ok, Map.put(lines, :type, type)}
    end
  end

  # Whole multiples of the interval within the window around greatest
  # eclipse, and greatest eclipse itself.
  defp sample_times(greatest, interval) do
    first = ceil((greatest - @days_around_greatest) / interval)
    last = floor((greatest + @days_around_greatest) / interval)

    first..last//1
    |> Enum.map(&(&1 * interval))
    |> Enum.concat([greatest])
    |> Enum.sort()
    |> Enum.dedup()
  end

  # A line's points at the samples, and where it begins and ends.
  defp line(samples, line) do
    {before, rest} = Enum.split_while(samples, &absent?(&1, line))
    {present, following} = Enum.split_while(rest, &(not absent?(&1, line)))
    line_points(before, present, following, line)
  end

  defp absent?({_t, points}, line) do
    is_nil(points[line])
  end

  defp line_points(_before, [], _following, _line) do
    []
  end

  defp line_points(before, [{first, _points} | _rest] = present, following, line) do
    {last, _points} = List.last(present)
    start = line_end(List.last(before), first, line)
    finish = line_end(List.first(following), last, line)
    points = Enum.map(present, fn {_t, points} -> points[line] end)

    Enum.reject([start | points] ++ [finish], &is_nil/1)
  end

  # The point where a line begins or ends, between the sample next to
  # its first or last point and that point, if there is such a sample.
  defp line_end(nil, _present, _line) do
    nil
  end

  # At the instant the shadow first touches the Earth, or last leaves
  # it, the limits meet there. The ground is then so tilted to the shadow
  # that a hundred metres on the plane is tens of kilometres on the
  # Earth, so the edges are taken from the first step alone, which is
  # the same line for both sides, and the path closes.
  defp line_end({absent, _points}, present, line) do
    t = bisect_end(absent, present, line)
    points_at(t, 1)[line]
  end

  defp bisect_end(absent, present, _line) when abs(present - absent) < @end_tolerance_days do
    present
  end

  defp bisect_end(absent, present, line) do
    middle = (absent + present) / 2

    if is_nil(at(middle)[line]) do
      bisect_end(middle, present, line)
    else
      bisect_end(absent, middle, line)
    end
  end

  defp central_point(t, elements, rates, surface) do
    %{x: x, y: y, d: d, l2: l2, tan_f2: tan_f2} = elements

    case height(x, y, surface) do
      {:ok, zeta1, zeta} ->
        {longitude, latitude, hour_angle} = location(x, y, zeta1, elements, surface)
        umbra = l2 - zeta * tan_f2
        {a, b} = relative_motion(x, y, zeta, elements, rates)
        speed = :math.sqrt(a * a + b * b)

        %{
          time: t,
          location: %Geo.Point{coordinates: {longitude, latitude}},
          type: central_type(umbra),
          width: width(umbra, a, b, speed, latitude, hour_angle, d),
          duration: 2 * abs(umbra) / speed * @seconds_per_day,
          sun_altitude: asin(sin(d) * sin(latitude) + cos(d) * cos(latitude) * cos(hour_angle))
        }

      :none ->
        nil
    end
  end

  defp central_type(umbra) when umbra < 0.0 do
    :total
  end

  defp central_type(_umbra) do
    :annular
  end

  # Across the motion on the plane the band is 2|L2| wide; the vertical
  # `n` at the central line tilts the ground to the plane, which widens
  # it by 1 / √(1 − (q · n)²) for `q` the unit vector across the motion.
  defp width(umbra, a, b, speed, latitude, hour_angle, d) do
    normal_x = cos(latitude) * sin(hour_angle)
    normal_y = sin(latitude) * cos(d) - cos(latitude) * sin(d) * cos(hour_angle)
    across = (a * normal_y - b * normal_x) / speed

    2 * abs(umbra) / :math.sqrt(1 - across * across) * Earth.earth_radius_m() / 1_000
  end

  # The edge of the path on one side at a moment. The observers having
  # greatest eclipse at the moment lie on the line through the axis
  # across the shadow's motion; the edge is where that line leaves the
  # shadow, `|L2|` from the axis, or leaves the Earth first, at the
  # horizon. Where the cone's radius changes, the observer for whom the
  # shadow's edge passes nearest is a little along the motion, so the
  # line is turned by `α = L2′ / √(a² + b²)`. The motion and `L2′`
  # depend a little on where the observer is, so the edge is found again
  # from where it was. `side` is 1.0 for the northern limit, to the left
  # of the shadow's motion, and -1.0 for the southern.
  defp limit_point(t, elements, rates, surface, side, iterations) do
    observer = %{xi: elements.x, eta: elements.y, zeta: 0.0}

    case edge(observer, elements, rates, surface, side, iterations, :none) do
      {:ok, %{xi: xi, eta: eta, zeta1: zeta1}} ->
        {longitude, latitude, _hour_angle} = location(xi, eta, zeta1, elements, surface)
        %{time: t, location: %Geo.Point{coordinates: {longitude, latitude}}}

      :none ->
        nil
    end
  end

  # Just after the shadow reaches the Earth the part of the line on the
  # Earth and within the shadow is a sliver at the limb. The first step
  # takes the line straight across the motion at the axis, the same line
  # for both sides, so that both edges are found or neither is; turning
  # it for the motion at the edge can then take it off the Earth, and
  # the edge found before is kept.
  defp edge(_observer, _elements, _rates, _surface, _side, 0, found) do
    found
  end

  defp edge(observer, elements, rates, surface, side, iterations, found) do
    line = edge_line(observer, elements, rates, side, found)

    case edge_on_line(line, surface) do
      {:ok, next} -> edge(next, elements, rates, surface, side, iterations - 1, {:ok, next})
      :none -> found
    end
  end

  defp edge_on_line(line, surface) do
    with {:ok, entry, exit} <- chord(line, surface) do
      edge_on_chord(entry, exit, line, surface)
    end
  end

  # The line from the axis towards the edge on one side, as the axis,
  # the unit direction, and what gives the cone's radius at a height.
  defp edge_line(observer, elements, rates, side, found) do
    %{xi: xi, eta: eta, zeta: zeta} = observer
    %{x: x, y: y, l2: l2, tan_f2: tan_f2} = elements
    {a, b} = relative_motion(xi, eta, zeta, elements, rates)
    speed = :math.sqrt(a * a + b * b)
    along = turn(found, observer, elements, rates, speed)
    across = side * :math.sqrt(1 - along * along)

    %{
      x: x,
      y: y,
      direction_x: (-along * a - across * b) / speed,
      direction_y: (-along * b + across * a) / speed,
      l2: l2,
      tan_f2: tan_f2
    }
  end

  # Where the line enters and leaves the Earth, as distances along it
  # from the axis: on the plane the Earth is the unit circle once `η` is
  # scaled by `1 / ρ1`.
  defp chord(line, surface) do
    eta1 = line.y / surface.rho1
    direction_y1 = line.direction_y / surface.rho1
    quadratic = line.direction_x * line.direction_x + direction_y1 * direction_y1
    linear = 2 * (line.x * line.direction_x + eta1 * direction_y1)
    constant = line.x * line.x + eta1 * eta1 - 1
    discriminant = linear * linear - 4 * quadratic * constant

    if discriminant < 0.0 do
      :none
    else
      root = :math.sqrt(discriminant)
      {:ok, (-linear - root) / (2 * quadratic), (-linear + root) / (2 * quadratic)}
    end
  end

  # The part of the chord within the shadow, where the distance from the
  # axis is less than the cone's radius there, ends on this side at the
  # edge: where the chord leaves the Earth, or where the distance
  # overtakes the radius, found by bisection from a point within. The
  # cone's radius changes with the height above the plane, which near
  # the limb changes quickly, so the shadow can first reach the Earth a
  # little inside the limb: the point within is the axis where it is on
  # the chord, and otherwise the point of the chord deepest in the
  # shadow, from either end or a golden section search between them.
  defp edge_on_chord(entry, exit, line, surface) do
    inside = deepest(entry, exit, line, surface)

    cond do
      beyond_edge(inside, line, surface) >= 0.0 -> :none
      beyond_edge(exit, line, surface) < 0.0 -> {:ok, point_on_line(exit, line, surface)}
      true -> {:ok, bisect_edge(inside, exit, line, surface)}
    end
  end

  defp deepest(entry, exit, _line, _surface) when entry <= 0.0 and exit >= 0.0 do
    0.0
  end

  defp deepest(entry, exit, line, surface) do
    Enum.min_by(
      [entry, exit, golden_section(entry, exit, line, surface)],
      &beyond_edge(&1, line, surface)
    )
  end

  defp golden_section(low, high, _line, _surface) when high - low < @edge_tolerance do
    (low + high) / 2
  end

  defp golden_section(low, high, line, surface) do
    step = (high - low) * @golden_section
    left = low + step
    right = high - step

    if beyond_edge(left, line, surface) < beyond_edge(right, line, surface) do
      golden_section(low, right, line, surface)
    else
      golden_section(left, high, line, surface)
    end
  end

  defp bisect_edge(inside, outside, line, surface)
       when abs(outside - inside) < @edge_tolerance do
    point_on_line((inside + outside) / 2, line, surface)
  end

  defp bisect_edge(inside, outside, line, surface) do
    middle = (inside + outside) / 2

    if beyond_edge(middle, line, surface) < 0.0 do
      bisect_edge(middle, outside, line, surface)
    else
      bisect_edge(inside, middle, line, surface)
    end
  end

  # How far beyond the shadow's edge a point of the line is: its
  # distance from the axis less the cone's radius there.
  defp beyond_edge(distance, line, surface) do
    abs(distance) - radius_at(distance, line, surface)
  end

  defp radius_at(distance, line, surface) do
    %{zeta: zeta} = point_on_line(distance, line, surface)
    abs(line.l2 - zeta * line.tan_f2)
  end

  # The point of the surface on the line, which within the chord is on
  # the Earth; at the ends `ζ1` is zero, and rounding is not allowed to
  # take it below.
  defp point_on_line(distance, line, surface) do
    xi = line.x + distance * line.direction_x
    eta = line.y + distance * line.direction_y
    eta1 = eta / surface.rho1
    zeta1 = :math.sqrt(max(1 - xi * xi - eta1 * eta1, 0.0))
    zeta = surface.rho2 * (zeta1 * surface.cos_d1_d2 - eta1 * surface.sin_d1_d2)

    %{xi: xi, eta: eta, zeta: zeta, zeta1: zeta1}
  end

  # The sine of the angle the line turns along the motion, as the cone's
  # radius changes for the observer: none for the first step.
  defp turn(:none, _observer, _elements, _rates, _speed) do
    0.0
  end

  defp turn({:ok, _edge}, observer, elements, rates, speed) do
    %{xi: xi, eta: eta, zeta: zeta} = observer
    %{d: d, l2: l2, tan_f2: tan_f2} = elements
    umbra = l2 - zeta * tan_f2
    height_rate = -rates.mu * xi * cos(d) + rates.d * eta
    umbra_rate = rates.l2 - height_rate * tan_f2

    clamp(sign(umbra) * umbra_rate / speed, -1.0, 1.0)
  end

  defp sign(value) when value < 0.0 do
    -1.0
  end

  defp sign(_value) do
    1.0
  end

  defp clamp(value, least, greatest) do
    value
    |> max(least)
    |> min(greatest)
  end

  # The shadow's motion over an observer on the plane, per day: its own
  # less the observer's, carried by the Earth's rotation and the change
  # in the axis's declination.
  defp relative_motion(xi, eta, zeta, %{d: d}, rates) do
    xi_rate = rates.mu * (zeta * cos(d) - eta * sin(d))
    eta_rate = rates.mu * xi * sin(d) - zeta * rates.d
    {rates.x - xi_rate, rates.y - eta_rate}
  end

  # The rates of the elements per day, `μ′` and `d′` in radians.
  defp rates(t) do
    before = Eclipse.elements(t - @rate_step_days)
    later = Eclipse.elements(t + @rate_step_days)
    interval = 2 * @rate_step_days
    mu_change = Math.mod(later.mu - before.mu + 180.0, 360.0) - 180.0

    %{
      x: (later.x - before.x) / interval,
      y: (later.y - before.y) / interval,
      l2: (later.l2 - before.l2) / interval,
      mu: mu_change / interval * :math.pi() / 180,
      d: (later.d - before.d) / interval * :math.pi() / 180
    }
  end

  # The Explanatory Supplement's auxiliary quantities for the Earth's
  # ellipsoid seen along the shadow axis at declination `d`.
  defp surface_geometry(d) do
    rho1 = :math.sqrt(1 - @earth_eccentricity_squared * cos(d) * cos(d))
    rho2 = :math.sqrt(1 - @earth_eccentricity_squared * sin(d) * sin(d))
    sin_d1_d2 = @earth_eccentricity_squared * sin(d) * cos(d) / (rho1 * rho2)

    %{
      rho1: rho1,
      rho2: rho2,
      sin_d1: sin(d) / rho1,
      cos_d1: :math.sqrt(1 - @earth_eccentricity_squared) * cos(d) / rho1,
      sin_d1_d2: sin_d1_d2,
      cos_d1_d2: :math.sqrt(1 - sin_d1_d2 * sin_d1_d2)
    }
  end

  # The height above the plane of the surface at `(ξ, η)`, and `ζ1` on
  # the unit sphere, or `:none` off the Earth.
  defp height(xi, eta, surface) do
    eta1 = eta / surface.rho1
    radius_squared = xi * xi + eta1 * eta1

    if radius_squared <= 1.0 do
      zeta1 = :math.sqrt(1 - radius_squared)
      {:ok, zeta1, surface.rho2 * (zeta1 * surface.cos_d1_d2 - eta1 * surface.sin_d1_d2)}
    else
      :none
    end
  end

  # The geodetic longitude and latitude of the surface at `(ξ, η)`, and
  # the hour angle of the shadow axis there.
  defp location(xi, eta, zeta1, %{mu: mu}, surface) do
    eta1 = eta / surface.rho1
    sin_phi1 = eta1 * surface.cos_d1 + zeta1 * surface.sin_d1
    cos_phi1 = :math.sqrt(max(1 - sin_phi1 * sin_phi1, 0.0))
    hour_angle = atan(xi, zeta1 * surface.cos_d1 - eta1 * surface.sin_d1)
    # A latitude is signed, where `atan/2` is an angle from 0° to 360°.
    latitude =
      :math.atan2(sin_phi1, :math.sqrt(1 - @earth_eccentricity_squared) * cos_phi1) * 180 /
        :math.pi()

    longitude = Math.mod(hour_angle - mu + 180.0, 360.0) - 180.0

    {longitude, latitude, hour_angle}
  end
end
