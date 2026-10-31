defmodule Astro.Lunar.Eclipse do
  @moduledoc """
  Finds lunar eclipses and computes their circumstances.

  This module is the implementation behind `Astro.lunar_eclipse_at_or_after/2`
  and `Astro.lunar_eclipse_before/2`, and works in moments (see
  `t:Astro.Time.moment/0`).

  ## The Earth's shadow

  The Earth casts two shadows away from the Sun. The *umbra* is the cone
  in which the Sun is wholly hidden by the Earth; the *penumbra* is the
  wider cone in which it is partly hidden. At the Moon's distance both
  are circles centred on the *shadow axis*, the point opposite the Sun,
  and a lunar eclipse is the Moon passing through them. It can only
  happen at a full moon, and only near a node of the Moon's orbit,
  because otherwise the Moon passes north or south of both circles.

  Seen from the centre of the Earth, the radii of the two circles are

      penumbra  Rp = 1.01 πm + ss + πs
      umbra     Ru = 1.01 πm − ss + πs

  where `πm` and `πs` are the Moon's and the Sun's equatorial horizontal
  parallaxes, the angles the Earth's equatorial radius subtends at each,
  and `ss` is the Sun's angular semi-diameter. The factor `1.01` is
  Danjon's enlargement of the shadows for the Earth's atmosphere, a layer
  about 75 km deep that stops sunlight as the solid Earth does,
  `1 + 1/85 − 1/594`, the last term for the Earth's flattening at 45°.
  This is the convention of NASA's eclipse catalogues. The older almanac
  convention, Chauvenet's, multiplies the radii by `1.02` instead,

      penumbra  Rp = 1.02 (0.99834 πm + ss + πs)
      umbra     Ru = 1.02 (0.99834 πm − ss + πs)

  which makes the umbral magnitude about 0.006 larger and can make an
  eclipse at the limit total where Danjon's makes it partial.

  ## Greatest eclipse, gamma and magnitude

  The Moon's angular distance `σ` from the shadow axis is least at
  *greatest eclipse*. *Gamma* is that least distance in equatorial
  radii of the Earth, positive when the Moon passes north of the axis.
  The *penumbral* and *umbral magnitudes* are the fractions of the Moon's
  diameter inside each shadow at greatest eclipse,

      penumbral magnitude = (Rp + sm − σ) / 2sm
      umbral magnitude    = (Ru + sm − σ) / 2sm

  where `sm` is the Moon's angular semi-diameter. An eclipse is total
  when the umbral magnitude is at least 1, partial when it is between 0
  and 1, and penumbral when only the penumbral magnitude is positive.

  ## The contacts

  The eclipse begins when the Moon's limb first touches the penumbra
  (P1) and ends when it leaves it (P4). A partial or total eclipse has
  two more contacts with the umbra, U1 and U4, and a total eclipse two
  more, U2 and U3, between which the Moon is wholly inside the umbra.
  Each is the instant `σ` equals a shadow's radius plus or minus `sm`,
  found by bisection either side of greatest eclipse.

  ## Positions

  The Sun's and the Moon's apparent geocentric positions and distances
  come from `Astro.Solar.solar_position/1` and
  `Astro.Lunar.lunar_position/1`: from the JPL ephemeris where the loaded
  kernel covers the moment, and from the analytical series elsewhere.

  """

  alias Astro.{Earth, Lunar, Math, Solar}

  import Astro.Math, only: [sin: 1, cos: 1, asin: 1]

  @typedoc """
  The convention for enlarging the Earth's shadows: Danjon's, used by
  NASA's catalogues, or Chauvenet's, the older almanac convention.

  """
  @type shadow :: :danjon | :chauvenet

  @typedoc """
  The kind of lunar eclipse: the Moon passes through the penumbra only,
  partly into the umbra, or wholly into it.

  """
  @type eclipse_type :: :penumbral | :partial | :total

  @typedoc """
  A lunar eclipse. Every instant is a UTC `t:DateTime.t/0`; the umbral
  contacts are `nil` for an eclipse that does not reach them.

  """
  @type t :: %__MODULE__{
          type: eclipse_type(),
          greatest: DateTime.t(),
          gamma: float(),
          penumbral_magnitude: float(),
          umbral_magnitude: float(),
          penumbral_begins: DateTime.t(),
          partial_begins: DateTime.t() | nil,
          total_begins: DateTime.t() | nil,
          total_ends: DateTime.t() | nil,
          partial_ends: DateTime.t() | nil,
          penumbral_ends: DateTime.t()
        }

  defstruct [
    :type,
    :greatest,
    :gamma,
    :penumbral_magnitude,
    :umbral_magnitude,
    :penumbral_begins,
    :partial_begins,
    :total_begins,
    :total_ends,
    :partial_ends,
    :penumbral_ends
  ]

  # The Moon's radius in equatorial radii of the Earth, as NASA's catalogues
  # use it for the Moon's limb.
  @lunar_k 0.272488

  # The Sun's angular semi-diameter at one astronomical unit, in arcseconds.
  @solar_semi_diameter_at_one_au 959.63

  # The shadow enlargements, as factors on the Moon's parallax and on the
  # whole radius.
  @shadows %{
    danjon: {1.01, 1.0},
    chauvenet: {0.99834, 1.02}
  }

  @full_moon 180.0

  # Greatest eclipse is within a few hours of the full moon, the opposition
  # in longitude, and is looked for this many days either side of it.
  @days_around_full_moon 0.25

  # The Moon's path across the shadow is inclined about 6° to the ecliptic,
  # so its least distance from the axis is at least this fraction of its
  # distance at full moon. A full moon farther than the penumbra by more than
  # that has no eclipse, and is passed over with one position.
  @least_distance_fraction 0.99

  # Every lunar eclipse season has a full moon within reach of the
  # penumbra, and seasons are about six lunations apart; the searches give
  # up after twice that, which no eclipse needs.
  @lunations_searched 13

  # Greatest eclipse and the contacts are found to under a millisecond.
  @search_tolerance_days 1.0e-8

  # The longest penumbral eclipse lasts about six hours, so each contact is
  # within this many days of greatest eclipse.
  @days_around_greatest 0.25

  @doc """
  Returns the geometry of the Earth's shadow and the Moon at a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0`.

  * `shadow` is the enlargement convention, `:danjon` or `:chauvenet`.

  ### Returns

  * A map with these keys, every angle in degrees:

    * `:distance` — the Moon's angular distance from the shadow axis, `σ`.

    * `:penumbra` and `:umbra` — the radii of the shadows at the Moon,
      `Rp` and `Ru`.

    * `:semi_diameter` — the Moon's angular semi-diameter, `sm`.

    * `:gamma` — `σ` in equatorial radii of the Earth at the Moon's
      distance, positive when the Moon is north of the axis.

  ### Examples

      iex> geometry = Astro.Lunar.Eclipse.geometry(739_689.2917, :danjon)
      iex> Float.round(geometry.gamma, 3)
      0.349

  """
  @spec geometry(Astro.Time.moment(), shadow()) :: %{
          distance: float(),
          penumbra: float(),
          umbra: float(),
          semi_diameter: float(),
          gamma: float()
        }
  def geometry(t, shadow) do
    {sun_ra, sun_dec, sun_au} = Solar.solar_position(t)
    {moon_ra, moon_dec, moon_m} = Lunar.lunar_position(t)
    earth_m = Earth.earth_radius_m()

    distance = separation(moon_ra, moon_dec, sun_ra + 180.0, -sun_dec)
    moon_parallax = asin(earth_m / moon_m)
    sun_parallax = asin(earth_m / Math.au_to_m(sun_au))
    sun_semi_diameter = @solar_semi_diameter_at_one_au / sun_au / 3_600.0
    {parallax_factor, enlargement} = Map.fetch!(@shadows, shadow)

    penumbra = enlargement * (parallax_factor * moon_parallax + sun_semi_diameter + sun_parallax)
    umbra = enlargement * (parallax_factor * moon_parallax - sun_semi_diameter + sun_parallax)

    %{
      distance: distance,
      penumbra: penumbra,
      umbra: umbra,
      semi_diameter: asin(@lunar_k * earth_m / moon_m),
      gamma: north_or_south(moon_dec, sun_dec) * moon_m * sin(distance) / earth_m
    }
  end

  @doc """
  Returns the circumstances of the first lunar eclipse whose greatest
  eclipse is at or after a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` within 50,000 years of J2000.

  * `shadow` is the enlargement convention, `:danjon` or `:chauvenet`.

  ### Returns

  * `{:ok, circumstances}`, a map with the keys of `t:t/0`, every
    instant a moment and every missing contact `nil`.

  * `{:error, :no_eclipse}` if none is found within 13 lunations, which
    does not happen.

  ### Examples

      iex> {:ok, eclipse} = Astro.Lunar.Eclipse.eclipse_at_or_after(739_600.0, :danjon)
      iex> {eclipse.type, Float.round(eclipse.umbral_magnitude, 3)}
      {:total, 1.178}

  """
  @spec eclipse_at_or_after(Astro.Time.moment(), shadow()) ::
          {:ok, map()} | {:error, :no_eclipse}
  def eclipse_at_or_after(t, shadow) do
    full_moon = Lunar.date_time_lunar_phase_at_or_after(t - @days_around_full_moon, @full_moon)
    search(full_moon, t, shadow, :forward, @lunations_searched)
  end

  @doc """
  Returns the circumstances of the last lunar eclipse whose greatest
  eclipse is before a moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` within 50,000 years of J2000.

  * `shadow` is the enlargement convention, `:danjon` or `:chauvenet`.

  ### Returns

  * `{:ok, circumstances}`, a map with the keys of `t:t/0`, every
    instant a moment and every missing contact `nil`.

  * `{:error, :no_eclipse}` if none is found within 13 lunations, which
    does not happen.

  ### Examples

      iex> {:ok, eclipse} = Astro.Lunar.Eclipse.eclipse_before(739_700.0, :danjon)
      iex> eclipse.type
      :total

  """
  @spec eclipse_before(Astro.Time.moment(), shadow()) ::
          {:ok, map()} | {:error, :no_eclipse}
  def eclipse_before(t, shadow) do
    full_moon = Lunar.date_time_lunar_phase_at_or_before(t + @days_around_full_moon, @full_moon)
    search(full_moon, t, shadow, :backward, @lunations_searched)
  end

  # Tries one full moon after another until one has an eclipse on the
  # right side of `t`.
  defp search(_full_moon, _t, _shadow, _direction, 0) do
    {:error, :no_eclipse}
  end

  defp search(full_moon, t, shadow, direction, lunations) do
    case eclipse_at_full_moon(full_moon, shadow) do
      {:ok, %{greatest: greatest} = eclipse} when direction == :forward and greatest >= t ->
        {:ok, eclipse}

      {:ok, %{greatest: greatest} = eclipse} when direction == :backward and greatest < t ->
        {:ok, eclipse}

      _no_eclipse_or_wrong_side ->
        search(next_full_moon(full_moon, direction), t, shadow, direction, lunations - 1)
    end
  end

  defp next_full_moon(full_moon, :forward) do
    Lunar.date_time_lunar_phase_at_or_after(full_moon + 1.0, @full_moon)
  end

  defp next_full_moon(full_moon, :backward) do
    Lunar.date_time_lunar_phase_at_or_before(full_moon - 1.0, @full_moon)
  end

  # The eclipse at a full moon, if the Moon reaches the penumbra.
  defp eclipse_at_full_moon(full_moon, shadow) do
    at_full_moon = geometry(full_moon, shadow)

    if @least_distance_fraction * at_full_moon.distance < penumbral_reach(at_full_moon) do
      greatest =
        least_distance(
          full_moon - @days_around_full_moon,
          full_moon + @days_around_full_moon,
          shadow
        )

      eclipse_at_greatest(greatest, geometry(greatest, shadow), shadow)
    else
      :none
    end
  end

  defp eclipse_at_greatest(greatest, %{distance: distance} = at_greatest, shadow) do
    if distance < penumbral_reach(at_greatest) do
      {:ok, circumstances(greatest, at_greatest, shadow)}
    else
      :none
    end
  end

  # The Moon's distance from the axis at which its limb touches the penumbra.
  defp penumbral_reach(%{penumbra: penumbra, semi_diameter: semi_diameter}) do
    penumbra + semi_diameter
  end

  # The moment of least distance from the axis in `[a, b]`, by golden
  # section search.
  defp least_distance(a, b, _shadow) when b - a < @search_tolerance_days do
    (a + b) / 2
  end

  defp least_distance(a, b, shadow) do
    step = (b - a) * 0.381966011250105
    left = a + step
    right = b - step

    if geometry(left, shadow).distance < geometry(right, shadow).distance do
      least_distance(a, right, shadow)
    else
      least_distance(left, b, shadow)
    end
  end

  # Gamma, the magnitudes, the type and the contacts of an eclipse from its
  # geometry at greatest eclipse.
  defp circumstances(greatest, at_greatest, shadow) do
    %{distance: distance, penumbra: penumbra, umbra: umbra, semi_diameter: semi_diameter} =
      at_greatest

    umbral_magnitude = (umbra + semi_diameter - distance) / (2 * semi_diameter)

    %{
      type: eclipse_type(umbral_magnitude),
      greatest: greatest,
      gamma: at_greatest.gamma,
      penumbral_magnitude: (penumbra + semi_diameter - distance) / (2 * semi_diameter),
      umbral_magnitude: umbral_magnitude,
      penumbral_begins: contact(greatest, at_greatest, {:penumbra, 1.0}, :before, shadow),
      partial_begins: contact(greatest, at_greatest, {:umbra, 1.0}, :before, shadow),
      total_begins: contact(greatest, at_greatest, {:umbra, -1.0}, :before, shadow),
      total_ends: contact(greatest, at_greatest, {:umbra, -1.0}, :after, shadow),
      partial_ends: contact(greatest, at_greatest, {:umbra, 1.0}, :after, shadow),
      penumbral_ends: contact(greatest, at_greatest, {:penumbra, 1.0}, :after, shadow)
    }
  end

  defp eclipse_type(umbral_magnitude) when umbral_magnitude >= 1.0 do
    :total
  end

  defp eclipse_type(umbral_magnitude) when umbral_magnitude > 0.0 do
    :partial
  end

  defp eclipse_type(_umbral_magnitude) do
    :penumbral
  end

  # A contact is the moment the Moon's limb meets a shadow's edge: its
  # centre at the shadow's radius plus the Moon's semi-diameter (the outer
  # contacts) or less it (the inner contacts, U2 and U3). `nil` when the
  # Moon is outside that circle even at greatest eclipse.
  defp contact(greatest, at_greatest, edge, side, shadow) do
    if inside?(at_greatest, edge) do
      bracket(greatest, side)
      |> bisect_contact(edge, side, shadow)
    else
      nil
    end
  end

  defp inside?(geometry, {radius, limb}) do
    geometry.distance < Map.fetch!(geometry, radius) + limb * geometry.semi_diameter
  end

  defp bracket(greatest, :before) do
    {greatest - @days_around_greatest, greatest}
  end

  defp bracket(greatest, :after) do
    {greatest, greatest + @days_around_greatest}
  end

  # The bracket has the Moon outside the circle at one end and inside it at
  # the other, at greatest eclipse.
  defp bisect_contact({a, b}, _edge, _side, _shadow) when b - a < @search_tolerance_days do
    (a + b) / 2
  end

  defp bisect_contact({a, b}, edge, side, shadow) do
    middle = (a + b) / 2
    inside = inside?(geometry(middle, shadow), edge)

    if inside == (side == :before) do
      bisect_contact({a, middle}, edge, side, shadow)
    else
      bisect_contact({middle, b}, edge, side, shadow)
    end
  end

  # The angle between two points on the sky, by the haversine formula,
  # which stays precise for the small angles an eclipse needs.
  defp separation(ra1, dec1, ra2, dec2) do
    haversine =
      sin((dec1 - dec2) / 2) ** 2 + cos(dec1) * cos(dec2) * sin((ra1 - ra2) / 2) ** 2

    2 * asin(:math.sqrt(haversine))
  end

  # The shadow axis is at declination `−sun_dec`; the Moon is north of it
  # when its declination is greater.
  defp north_or_south(moon_dec, sun_dec) when moon_dec + sun_dec >= 0 do
    1.0
  end

  defp north_or_south(_moon_dec, _sun_dec) do
    -1.0
  end
end
