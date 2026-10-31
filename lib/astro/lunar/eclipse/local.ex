defmodule Astro.Lunar.Eclipse.Local do
  @moduledoc """
  The local circumstances of a lunar eclipse: how it is seen from a
  place on the Earth.

  A lunar eclipse is the Moon passing through the Earth's shadow, so
  unlike a solar eclipse it happens at the same instants for everyone:
  its contacts and greatest eclipse are those of `Astro.Lunar.Eclipse`.
  What depends on the place is whether the Moon is above the horizon,
  and how high, while it happens.

  The Moon's altitude is *topocentric*: the Moon is close enough that
  seen from the Earth's surface it is displaced by up to about 1°, its
  horizontal parallax, from where it is seen from the Earth's centre.
  The observer's position, from the geodetic latitude, the Earth's
  flattening and the height above the ellipsoid, is subtracted from the
  Moon's geocentric position, both in the equatorial frame of date
  turned by the local apparent sidereal time, and the altitude is the
  angle of what remains above the plane perpendicular to the observer's
  vertical. It is geometric: refraction, which lifts the Moon by about
  34′ at the horizon, is not applied.

  An eclipse is *seen* if at some moment between the first and last
  penumbral contacts the Moon's upper limb is above the horizon,
  allowing for standard refraction, which is the condition for
  moonrise.

  """

  alias Astro.{Earth, Lunar, Time}

  import Astro.Math, only: [sin: 1, cos: 1, asin: 1]

  @typedoc """
  The local circumstances of a lunar eclipse: the fields of
  `t:Astro.Lunar.Eclipse.t/0`, every instant a `t:DateTime.t/0`, and
  the Moon's geometric topocentric altitude in degrees at greatest
  eclipse and each contact, keyed by the contact.

  """
  @type t :: %__MODULE__{
          type: Astro.Lunar.Eclipse.eclipse_type(),
          greatest: DateTime.t(),
          gamma: float(),
          penumbral_magnitude: float(),
          umbral_magnitude: float(),
          penumbral_begins: DateTime.t(),
          partial_begins: DateTime.t() | nil,
          total_begins: DateTime.t() | nil,
          total_ends: DateTime.t() | nil,
          partial_ends: DateTime.t() | nil,
          penumbral_ends: DateTime.t(),
          saros: integer(),
          moon_altitudes: %{atom() => float()}
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
    :penumbral_ends,
    :saros,
    :moon_altitudes
  ]

  # The ratio of the Earth's polar radius to its equatorial radius.
  @polar_ratio 0.99664719

  # Standard refraction at the horizon, in degrees.
  @horizon_refraction 34 / 60

  # The highest altitude is found to about a millisecond.
  @search_tolerance_days 1.0e-8

  # The golden section of an interval.
  @golden_section 0.381966011250105

  @contacts [
    :penumbral_begins,
    :partial_begins,
    :total_begins,
    :greatest,
    :total_ends,
    :partial_ends,
    :penumbral_ends
  ]

  @doc """
  Returns the local circumstances at a location of a lunar eclipse.

  ### Arguments

  * `eclipse` is a lunar eclipse's circumstances as
    `Astro.Lunar.Eclipse.eclipse_at_or_after/2` returns them, every
    instant a moment.

  * `location` is a `t:Geo.PointZ.t/0`, its altitude in metres above
    the ellipsoid.

  ### Returns

  * `{:ok, circumstances}`, the eclipse's circumstances with the key
    `:moon_altitudes`, a map of the Moon's altitude in degrees at
    greatest eclipse and at each contact the eclipse has.

  * `{:error, :not_visible}` if the Moon is below the horizon from the
    first penumbral contact to the last.

  ### Examples

  The total eclipse of 14 March 2025 was seen from Dallas, the Moon
  high in the south at greatest eclipse:

      iex> {:ok, eclipse} = Astro.Lunar.Eclipse.eclipse_at_or_after(739_676.0, :danjon)
      iex> dallas = %Geo.PointZ{coordinates: {-96.80, 32.78, 0.0}}
      iex> {:ok, local} = Astro.Lunar.Eclipse.Local.circumstances(eclipse, dallas)
      iex> Float.round(local.moon_altitudes.greatest, 1)
      59.0

  """
  @spec circumstances(map(), Geo.PointZ.t()) :: {:ok, map()} | {:error, :not_visible}
  def circumstances(eclipse, %Geo.PointZ{coordinates: {longitude, latitude, height}}) do
    observer = observer(longitude, latitude, height)
    %{penumbral_begins: begins, penumbral_ends: ends} = eclipse

    moon_altitudes =
      eclipse
      |> Map.take(@contacts)
      |> Enum.reject(fn {_contact, moment} -> is_nil(moment) end)
      |> Map.new(fn {contact, moment} -> {contact, moon_altitude(observer, moment)} end)

    highest = highest_altitude(observer, begins, ends)

    if Enum.max([highest | Map.values(moon_altitudes)]) > moonrise_altitude(eclipse.greatest) do
      {:ok, Map.put(eclipse, :moon_altitudes, moon_altitudes)}
    else
      {:error, :not_visible}
    end
  end

  # The Moon has risen when its centre, without refraction, is the
  # refraction and its semi-diameter below the horizon. The
  # semi-diameter changes by under a second of arc during an eclipse.
  defp moonrise_altitude(greatest) do
    -(@horizon_refraction + Lunar.angular_semi_diameter(greatest))
  end

  # The Moon's altitude over a few hours rises, falls, or does one then
  # the other, so its greatest is at an end or at the one turning point
  # a golden section search finds.
  defp highest_altitude(observer, a, b) when b - a < @search_tolerance_days do
    moon_altitude(observer, (a + b) / 2)
  end

  defp highest_altitude(observer, a, b) do
    step = (b - a) * @golden_section
    left = a + step
    right = b - step

    if moon_altitude(observer, left) > moon_altitude(observer, right) do
      highest_altitude(observer, a, right)
    else
      highest_altitude(observer, left, b)
    end
  end

  # The Moon seen from the observer: both positions in equatorial radii
  # of the Earth, in a frame that turns with the Earth so that the
  # observer's meridian is the x axis.
  defp moon_altitude(observer, t) do
    {right_ascension, declination, distance_m} = Lunar.lunar_position(t)
    distance = distance_m / Earth.earth_radius_m()
    hour_angle = Time.apparent_sidereal_from_moment(t) + observer.longitude - right_ascension

    x = distance * cos(declination) * cos(hour_angle) - observer.rho_cos_phi
    y = distance * cos(declination) * sin(hour_angle)
    z = distance * sin(declination) - observer.rho_sin_phi

    upward = x * cos(observer.latitude) + z * sin(observer.latitude)
    asin(upward / :math.sqrt(x * x + y * y + z * z))
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
