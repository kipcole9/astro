defmodule Astro.Solar.Eclipse.Path do
  @moduledoc """
  The path of a solar eclipse: where on the Earth it is total or
  annular, as the central line and the northern and southern limits of
  the umbra, or the antumbra, and where it is seen at all, as the
  limits of the penumbra and the curves on the horizon where it begins
  or ends at sunrise or sunset, through the time the shadow is on the
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

  ### The region of partial eclipse

  The partial eclipse is seen wherever the penumbra passes while the
  Sun is up. Its region is bounded by:

  * The *penumbral limits*, north and south, found as the umbral limits
    are, from the penumbra's radius `L1 = l1 − ζ tan f1`. Where a limit
    would lie beyond the horizon it is left out: the region is bounded
    there by the horizon instead.

  * The *sunrise limit*, where the eclipse ends just as the Sun rises,
    and the *sunset limit*, where it begins just as the Sun sets. At a
    moment, the penumbra's edge meets the Earth's limb, `(cos θ,
    ρ1 sin θ)` on the plane, at up to two points, found by Newton's
    method from where a circle of the penumbra's radius meets the unit
    circle. A point where the shadow is leaving, `u a + v b < 0` for
    `(u, v)` the point less the axis, and the ground is turning into
    the day, `ζ′ = −μ′ ξ cos d + d′ η > 0`, sees the eclipse end at
    sunrise; one where the shadow is arriving and the ground turning
    into the night sees it begin at sunset. Places a little inside
    these curves see some of the eclipse with the Sun up.

  Within the region, the curves of *maximum eclipse at sunrise* and *at
  sunset* are the places having their greatest eclipse on the horizon:
  the ends of the chord across the shadow's motion through the axis,
  where they are within the penumbra. *First* and *last contact* are
  the moments the penumbra first touches the Earth's limb and last
  leaves it, at the point of the limb nearest the axis, where the Sun
  is on the horizon.

  A curve on the horizon can have two branches at the same moment, as
  when the penumbra overlaps the limb on one side of the Earth and the
  eclipse ends at sunrise both north and south of the axis, so each of
  those curves is a list of lines. The horizon is geometric: the
  Sun's centre at zero altitude, without refraction.

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
  A line of points in time order.

  """
  @type line :: [limit_point()]

  @typedoc """
  The path of a solar eclipse, as `Astro.solar_eclipse_path/2` returns
  it: the eclipse's type; its central line and limits, and its
  penumbral limits, as lists of points in time order; its sunrise and
  sunset limits and its curves of maximum eclipse at sunrise and
  sunset as lists of such lines; and its first and last contact. Each
  point's `:time` is a UTC `t:DateTime.t/0`.

  """
  @type t :: %__MODULE__{
          type: Eclipse.eclipse_type(),
          central_line: [map()],
          northern_limit: [map()],
          southern_limit: [map()],
          penumbral_northern_limit: [map()],
          penumbral_southern_limit: [map()],
          sunrise_limit: [[map()]],
          sunset_limit: [[map()]],
          maximum_at_sunrise: [[map()]],
          maximum_at_sunset: [[map()]],
          first_contact: map(),
          last_contact: map()
        }

  defstruct [
    :type,
    :central_line,
    :northern_limit,
    :southern_limit,
    :penumbral_northern_limit,
    :penumbral_southern_limit,
    :sunrise_limit,
    :sunset_limit,
    :maximum_at_sunrise,
    :maximum_at_sunset,
    :first_contact,
    :last_contact
  ]

  # The square of the eccentricity of the Earth's meridian ellipse (WGS 84).
  @earth_eccentricity_squared 0.00669438

  # The rates of the elements are central differences over a minute
  # either side.
  @rate_step_days 1 / 1_440

  @seconds_per_day 86_400

  @lines [
    :central_line,
    :northern_limit,
    :southern_limit,
    :penumbral_northern_limit,
    :penumbral_southern_limit
  ]

  @curves [:sunrise_limit, :sunset_limit, :maximum_at_sunrise, :maximum_at_sunset]

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

  # Where the penumbra's edge meets the limb is found by Newton's method,
  # its slope by a difference over this angle in radians.
  @newton_iterations 20
  @newton_step 1.0e-7

  # First and last contact are bracketed in steps of ten minutes, and the
  # nearest point of the limb is searched for within this many radians of
  # the direction of the axis.
  @contact_step_days 10 / 1_440
  @limb_search 0.2

  @doc """
  Returns the points of the path of a solar eclipse at a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0`.

  ### Returns

  * A map with keys `:central_line`, a `t:central_point/0`;
    `:northern_limit`, `:southern_limit`, `:penumbral_northern_limit`
    and `:penumbral_southern_limit`, each a `t:limit_point/0`, `nil`
    where it is not on the Earth at the moment; and `:sunrise_limit`,
    `:sunset_limit`, `:maximum_at_sunrise` and `:maximum_at_sunset`,
    each a list of the up to two `t:limit_point/0`s of the curve at the
    moment.

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
          southern_limit: limit_point() | nil,
          penumbral_northern_limit: limit_point() | nil,
          penumbral_southern_limit: limit_point() | nil,
          sunrise_limit: [limit_point()],
          sunset_limit: [limit_point()],
          maximum_at_sunrise: [limit_point()],
          maximum_at_sunset: [limit_point()]
        }
  def at(t) do
    points = points_at(t, @edge_iterations)
    lines = Map.take(points, @lines)

    curves =
      Map.new(@curves, fn curve ->
        branches = for {{^curve, _branch}, point} <- points, do: point
        {curve, branches}
      end)

    Map.merge(lines, curves)
  end

  defp points_at(t, edge_iterations) do
    elements = Eclipse.elements(t)
    rates = rates(t)
    surface = surface_geometry(elements.d)

    limit = fn side, cone ->
      limit_point(t, elements, rates, surface, side, edge_iterations, cone)
    end

    %{
      central_line: central_point(t, elements, rates, surface),
      northern_limit: limit.(1.0, :umbra),
      southern_limit: limit.(-1.0, :umbra),
      penumbral_northern_limit: limit.(1.0, :penumbra),
      penumbral_southern_limit: limit.(-1.0, :penumbra)
    }
    |> Map.merge(Map.new(horizon_contacts(t, elements, rates, surface)))
    |> Map.merge(Map.new(horizon_maxima(t, elements, rates, surface)))
  end

  @doc """
  Returns the path of a solar eclipse: its central line and northern
  and southern limits, and the bounds of its region of partial eclipse.

  The points are at whole multiples of `interval` from midnight, and at
  greatest eclipse, while the shadow is on the Earth. Each line also has
  a point where it begins and where it ends, found by bisection.

  ### Arguments

  * `eclipse` is a solar eclipse's circumstances as
    `Astro.Solar.Eclipse.eclipse_at_or_after/1` returns them, every
    instant a moment.

  * `interval` is the time between points, in days.

  ### Returns

  * `{:ok, path}`, a map of the eclipse's `:type`; its
    `:central_line`, a list of `t:central_point/0`; its
    `:northern_limit`, `:southern_limit`, `:penumbral_northern_limit`
    and `:penumbral_southern_limit`, each a `t:line/0`; its
    `:sunrise_limit`, `:sunset_limit`, `:maximum_at_sunrise` and
    `:maximum_at_sunset`, each a list of `t:line/0`s in the order they
    begin; and its `:first_contact` and `:last_contact`, each a
    `t:limit_point/0`. The central line is empty for an eclipse whose
    shadow axis misses the Earth, and the central line and umbral
    limits are empty for a partial eclipse.

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
             northern_limit: line(),
             southern_limit: line(),
             penumbral_northern_limit: line(),
             penumbral_southern_limit: line(),
             sunrise_limit: [line()],
             sunset_limit: [line()],
             maximum_at_sunrise: [line()],
             maximum_at_sunset: [line()],
             first_contact: limit_point(),
             last_contact: limit_point()
           }}
  def path(%{type: type, greatest: greatest}, interval) do
    samples =
      greatest
      |> sample_times(interval)
      |> Enum.map(fn t -> {t, points_at(t, @edge_iterations)} end)

    lines = Map.new(@lines, fn line -> {line, line(samples, line)} end)
    curves = Map.new(@curves, fn curve -> {curve, curve(samples, curve)} end)

    {:ok,
     lines
     |> Map.merge(curves)
     |> Map.merge(%{
       type: type,
       first_contact: contact(greatest, -1.0),
       last_contact: contact(greatest, 1.0)
     })}
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

  # A line's points at the samples, and where it begins and ends: one
  # run of moments while it is on the Earth.
  defp line(samples, key) do
    samples
    |> runs(key)
    |> Enum.flat_map(&run_points(&1, key))
  end

  # A curve on the horizon can have two branches at once, each a line of
  # its own, and a branch can appear in more than one run.
  defp curve(samples, kind) do
    samples
    |> branches(kind)
    |> Enum.flat_map(fn branch -> runs(samples, branch) |> Enum.map(&run_points(&1, branch)) end)
    |> Enum.reject(&Enum.empty?/1)
    |> Enum.sort_by(fn [%{time: time} | _rest] -> time end)
  end

  defp branches(samples, kind) do
    samples
    |> Enum.flat_map(fn {_t, points} -> Map.keys(points) end)
    |> Enum.filter(&match?({^kind, _branch}, &1))
    |> Enum.uniq()
  end

  # The runs of samples in which a key has a point, each with the samples
  # either side of it, if there are any.
  defp runs(samples, key) do
    samples
    |> Enum.with_index()
    |> Enum.chunk_by(fn {sample, _index} -> absent?(sample, key) end)
    |> Enum.reject(fn [{sample, _index} | _rest] -> absent?(sample, key) end)
    |> Enum.map(fn [{_sample, first} | _rest] = run ->
      {_sample, last} = List.last(run)
      {neighbour(samples, first - 1), Enum.map(run, &elem(&1, 0)), neighbour(samples, last + 1)}
    end)
  end

  defp neighbour(_samples, index) when index < 0 do
    nil
  end

  defp neighbour(samples, index) do
    Enum.at(samples, index)
  end

  defp absent?({_t, points}, key) do
    is_nil(points[key])
  end

  defp run_points({before, [{first, _points} | _rest] = present, following}, key) do
    {last, _points} = List.last(present)
    start = line_end(before, first, key)
    finish = line_end(following, last, key)
    points = Enum.map(present, fn {_t, points} -> points[key] end)

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

    if is_nil(points_at(middle, @edge_iterations)[line]) do
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
  defp limit_point(t, elements, rates, surface, side, iterations, cone) do
    observer = %{xi: elements.x, eta: elements.y, zeta: 0.0}
    context = {elements, rates, surface, side, cone}

    case edge(observer, context, iterations, :none) do
      {:ok, kind, %{xi: xi, eta: eta, zeta1: zeta1}} when kind == :limit or cone == :umbra ->
        {longitude, latitude, _hour_angle} = location(xi, eta, zeta1, elements, surface)
        %{time: t, location: %Geo.Point{coordinates: {longitude, latitude}}}

      _none_or_horizon ->
        nil
    end
  end

  # First and last contact: the moments the penumbra first touches the
  # Earth's limb and last leaves it, when the axis is the penumbra's
  # radius from the nearest point of the limb, and that point, where
  # the Sun is on the horizon. Each is bracketed in steps from greatest
  # eclipse and found by bisection.
  defp contact(greatest, direction) do
    {outside, inside} = contact_bracket(greatest, direction)
    t = bisect_contact(outside, inside)
    elements = Eclipse.elements(t)
    surface = surface_geometry(elements.d)
    {xi, eta, _zeta} = limb_point(nearest_limb(elements, surface), surface)

    horizon_point(t, xi, eta, elements, surface)
  end

  defp contact_bracket(inside, direction) do
    outside = inside + direction * @contact_step_days

    if limb_gap(outside) > 0.0 do
      {outside, inside}
    else
      contact_bracket(outside, direction)
    end
  end

  defp bisect_contact(outside, inside) when abs(outside - inside) < @end_tolerance_days do
    (outside + inside) / 2
  end

  defp bisect_contact(outside, inside) do
    middle = (outside + inside) / 2

    if limb_gap(middle) > 0.0 do
      bisect_contact(middle, inside)
    else
      bisect_contact(outside, middle)
    end
  end

  # How far the penumbra's edge is from the Earth's limb at a moment:
  # positive while the penumbra is off the Earth, and negative while it
  # overlaps it, as it does whenever the axis is on the Earth.
  defp limb_gap(t) do
    elements = Eclipse.elements(t)
    surface = surface_geometry(elements.d)

    case height(elements.x, elements.y, surface) do
      {:ok, _zeta1, _zeta} -> -1.0
      :none -> beyond_penumbra(nearest_limb(elements, surface), elements, surface)
    end
  end

  # The angle of the point of the limb nearest the axis, by golden
  # section search about the direction of the axis.
  defp nearest_limb(%{x: x, y: y} = elements, surface) do
    towards_axis = :math.atan2(y / surface.rho1, x)
    nearest_limb(towards_axis - @limb_search, towards_axis + @limb_search, elements, surface)
  end

  defp nearest_limb(low, high, _elements, _surface) when high - low < @edge_tolerance do
    (low + high) / 2
  end

  defp nearest_limb(low, high, elements, surface) do
    step = (high - low) * @golden_section
    left = low + step
    right = high - step

    if beyond_penumbra(left, elements, surface) < beyond_penumbra(right, elements, surface) do
      nearest_limb(low, right, elements, surface)
    else
      nearest_limb(left, high, elements, surface)
    end
  end

  # Where the penumbra's edge meets the Earth's limb at a moment, the
  # places on the horizon where the partial eclipse begins or ends. On
  # the plane the limb is `(cos θ, ρ1 sin θ)`, a unit circle once `η` is
  # scaled, and the edge meets it near the two points where a circle of
  # the penumbra's radius about the axis meets the unit circle; Newton's
  # method finds each from there. A place where the shadow is leaving
  # and the ground turning into the day sees the eclipse end at sunrise;
  # one where the shadow is arriving and the ground turning into the
  # night sees it begin at sunset. The two crossings are told apart by
  # the side of the line from the axis to the Earth's centre they lie
  # on, which changes continuously while they exist.
  defp horizon_contacts(t, elements, rates, surface) do
    %{x: x, y: y, l1: l1} = elements
    eta1 = y / surface.rho1
    distance = :math.sqrt(x * x + eta1 * eta1)
    cosine = (1 + distance * distance - l1 * l1) / (2 * distance)

    if abs(cosine) >= 1.0 do
      []
    else
      towards_axis = :math.atan2(eta1, x)
      spread = :math.acos(cosine)

      [{:plus, towards_axis + spread}, {:minus, towards_axis - spread}]
      |> Enum.map(fn {branch, theta} -> {branch, limb_crossing(theta, elements, surface)} end)
      |> Enum.flat_map(&horizon_contact(&1, t, elements, rates, surface))
    end
  end

  defp horizon_contact({_branch, :none}, _t, _elements, _rates, _surface) do
    []
  end

  defp horizon_contact({branch, {:ok, theta}}, t, elements, rates, surface) do
    %{x: x, y: y, d: d} = elements
    {xi, eta, zeta} = limb_point(theta, surface)
    {a, b} = relative_motion(xi, eta, zeta, elements, rates)
    arriving? = (xi - x) * a + (eta - y) * b > 0.0
    rising? = rising?(xi, eta, d, rates)
    point = horizon_point(t, xi, eta, elements, surface)

    case {rising?, arriving?} do
      {true, false} -> [{{:sunrise_limit, branch}, point}]
      {false, true} -> [{{:sunset_limit, branch}, point}]
      _inside -> []
    end
  end

  # The angle of the limb where the penumbra's edge meets it, by Newton's
  # method from the circle's estimate.
  defp limb_crossing(theta, elements, surface) do
    limb_crossing(theta, elements, surface, @newton_iterations)
  end

  defp limb_crossing(_theta, _elements, _surface, 0) do
    :none
  end

  defp limb_crossing(theta, elements, surface, iterations) do
    value = beyond_penumbra(theta, elements, surface)
    slope = (beyond_penumbra(theta + @newton_step, elements, surface) - value) / @newton_step

    cond do
      abs(value) < @edge_tolerance -> {:ok, theta}
      slope == 0.0 -> :none
      true -> limb_crossing(theta - value / slope, elements, surface, iterations - 1)
    end
  end

  # How far a point of the limb is beyond the penumbra's edge.
  defp beyond_penumbra(theta, elements, surface) do
    %{x: x, y: y, l1: l1, tan_f1: tan_f1} = elements
    {xi, eta, zeta} = limb_point(theta, surface)
    :math.sqrt((xi - x) * (xi - x) + (eta - y) * (eta - y)) - (l1 - zeta * tan_f1)
  end

  # The point of the limb at an angle, and its height above the plane.
  defp limb_point(theta, surface) do
    eta = surface.rho1 * :math.sin(theta)
    {:math.cos(theta), eta, limb_height(eta, surface)}
  end

  # The height above the plane of the limb, where `ζ1` is zero.
  defp limb_height(eta, surface) do
    -surface.rho2 * eta / surface.rho1 * surface.sin_d1_d2
  end

  # A place on the limb is turning into the day, the Sun rising, when
  # its height above the plane grows.
  defp rising?(xi, eta, d, rates) do
    -rates.mu * xi * cos(d) + rates.d * eta > 0.0
  end

  defp horizon_point(t, xi, eta, elements, surface) do
    {longitude, latitude, _hour_angle} = location(xi, eta, 0.0, elements, surface)
    %{time: t, location: %Geo.Point{coordinates: {longitude, latitude}}}
  end

  # The places on the horizon having greatest eclipse at a moment: the
  # ends of the chord across the shadow's motion through the axis, where
  # they are within the penumbra. The line depends a little on the
  # motion where the place is, so each end is found again from itself.
  defp horizon_maxima(t, elements, rates, surface) do
    observer = %{xi: elements.x, eta: elements.y, zeta: 0.0}

    for chord_end <- [:entry, :exit],
        {:ok, %{xi: xi, eta: eta}} <-
          [horizon_maximum(observer, chord_end, {elements, rates, surface}, @edge_iterations)] do
      kind =
        if rising?(xi, eta, elements.d, rates) do
          :maximum_at_sunrise
        else
          :maximum_at_sunset
        end

      {{kind, chord_end}, horizon_point(t, xi, eta, elements, surface)}
    end
  end

  defp horizon_maximum(observer, _chord_end, _context, 0) do
    {:ok, observer}
  end

  defp horizon_maximum(observer, chord_end, {elements, rates, surface} = context, iterations) do
    line = edge_line(observer, elements, rates, 1.0, :none, :penumbra)

    with {:ok, entry, exit} <- chord(line, surface),
         {:ok, next} <- within_penumbra(chord_point(chord_end, entry, exit), line, surface) do
      horizon_maximum(next, chord_end, context, iterations - 1)
    end
  end

  defp chord_point(:entry, entry, _exit) do
    entry
  end

  defp chord_point(:exit, _entry, exit) do
    exit
  end

  defp within_penumbra(distance, line, surface) do
    if beyond_edge(distance, line, surface) < 0.0 do
      {:ok, point_on_line(distance, line, surface)}
    else
      :none
    end
  end

  # Just after the shadow reaches the Earth the part of the line on the
  # Earth and within the shadow is a sliver at the limb. The first step
  # takes the line straight across the motion at the axis, the same line
  # for both sides, so that both edges are found or neither is; turning
  # it for the motion at the edge can then take it off the Earth, and
  # the edge found before is kept.
  defp edge(_observer, _context, 0, found) do
    found
  end

  defp edge(observer, context, iterations, found) do
    {elements, rates, surface, side, cone} = context
    line = edge_line(observer, elements, rates, side, found, cone)

    case edge_on_line(line, surface) do
      {kind, next} when kind in [:limit, :horizon] ->
        edge(next, context, iterations - 1, {:ok, kind, next})

      :none ->
        found
    end
  end

  defp edge_on_line(line, surface) do
    with {:ok, entry, exit} <- chord(line, surface) do
      edge_on_chord(entry, exit, line, surface)
    end
  end

  # The line from the axis towards the edge on one side, as the axis,
  # the unit direction, and what gives the cone's radius at a height.
  defp edge_line(observer, elements, rates, side, found, cone) do
    %{xi: xi, eta: eta, zeta: zeta} = observer
    %{x: x, y: y} = elements
    shadow = cone(cone, elements, rates)
    {a, b} = relative_motion(xi, eta, zeta, elements, rates)
    speed = :math.sqrt(a * a + b * b)
    along = turn(found, observer, elements, rates, speed, shadow)
    across = side * :math.sqrt(1 - along * along)

    %{
      x: x,
      y: y,
      direction_x: (-along * a - across * b) / speed,
      direction_y: (-along * b + across * a) / speed,
      l: shadow.l,
      tan_f: shadow.tan_f
    }
  end

  # The radius on the plane, the slope and the rate of change of the
  # radius of the umbra or the penumbra.
  defp cone(:umbra, elements, rates) do
    %{l: elements.l2, tan_f: elements.tan_f2, rate: rates.l2}
  end

  defp cone(:penumbra, elements, rates) do
    %{l: elements.l1, tan_f: elements.tan_f1, rate: rates.l1}
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
      beyond_edge(exit, line, surface) < 0.0 -> {:horizon, point_on_line(exit, line, surface)}
      true -> {:limit, bisect_edge(inside, exit, line, surface)}
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
    abs(line.l - zeta * line.tan_f)
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
  defp turn(:none, _observer, _elements, _rates, _speed, _shadow) do
    0.0
  end

  defp turn({:ok, _kind, _edge}, observer, elements, rates, speed, shadow) do
    %{xi: xi, eta: eta, zeta: zeta} = observer
    radius = shadow.l - zeta * shadow.tan_f
    height_rate = -rates.mu * xi * cos(elements.d) + rates.d * eta
    radius_rate = shadow.rate - height_rate * shadow.tan_f

    clamp(sign(radius) * radius_rate / speed, -1.0, 1.0)
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
      l1: (later.l1 - before.l1) / interval,
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
