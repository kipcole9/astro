defmodule Astro.Solar.Eclipse.Local do
  @moduledoc """
  The local circumstances of a solar eclipse: how it is seen from a
  place on the Earth.

  The Besselian elements (see `Astro.Solar.Eclipse`) describe the
  Moon's shadow on the fundamental plane. An observer is put in the
  same frame: at a moment, with the shadow axis at declination `d` and
  local hour angle `H = μ + λ` for an east longitude `λ`, the observer
  is at

  * `ξ = ρ cos φ′ sin H`,

  * `η = ρ sin φ′ cos d − ρ cos φ′ sin d cos H`, and

  * `ζ = ρ sin φ′ sin d + ρ cos φ′ cos d cos H`,

  where `ρ sin φ′` and `ρ cos φ′` are the observer's geocentric
  coordinates, from the geodetic latitude `φ`, the Earth's flattening
  and the height above the ellipsoid. `ζ` is the observer's height
  above the plane, where the shadow cones have radii
  `L1 = l1 − ζ tan f1` and `L2 = l2 − ζ tan f2`, and the observer is
  `m = √((x − ξ)² + (y − η)²)` from the axis.

  * The eclipse is seen where `m < L1`, inside the penumbra.

  * *Maximum eclipse* is the moment of least `m`, found by golden
    section search.

  * The *contacts* are the moments the observer crosses a cone: first
    and last contact where `m = L1`, and second and third where
    `m = |L2|`, inside the umbra (total, `L2 < 0`) or the antumbra
    (annular, `L2 > 0`). Each is found by bisection.

  * The *magnitude* at maximum is the fraction of the Sun's diameter
    covered, measured along the line through the centres of the two
    disks, `(L1 − m) / (L1 + L2)`. It exceeds 1 inside the umbra. This
    is the local magnitude NASA and the USNO give; the magnitude of a
    central eclipse in the catalogues is the ratio of the Moon's
    apparent diameter to the Sun's on the central line instead.

  * The *obscuration* is the fraction of the Sun's area covered: the
    Sun and the Moon are disks of radii `(L1 + L2) / 2` and
    `(L1 − L2) / 2` on the plane, `m` apart, and the obscuration is the
    area they share over the Sun's.

  * The Sun's *altitude* is that of the shadow axis,
    `sin h = sin d sin φ + cos d cos φ cos H`, which differs from the
    Sun's direction by a few arc seconds. It is geometric: refraction,
    which lifts the Sun by about 34′ at the horizon, is not applied.

  The elements are geocentric, so the geometry is the same whether or
  not the Sun is above the horizon. An eclipse is *seen* from a place
  if at some moment between first and last contact the Sun's upper
  limb is above the horizon, allowing for standard refraction, which is
  the condition for sunrise.

  Because `μ` is the Greenwich hour angle at the moment, the observer's
  longitude is used as it is. NASA's and the USNO's elements use an
  ephemeris hour angle and correct the longitude by ΔT instead; the two
  agree when they use the same ΔT.

  """

  alias Astro.{Earth, Time}
  alias Astro.Solar.Eclipse

  import Astro.Math, only: [sin: 1, cos: 1, asin: 1]

  @typedoc """
  How a solar eclipse is seen from a place: only the penumbra passes
  over it, the antumbra does, or the umbra does.

  """
  @type eclipse_type :: :partial | :annular | :total

  @typedoc """
  The local circumstances of a solar eclipse. The contacts and maximum
  eclipse are `t:DateTime.t/0`s, `nil` for the contacts the eclipse
  does not have there; the Sun's altitudes are geometric, in degrees,
  keyed by the contact.

  """
  @type t :: %__MODULE__{
          type: eclipse_type(),
          partial_begins: DateTime.t(),
          annular_begins: DateTime.t() | nil,
          total_begins: DateTime.t() | nil,
          maximum: DateTime.t(),
          total_ends: DateTime.t() | nil,
          annular_ends: DateTime.t() | nil,
          partial_ends: DateTime.t(),
          magnitude: float(),
          obscuration: float(),
          sun_altitudes: %{atom() => float()}
        }

  defstruct [
    :type,
    :partial_begins,
    :annular_begins,
    :total_begins,
    :maximum,
    :total_ends,
    :annular_ends,
    :partial_ends,
    :magnitude,
    :obscuration,
    :sun_altitudes
  ]

  # The ratio of the Earth's polar radius to its equatorial radius.
  @polar_ratio 0.99664719

  # Every phase of a solar eclipse at a place lies within six hours of
  # greatest eclipse.
  @days_around_greatest 0.25

  # Maximum and the contacts are found to about a millisecond.
  @search_tolerance_days 1.0e-8

  # The golden section of an interval.
  @golden_section 0.381966011250105

  # The Sun has risen when its centre, without refraction, is 50′ below
  # the horizon: 34′ of refraction and 16′ of semi-diameter.
  @sunrise_altitude -50 / 60

  @doc """
  Returns the local circumstances at a location of the solar eclipse
  whose greatest eclipse is at a moment.

  ### Arguments

  * `greatest` is the `t:Astro.Time.moment/0` of greatest eclipse, as
    `Astro.Solar.Eclipse.eclipse_at_or_after/1` returns it.

  * `location` is a `t:Geo.PointZ.t/0`, its altitude in metres above
    the ellipsoid.

  ### Returns

  * `{:ok, circumstances}`, a map with the keys of `t:t/0`, the
    contacts and maximum as moments.

  * `{:error, :not_visible}` if the location is outside the penumbra
    throughout, or the Sun is below the horizon from first contact to
    last.

  ### Examples

  Dallas saw totality on 8 April 2024:

      iex> {:ok, eclipse} = Astro.Solar.Eclipse.eclipse_at_or_after(739_300.0)
      iex> dallas = %Geo.PointZ{coordinates: {-96.80, 32.78, 0.0}}
      iex> {:ok, local} = Astro.Solar.Eclipse.Local.circumstances(eclipse.greatest, dallas)
      iex> {local.type, Float.round(local.magnitude, 3)}
      {:total, 1.015}

  """
  @spec circumstances(Time.moment(), Geo.PointZ.t()) :: {:ok, map()} | {:error, :not_visible}
  def circumstances(greatest, %Geo.PointZ{coordinates: {longitude, latitude, height}}) do
    observer = observer(longitude, latitude, height)

    maximum =
      least_distance(observer, greatest - @days_around_greatest, greatest + @days_around_greatest)

    at_maximum = shadow(observer, maximum)

    if at_maximum.distance < at_maximum.penumbra do
      observer
      |> contacts(maximum, at_maximum)
      |> seen(observer)
    else
      {:error, :not_visible}
    end
  end

  defp contacts(observer, maximum, at_maximum) do
    %{penumbra: penumbra, umbra: umbra, distance: distance} = at_maximum
    type = local_type(distance, umbra)

    %{
      type: type,
      partial_begins: contact(observer, :penumbra, maximum, :before),
      maximum: maximum,
      partial_ends: contact(observer, :penumbra, maximum, :after),
      magnitude: (penumbra - distance) / (penumbra + umbra),
      obscuration: obscuration((penumbra + umbra) / 2, (penumbra - umbra) / 2, distance)
    }
    |> Map.merge(central_contacts(type, observer, maximum))
  end

  defp central_contacts(:partial, _observer, _maximum) do
    %{}
  end

  defp central_contacts(:total, observer, maximum) do
    %{
      total_begins: contact(observer, :umbra, maximum, :before),
      total_ends: contact(observer, :umbra, maximum, :after)
    }
  end

  defp central_contacts(:annular, observer, maximum) do
    %{
      annular_begins: contact(observer, :umbra, maximum, :before),
      annular_ends: contact(observer, :umbra, maximum, :after)
    }
  end

  defp local_type(distance, umbra) when distance < abs(umbra) and umbra < 0.0 do
    :total
  end

  defp local_type(distance, umbra) when distance < abs(umbra) do
    :annular
  end

  defp local_type(_distance, _umbra) do
    :partial
  end

  # The area two disks share, over the area of the first: the Sun of
  # radius `sun`, the Moon of radius `moon`, their centres `distance`
  # apart.
  defp obscuration(sun, moon, distance) when distance >= sun + moon do
    0.0
  end

  defp obscuration(sun, moon, distance) when distance <= moon - sun do
    1.0
  end

  defp obscuration(sun, moon, distance) when distance <= sun - moon do
    moon * moon / (sun * sun)
  end

  defp obscuration(sun, moon, distance) do
    moon_angle =
      :math.acos((distance * distance + moon * moon - sun * sun) / (2 * distance * moon))

    sun_angle = :math.acos((distance * distance + sun * sun - moon * moon) / (2 * distance * sun))

    triangle =
      :math.sqrt(
        (-distance + moon + sun) * (distance + moon - sun) * (distance - moon + sun) *
          (distance + moon + sun)
      )

    shared = moon * moon * moon_angle + sun * sun * sun_angle - triangle / 2
    shared / (:math.pi() * sun * sun)
  end

  # The eclipse is seen if the Sun has risen at some moment between
  # first and last contact. The Sun's altitude over a few hours rises,
  # falls, or does one then the other, so its greatest is at an end or
  # at the one turning point a golden section search finds.
  defp seen(circumstances, observer) do
    %{partial_begins: begins, partial_ends: ends} = circumstances
    highest = highest_altitude(observer, begins, ends)

    sun_altitudes =
      circumstances
      |> Map.take(contact_keys())
      |> Map.new(fn {key, moment} -> {key, sun_altitude(observer, moment)} end)

    if Enum.max([highest | Map.values(sun_altitudes)]) > @sunrise_altitude do
      {:ok, Map.put(circumstances, :sun_altitudes, sun_altitudes)}
    else
      {:error, :not_visible}
    end
  end

  defp contact_keys do
    [
      :partial_begins,
      :annular_begins,
      :total_begins,
      :maximum,
      :total_ends,
      :annular_ends,
      :partial_ends
    ]
  end

  defp highest_altitude(observer, a, b) when b - a < @search_tolerance_days do
    sun_altitude(observer, (a + b) / 2)
  end

  defp highest_altitude(observer, a, b) do
    step = (b - a) * @golden_section
    left = a + step
    right = b - step

    if sun_altitude(observer, left) > sun_altitude(observer, right) do
      highest_altitude(observer, a, right)
    else
      highest_altitude(observer, left, b)
    end
  end

  defp sun_altitude(observer, t) do
    %{d: d, mu: mu} = Eclipse.elements(t)
    hour_angle = mu + observer.longitude
    asin(sin(d) * sin(observer.latitude) + cos(d) * cos(observer.latitude) * cos(hour_angle))
  end

  defp least_distance(_observer, a, b) when b - a < @search_tolerance_days do
    (a + b) / 2
  end

  defp least_distance(observer, a, b) do
    step = (b - a) * @golden_section
    left = a + step
    right = b - step

    if shadow(observer, left).distance < shadow(observer, right).distance do
      least_distance(observer, a, right)
    else
      least_distance(observer, left, b)
    end
  end

  # A contact is where the observer's distance from the axis equals a
  # cone's radius; inside it at maximum, outside six hours away.
  defp contact(observer, cone, maximum, :before) do
    bisect(observer, cone, maximum - @days_around_greatest, maximum)
  end

  defp contact(observer, cone, maximum, :after) do
    bisect(observer, cone, maximum + @days_around_greatest, maximum)
  end

  defp bisect(_observer, _cone, outside, inside)
       when abs(outside - inside) < @search_tolerance_days do
    (outside + inside) / 2
  end

  defp bisect(observer, cone, outside, inside) do
    middle = (outside + inside) / 2

    if inside_cone?(shadow(observer, middle), cone) do
      bisect(observer, cone, outside, middle)
    else
      bisect(observer, cone, middle, inside)
    end
  end

  defp inside_cone?(%{distance: distance, penumbra: penumbra}, :penumbra) do
    distance < penumbra
  end

  defp inside_cone?(%{distance: distance, umbra: umbra}, :umbra) do
    distance < abs(umbra)
  end

  # The observer on the fundamental plane at a moment, the radii of the
  # cones at the observer's height above it, and the observer's
  # distance from the axis.
  defp shadow(observer, t) do
    %{x: x, y: y, d: d, mu: mu, l1: l1, l2: l2, tan_f1: tan_f1, tan_f2: tan_f2} =
      Eclipse.elements(t)

    hour_angle = mu + observer.longitude
    xi = observer.rho_cos_phi * sin(hour_angle)
    eta = observer.rho_sin_phi * cos(d) - observer.rho_cos_phi * sin(d) * cos(hour_angle)
    zeta = observer.rho_sin_phi * sin(d) + observer.rho_cos_phi * cos(d) * cos(hour_angle)
    u = x - xi
    v = y - eta

    %{
      distance: :math.sqrt(u * u + v * v),
      penumbra: l1 - zeta * tan_f1,
      umbra: l2 - zeta * tan_f2
    }
  end

  # The observer's geocentric coordinates `ρ sin φ′` and `ρ cos φ′` in
  # equatorial radii of the Earth, from the geodetic latitude and the
  # height above the ellipsoid.
  defp observer(longitude, latitude, height) do
    reduced_latitude = :math.atan(@polar_ratio * :math.tan(latitude * :math.pi() / 180))
    height_ratio = height / Earth.earth_radius_m()

    %{
      longitude: longitude,
      latitude: latitude,
      rho_sin_phi: @polar_ratio * :math.sin(reduced_latitude) + height_ratio * sin(latitude),
      rho_cos_phi: :math.cos(reduced_latitude) + height_ratio * cos(latitude)
    }
  end
end
