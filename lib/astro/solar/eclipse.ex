defmodule Astro.Solar.Eclipse do
  @moduledoc """
  Solar eclipses: finding them, classifying them and measuring them,
  from the Besselian elements of the Moon's shadow.

  A solar eclipse can only happen at a new moon near a node of the
  Moon's orbit, when the shadow the Moon casts away from the Sun falls
  on the Earth. The shadow is two cones with a common axis, the line
  through the centres of the Sun and the Moon: the penumbra, from which
  some of the Sun is seen, and the umbra, from which none of it is. The
  umbra narrows to a vertex about as far from the Moon as the Earth is;
  beyond it, the antumbra, the Moon is seen inside the Sun's disk.

  ### The Besselian elements

  The shadow is described on the *fundamental plane*, through the
  centre of the Earth and perpendicular to the shadow axis, with the
  Earth's equatorial radius as the unit of length. At any instant the
  Besselian elements give:

  * `x` and `y`, where the axis crosses the plane, with `y` towards
    the north and `x` towards the east.

  * `d` and `μ`, the declination and Greenwich hour angle of the axis,
    which turn the plane into places on the Earth.

  * `l1` and `l2`, the radii of the penumbra and the umbra on the
    plane, `l2` negative where the umbra reaches beyond it.

  * `tan f1` and `tan f2`, the slopes of the two cones, which give
    their radii at an observer's distance above the plane.

  `elements/1` computes them from the Sun's and the Moon's apparent
  geocentric positions and distances, the method of the *Explanatory
  Supplement*: the axis is the direction from the Moon to the Sun, the
  Moon's position is turned into the frame of the plane, and the cones
  follow from the radii of the Sun and the Moon. The Moon's radius is
  `k1 = 0.272488` Earth radii for the penumbra and `k2 = 0.272281`, a
  mean below the peaks of its limb, for the umbra, as NASA's catalogues
  use them, so that a total phase is not overstated.

  NASA publishes `μ` as an *ephemeris* hour angle, computed as if
  Terrestrial Time were Universal Time, and an observer's longitude is
  corrected by ΔT to use it. `elements/1` returns the Greenwich hour
  angle at the moment itself, which needs no correction, so the two
  differ by ΔT's worth of the Earth's rotation, about 0.29° in 2024.

  ### Greatest eclipse, gamma and the type

  *Greatest eclipse* is the moment the shadow axis passes closest to
  the centre of the Earth, the least `√(x² + y²)`, found by golden
  section search around each new moon. *Gamma* is that distance,
  positive when the axis passes north of the centre.

  On the plane the Earth is an ellipse, of semi-axes 1 and
  `√(1 − e² cos² d)` for the Earth's flattening. Where the axis meets
  it, the eclipse is *central*, and its kind depends on the umbra where
  the axis meets the surface, at a height `ζ` above the plane: total
  where `l2 − ζ tan f2` is negative, annular where it is positive. The
  point of greatest eclipse is nearer the Sun than the limb, where the
  central line begins and ends, so a total eclipse whose umbra stops
  short of the surface at either end is *hybrid*. Where the axis
  misses the Earth but the umbra or antumbra still reaches it, the
  eclipse is total or annular without a central line; where only the
  penumbra does, it is partial.

  ### Magnitude

  For a central eclipse the magnitude is the ratio of the Moon's
  apparent diameter to the Sun's at the point of greatest eclipse,
  `(L1 − L2) / (L1 + L2)`, where `L1` and `L2` are the cones' radii
  there. Otherwise it is the fraction of the Sun's diameter covered at
  the point of the Earth's limb nearest the axis, `(l1 − Δ) / (l1 + l2)`,
  where `Δ` is that point's distance from the axis; NASA's catalogues
  use it for a total or annular eclipse without a central line too.

  How an eclipse is seen from a place, its local circumstances, is
  computed from the same elements by `Astro.Solar.Eclipse.Local`.

  The Sun's and the Moon's apparent geocentric positions and distances
  are those of `Astro.sun_position_at/1` and `Astro.moon_position_at/1`:
  from the JPL ephemeris where the loaded kernel covers the moment, and
  from the analytical series elsewhere.

  """

  alias Astro.{Earth, Lunar, Math, Solar, Time}

  import Astro.Math, only: [sin: 1, cos: 1, atan: 2, asin: 1]

  @typedoc """
  The kind of solar eclipse: only the penumbra reaches the Earth, the
  antumbra does, the umbra does, or the shadow changes from one to the
  other along its path.

  """
  @type eclipse_type :: :partial | :annular | :total | :hybrid

  @typedoc """
  The Besselian elements of the Moon's shadow at a moment. Lengths are
  in equatorial radii of the Earth and angles in degrees.

  """
  @type elements :: %{
          x: float(),
          y: float(),
          d: float(),
          mu: float(),
          l1: float(),
          l2: float(),
          tan_f1: float(),
          tan_f2: float()
        }

  @typedoc """
  A solar eclipse. Greatest eclipse is a UTC `t:DateTime.t/0`.

  """
  @type t :: %__MODULE__{
          type: eclipse_type(),
          greatest: DateTime.t(),
          gamma: float(),
          magnitude: float()
        }

  defstruct [:type, :greatest, :gamma, :magnitude]

  # The Moon's radius in Earth radii for the penumbra and for the umbra.
  @penumbral_k 0.272488
  @umbral_k 0.272281

  # The Sun's semi-diameter at one astronomical unit, in arc seconds.
  @solar_semi_diameter_at_one_au 959.63

  @arc_seconds_per_radian 206_264.80624709636

  # The square of the eccentricity of the Earth's meridian ellipse (WGS 84).
  @earth_eccentricity_squared 0.00669438

  # Greatest eclipse is searched for within this many days of a new moon,
  # and a new moon is skipped when the shadow axis is further from the
  # Earth than its reach by more than the axis can close in that time.
  @days_around_new_moon 0.25
  @least_distance_fraction 0.99

  # Every eclipse season has a solar eclipse, so one is found within a year.
  @lunations_searched 13

  @search_tolerance_days 1.0e-8

  # The ends of the central line are bracketed in steps of an hour and
  # found to a tenth of a second; the umbra changes slowly.
  @central_line_step_days 1 / 24
  @central_line_tolerance_days 1.0e-6

  @doc """
  Returns the Besselian elements of the Moon's shadow at a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0`.

  ### Returns

  * A map with these keys, lengths in equatorial radii of the Earth and
    angles in degrees:

    * `:x` and `:y` — where the shadow axis crosses the fundamental
      plane, `:y` towards the north.

    * `:d` — the declination of the shadow axis.

    * `:mu` — the Greenwich hour angle of the shadow axis.

    * `:l1` and `:l2` — the radii of the penumbra and the umbra on the
      plane, `:l2` negative where the umbra reaches beyond it.

    * `:tan_f1` and `:tan_f2` — the slopes of the penumbral and umbral
      cones.

  ### Examples

  At 18:00 TD on 8 April 2024, 17:58:51 UT, NASA's elements are
  `x = −0.318157` and `y = 0.219747`:

      iex> elements = Astro.Solar.Eclipse.elements(739_349.749199)
      iex> {Float.round(elements.x, 3), Float.round(elements.y, 3)}
      {-0.318, 0.22}

  """
  @spec elements(Time.moment()) :: elements()
  def elements(t) do
    earth_m = Earth.earth_radius_m()
    {sun_ra, sun_dec, sun_au} = Solar.solar_position(t)
    {moon_ra, moon_dec, moon_m} = Lunar.lunar_position(t)

    sun_distance = Math.au_to_m(sun_au) / earth_m
    moon_distance = moon_m / earth_m

    # The shadow axis points from the Moon to the Sun.
    {sun_x, sun_y, sun_z} = rectangular(sun_ra, sun_dec, sun_distance)
    {moon_x, moon_y, moon_z} = rectangular(moon_ra, moon_dec, moon_distance)
    {axis_x, axis_y, axis_z} = {sun_x - moon_x, sun_y - moon_y, sun_z - moon_z}
    axis_length = :math.sqrt(axis_x * axis_x + axis_y * axis_y + axis_z * axis_z)

    axis_ra = atan(axis_y, axis_x)
    d = asin(axis_z / axis_length)
    hour_angle = moon_ra - axis_ra

    # The Moon in the frame of the fundamental plane.
    x = moon_distance * cos(moon_dec) * sin(hour_angle)

    y =
      moon_distance *
        (sin(moon_dec) * cos(d) - cos(moon_dec) * sin(d) * cos(hour_angle))

    z =
      moon_distance *
        (sin(moon_dec) * sin(d) + cos(moon_dec) * cos(d) * cos(hour_angle))

    sun_radius =
      @solar_semi_diameter_at_one_au / @arc_seconds_per_radian * Math.au_to_m(1.0) / earth_m

    tan_f1 = tangent_of_cone((sun_radius + @penumbral_k) / axis_length)
    tan_f2 = tangent_of_cone((sun_radius - @umbral_k) / axis_length)

    %{
      x: x,
      y: y,
      d: d,
      mu: Math.mod(Time.apparent_sidereal_from_moment(t) - axis_ra, 360.0),
      l1: z * tan_f1 + @penumbral_k * :math.sqrt(1 + tan_f1 * tan_f1),
      l2: z * tan_f2 - @umbral_k * :math.sqrt(1 + tan_f2 * tan_f2),
      tan_f1: tan_f1,
      tan_f2: tan_f2
    }
  end

  @doc """
  Returns the circumstances of the first solar eclipse whose greatest
  eclipse is at or after a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` within 50,000 years of J2000.

  ### Returns

  * `{:ok, circumstances}`, a map with the keys of `t:t/0`, greatest
    eclipse a moment.

  * `{:error, :no_eclipse}` if none is found within 13 lunations, which
    does not happen.

  ### Examples

      iex> {:ok, eclipse} = Astro.Solar.Eclipse.eclipse_at_or_after(739_300.0)
      iex> {eclipse.type, Float.round(eclipse.gamma, 3)}
      {:total, 0.343}

  """
  @spec eclipse_at_or_after(Time.moment()) :: {:ok, map()} | {:error, :no_eclipse}
  def eclipse_at_or_after(t) do
    new_moon = Lunar.date_time_new_moon_at_or_after(t - @days_around_new_moon)
    search(new_moon, t, :forward, @lunations_searched)
  end

  @doc """
  Returns the circumstances of the last solar eclipse whose greatest
  eclipse is before a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` within 50,000 years of J2000.

  ### Returns

  * `{:ok, circumstances}`, a map with the keys of `t:t/0`, greatest
    eclipse a moment.

  * `{:error, :no_eclipse}` if none is found within 13 lunations, which
    does not happen.

  ### Examples

      iex> {:ok, eclipse} = Astro.Solar.Eclipse.eclipse_before(739_400.0)
      iex> eclipse.type
      :total

  """
  @spec eclipse_before(Time.moment()) :: {:ok, map()} | {:error, :no_eclipse}
  def eclipse_before(t) do
    new_moon = Lunar.date_time_new_moon_before(t + @days_around_new_moon)
    search(new_moon, t, :backward, @lunations_searched)
  end

  defp search(_new_moon, _t, _direction, 0) do
    {:error, :no_eclipse}
  end

  defp search(new_moon, t, direction, lunations) do
    case eclipse_at_new_moon(new_moon) do
      {:ok, %{greatest: greatest} = eclipse} when direction == :forward and greatest >= t ->
        {:ok, eclipse}

      {:ok, %{greatest: greatest} = eclipse} when direction == :backward and greatest < t ->
        {:ok, eclipse}

      _no_eclipse_or_wrong_side ->
        search(next_new_moon(new_moon, direction), t, direction, lunations - 1)
    end
  end

  defp next_new_moon(new_moon, :forward) do
    Lunar.date_time_new_moon_at_or_after(new_moon + 1.0)
  end

  defp next_new_moon(new_moon, :backward) do
    Lunar.date_time_new_moon_before(new_moon - 1.0)
  end

  defp eclipse_at_new_moon(new_moon) do
    at_new_moon = elements(new_moon)

    if @least_distance_fraction * axis_distance(at_new_moon) < 1.0 + at_new_moon.l1 do
      greatest =
        least_distance(new_moon - @days_around_new_moon, new_moon + @days_around_new_moon)

      circumstances(greatest, elements(greatest))
    else
      :none
    end
  end

  defp axis_distance(%{x: x, y: y}) do
    :math.sqrt(x * x + y * y)
  end

  defp least_distance(a, b) when b - a < @search_tolerance_days do
    (a + b) / 2
  end

  defp least_distance(a, b) do
    step = (b - a) * 0.381966011250105
    left = a + step
    right = b - step

    if axis_distance(elements(left)) < axis_distance(elements(right)) do
      least_distance(a, right)
    else
      least_distance(left, b)
    end
  end

  # Where the shadow axis meets the Earth the eclipse is central, and
  # the umbra is measured at the surface; elsewhere the shadow is
  # measured at the point of the limb nearest the axis.
  defp circumstances(greatest, elements) do
    gamma = north_or_south(elements.y) * axis_distance(elements)

    case surface(elements) do
      {:central, height} ->
        {:ok, central(greatest, elements, height, gamma)}

      {:limb, limb_distance} ->
        non_central(greatest, elements, limb_distance, gamma)
    end
  end

  defp central(greatest, elements, height, gamma) do
    %{l1: l1, l2: l2, tan_f1: tan_f1, tan_f2: tan_f2} = elements
    penumbra = l1 - height * tan_f1
    umbra = l2 - height * tan_f2

    %{
      type: central_type(greatest, umbra),
      greatest: greatest,
      gamma: gamma,
      magnitude: (penumbra - umbra) / (penumbra + umbra)
    }
  end

  defp central_type(_greatest, umbra) when umbra > 0.0 do
    :annular
  end

  defp central_type(greatest, _umbra) do
    if annular_at_an_end?(greatest) do
      :hybrid
    else
      :total
    end
  end

  # At the ends of the central line the axis grazes the limb, the
  # height above the plane is zero, and the umbra's radius is `l2`.
  defp annular_at_an_end?(greatest) do
    Enum.any?([:before, :after], fn side ->
      central_line_end(greatest, side).l2 > 0.0
    end)
  end

  defp non_central(greatest, %{l1: l1, l2: l2}, limb_distance, gamma) do
    if limb_distance < l1 do
      {:ok,
       %{
         type: non_central_type(limb_distance, l2),
         greatest: greatest,
         gamma: gamma,
         magnitude: (l1 - limb_distance) / (l1 + l2)
       }}
    else
      :none
    end
  end

  defp non_central_type(limb_distance, l2) when limb_distance < abs(l2) do
    umbral_type(l2)
  end

  defp non_central_type(_limb_distance, _l2) do
    :partial
  end

  defp umbral_type(l2) when l2 < 0.0 do
    :total
  end

  defp umbral_type(_l2) do
    :annular
  end

  # The Earth on the fundamental plane is an ellipse of semi-axes 1 and
  # ρ1. Scaling `y` by ρ1 makes it a unit circle; inside it the height of
  # the surface above the plane follows from the Explanatory
  # Supplement's auxiliary declinations d1 and d2.
  defp surface(%{x: x, y: y, d: d}) do
    rho1 = :math.sqrt(1 - @earth_eccentricity_squared * cos(d) * cos(d))
    y1 = y / rho1
    radius_squared = x * x + y1 * y1

    if radius_squared < 1.0 do
      rho2 = :math.sqrt(1 - @earth_eccentricity_squared * sin(d) * sin(d))
      sin_d1_d2 = @earth_eccentricity_squared * sin(d) * cos(d) / (rho1 * rho2)
      cos_d1_d2 = :math.sqrt(1 - sin_d1_d2 * sin_d1_d2)
      zeta1 = :math.sqrt(1 - radius_squared)
      {:central, rho2 * (zeta1 * cos_d1_d2 - y1 * sin_d1_d2)}
    else
      {:limb, :math.sqrt(x * x + y * y) * (1 - 1 / :math.sqrt(radius_squared))}
    end
  end

  defp central?(elements) do
    match?({:central, _height}, surface(elements))
  end

  defp central_line_end(greatest, side) do
    {inside, outside} = central_line_bracket(greatest, side, greatest)
    elements(bisect_central_line_end(inside, outside))
  end

  defp central_line_bracket(greatest, side, inside) do
    outside = step(inside, side)

    if central?(elements(outside)) and abs(outside - greatest) < @days_around_new_moon do
      central_line_bracket(greatest, side, outside)
    else
      {inside, outside}
    end
  end

  defp step(t, :before) do
    t - @central_line_step_days
  end

  defp step(t, :after) do
    t + @central_line_step_days
  end

  defp bisect_central_line_end(inside, outside)
       when abs(outside - inside) < @central_line_tolerance_days do
    (inside + outside) / 2
  end

  defp bisect_central_line_end(inside, outside) do
    middle = (inside + outside) / 2

    if central?(elements(middle)) do
      bisect_central_line_end(middle, outside)
    else
      bisect_central_line_end(inside, middle)
    end
  end

  defp north_or_south(y) when y < 0.0 do
    -1.0
  end

  defp north_or_south(_y) do
    1.0
  end

  defp rectangular(right_ascension, declination, distance) do
    {
      distance * cos(declination) * cos(right_ascension),
      distance * cos(declination) * sin(right_ascension),
      distance * sin(declination)
    }
  end

  defp tangent_of_cone(sine) do
    sine / :math.sqrt(1 - sine * sine)
  end
end
