defmodule Astro.Lunar do
  @moduledoc """
  Calculates lunar position, phases, distance and related quantities.

  This module provides the analytical (Meeus Ch. 47) periodic-term
  series for the Moon’s ecliptic longitude, latitude and distance,
  as well as derived quantities such as illuminated fraction,
  parallax and angular semi-diameter. These functions underpin the
  higher-level lunar API in `Astro` and the topocentric
  moonrise/moonset algorithm in `Astro.Lunar.MoonRiseSet`.

  ## Lunar phases

  The phase of the Moon is defined by the elongation — the
  geocentric angle between the Moon and the Sun. A **new moon**
  occurs at 0° elongation, **first quarter** at 90°, **full moon**
  at 180° and **last quarter** at 270°.

  Because the Moon’s orbital plane is tilted ~5.1° relative to
  the ecliptic, a new moon can be up to ~5.2° from the Sun,
  which is why a solar eclipse does not occur every month.

  ## Function groups

  ### Position and geometry

  * `lunar_position/1` — ecliptic longitude, latitude and distance
  * `lunar_ecliptic_longitude/1`, `lunar_latitude/1`, `lunar_distance/1`
  * `lunar_altitude/2`, `topocentric_lunar_altitude/2`
  * `equatorial_horizontal_parallax/1`, `topocentric_lunar_parallax/2`
  * `angular_semi_diameter/1`, `horizontal_dip/1`

  ### Phases and illumination

  * `lunar_phase_at/1` — phase angle (0–360°) at a moment
  * `illuminated_fraction_of_moon/1`
  * `new_moon_phase/0`, `full_moon_phase/0`, `first_quarter_phase/0`,
    `last_quarter_phase/0`

  ### New moon and phase search

  * `date_time_new_moon_before/1`, `date_time_new_moon_at_or_after/1`,
    `date_time_new_moon_nearest/1`
  * `date_time_lunar_phase_at_or_before/2`, `date_time_lunar_phase_at_or_after/2`
  * `nth_new_moon/1`

  ### Fundamental arguments (Julian centuries)

  * `mean_lunar_ecliptic_longitude/1`, `lunar_elongation/1`
  * `solar_anomaly/1`, `lunar_anomaly/1`, `lunar_node/1`, `moon_node/1`

  ## Time convention

  Most functions in this module accept a **moment** (fractional
  days since the epoch 0000-01-01). Use `Astro.Time.date_time_to_moment/1`
  to convert dates or datetimes. Functions that accept Julian centuries
  note this in their documentation.

  """

  alias Astro.{Math, Time, Solar, Earth}

  import Astro.Math,
    only: [
      deg: 1,
      sin: 1,
      cos: 1,
      mt: 1,
      asin: 1,
      sigma: 2,
      mod: 2,
      degrees: 1,
      poly: 2,
      invert_angular: 4,
      to_degrees: 1
    ]

  import Astro.Time,
    only: [
      j2000: 0,
      julian_centuries_from_moment: 1,
      mean_synodic_month: 0
    ]

  @months_epoch_to_j2000 24_724
  @average_distance_earth_to_moon 385_000_560.0
  @meters_per_kilometer 1000.0

  # IAU 2015 lunar radius in km
  @lunar_radius 1_737.4
  @lunar_radius_m @lunar_radius * @meters_per_kilometer

  # Moon's mean radius / Earth's equatorial radius (Meeus Ch.47).
  @lunar_k @lunar_radius_m / Earth.earth_radius_m()

  # -------------------------------------------------------------------
  # Meeus Ch.47 coefficient tables for lunar ecliptic longitude,
  # latitude and distance.  Each row is one periodic term; columns
  # are D (lunar elongation), M (solar anomaly), M' (lunar anomaly),
  # F (moon node) multipliers and the sine/cosine coefficient.
  #
  # The tables are stored as heredoc strings and parsed at compile
  # time into integer lists.
  # -------------------------------------------------------------------

  # -- Ecliptic longitude (Meeus Table 47.A) --------------------------

  @ecliptic_lng_d ~w"""
                     0  2  2  0  0  0  2  2  2  2
                     0  1  0  2  0  0  4  0  4  2
                     2  1  1  2  2  4  2  0  2  2
                     1  2  0  0  2  2  2  4  0  3
                     2  4  0  2  2  2  4  0  4  1
                     2  0  1  3  4  2  0  1  2
                  """
                  |> Enum.map(&String.to_integer/1)

  @ecliptic_lng_m ~w"""
                     0  0  0  0  1  0  0 -1  0 -1
                     1  0  1  0  0  0  0  0  0  1
                     1  0  1 -1  0  0  0  1  0 -1
                     0 -2  1  2 -2  0  0 -1  0  0
                     1 -1  2  2  1 -1  0  0 -1  0
                     1  0  1  0  0 -1  2  1  0
                  """
                  |> Enum.map(&String.to_integer/1)

  @ecliptic_lng_m_prime ~w"""
                           1 -1  0  2  0  0 -2 -1  1  0
                          -1  0  1  0  1  1 -1  3 -2 -1
                           0 -1  0  1  2  0 -3 -2 -1 -2
                           1  0  2  0 -1  1  0 -1  2 -1
                           1 -2 -1 -1 -2  0  1  4  0 -2
                           0  2  1 -2 -3  2  1 -1  3
                        """
                        |> Enum.map(&String.to_integer/1)

  @ecliptic_lng_f ~w"""
                     0  0  0  0  0  2  0  0  0  0
                     0  0  0 -2  2 -2  0  0  0  0
                     0  0  0  0  0  0  0  0  2  0
                     0  0  0  0  0 -2  2  0  2  0
                     0  0  0  0  0 -2  0  0  0  0
                    -2 -2  0  0  0  0  0  0  0
                  """
                  |> Enum.map(&String.to_integer/1)

  @ecliptic_lng_coeff ~w"""
                         6288774  1274027   658314   213618  -185116
                         -114332    58793    57066    53322    45758
                          -40923   -34720   -30383    15327   -12528
                           10980    10675    10034     8548    -7888
                           -6766    -5163     4987     4036     3994
                            3861     3665    -2689    -2602     2390
                           -2348     2236    -2120    -2069     2048
                           -1773    -1595     1215    -1110     -892
                            -810      759     -713     -700      691
                             596      549      537      520     -487
                            -399     -381      351     -340      330
                             327     -323      299      294
                      """
                      |> Enum.map(&String.to_integer/1)

  # -- Latitude (Meeus Table 47.B) ------------------------------------

  @latitude_d ~w"""
                 0  0  0  2  2  2  2  0  2  0
                 2  2  2  2  2  2  2  0  4  0
                 0  0  1  0  0  0  1  0  4  4
                 0  4  2  2  2  2  0  2  2  2
                 2  4  2  2  0  2  1  1  0  2
                 1  2  0  4  4  1  4  1  4  2
              """
              |> Enum.map(&String.to_integer/1)

  @latitude_m ~w"""
                 0  0  0  0  0  0  0  0  0  0
                -1  0  0  1 -1 -1 -1  1  0  1
                 0  1  0  1  1  1  0  0  0  0
                 0  0  0  0 -1  0  0  0  0  1
                 1  0 -1 -2  0  1  1  1  1  1
                 0 -1  1  0 -1  0  0  0 -1 -2
              """
              |> Enum.map(&String.to_integer/1)

  @latitude_m_prime ~w"""
                       0  1  1  0 -1 -1  0  2  1  2
                       0 -2  1  0 -1  0 -1 -1 -1  0
                       0 -1  0  1  1  0  0  3  0 -1
                       1 -2  0  2  1 -2  3  2 -3 -1
                       0  0  1  0  1  1  0  0 -2 -1
                       1 -2  2 -2 -1  1  1 -2  0  0
                    """
                    |> Enum.map(&String.to_integer/1)

  @latitude_f ~w"""
                 1  1 -1 -1  1 -1  1  1 -1 -1
                -1 -1  1 -1  1  1 -1 -1 -1  1
                 3  1  1  1 -1 -1 -1  1 -1  1
                -3  1 -3 -1 -1  1 -1  1 -1  1
                 1  1  1 -1  3 -1 -1  1 -1 -1
                 1 -1  1 -1 -1 -1 -1 -1 -1  1
              """
              |> Enum.map(&String.to_integer/1)

  @latitude_coeff ~w"""
                     5128122   280602   277693   173237    55413
                       46271    32573    17198     9266     8822
                        8216     4324     4200    -3359     2463
                        2211     2065    -1870     1828    -1794
                       -1749    -1565    -1491    -1475    -1410
                       -1344    -1335     1107     1021      833
                         777      671      607      596      491
                        -451      439      422      421     -366
                        -351      331      315      302     -283
                        -229      223      223     -220     -220
                        -185      181     -177      176      166
                        -164      132     -119      115      107
                  """
                  |> Enum.map(&String.to_integer/1)

  # -- Distance (Meeus Table 47.A cosine terms) -----------------------

  @distance_d ~w"""
                 0  2  2  0  0  0  2  2  2  2
                 0  1  0  2  0  0  4  0  4  2
                 2  1  1  2  2  4  2  0  2  2
                 1  2  0  0  2  2  2  4  0  3
                 2  4  0  2  2  2  4  0  4  1
                 2  0  1  3  4  2  0  1  2  2
              """
              |> Enum.map(&String.to_integer/1)

  @distance_m ~w"""
                 0  0  0  0  1  0  0 -1  0 -1
                 1  0  1  0  0  0  0  0  0  1
                 1  0  1 -1  0  0  0  1  0 -1
                 0 -2  1  2 -2  0  0 -1  0  0
                 1 -1  2  2  1 -1  0  0 -1  0
                 1  0  1  0  0 -1  2  1  0  0
              """
              |> Enum.map(&String.to_integer/1)

  @distance_m_prime ~w"""
                       1 -1  0  2  0  0 -2 -1  1  0
                      -1  0  1  0  1  1 -1  3 -2 -1
                       0 -1  0  1  2  0 -3 -2 -1 -2
                       1  0  2  0 -1  1  0 -1  2 -1
                       1 -2 -1 -1 -2  0  1  4  0 -2
                       0  2  1 -2 -3  2  1 -1  3 -1
                    """
                    |> Enum.map(&String.to_integer/1)

  @distance_f ~w"""
                 0  0  0  0  0  2  0  0  0  0
                 0  0  0 -2  2 -2  0  0  0  0
                 0  0  0  0  0  0  0  0  2  0
                 0  0  0  0  0 -2  2  0  2  0
                 0  0  0  0  0 -2  0  0  0  0
                -2 -2  0  0  0  0  0  0  0 -2
              """
              |> Enum.map(&String.to_integer/1)

  @distance_coeff ~w"""
                    -20905355 -3699111 -2955968  -569925    48888
                        -3149   246158  -152138  -170733  -204586
                      -129620   108743   104755    10321        0
                        79661   -34782   -23210   -21636    24208
                        30824    -8379   -16675   -12831   -10445
                       -11650    14403    -7003        0    10056
                         6322    -9884     5751        0    -4950
                         4130        0    -3958        0     3258
                         2616    -1897    -2117     2354        0
                            0    -1423    -1117    -1571    -1739
                            0    -4421        0        0        0
                            0     1165        0        0     8752
                  """
                  |> Enum.map(&String.to_integer/1)

  @doc """
  Returns the lunar radius in kilometers.

  The IAU 2015 value of 1737.4 km is used.

  ### Arguments

  None.

  ### Returns

  * The lunar radius as a float in kilometers.

  ### Examples

      iex> Astro.Lunar.lunar_radius()
      1737.4

  """
  @spec lunar_radius() :: Astro.kilometers()
  def lunar_radius do
    @lunar_radius
  end

  @doc false
  def lunar_radius_m do
    @lunar_radius_m
  end

  @doc false
  def lunar_k do
    @lunar_k
  end

  @doc """
  Returns the date time of the new
  moon before a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * A `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Example

      iex> Astro.Lunar.date_time_new_moon_before 738390
      738375.5764772523

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_before(t :: Time.moment()) :: Time.moment()

  def date_time_new_moon_before(t) when is_number(t) do
    t0 = nth_new_moon(0)
    phi = lunar_phase_at(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360)) |> trunc()
    nth_new_moon(Math.final(n - 1, &(nth_new_moon(&1) < t)))
  end

  @doc """
  Returns the date time of the new
  moon at or after a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * a `t:Astro.Time.moment/0` which is a float number of days
    since `0000-01-01`

  ### Example

      iex> Astro.Lunar.date_time_new_moon_at_or_after(738390)
      738405.0359290199

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_at_or_after(t :: Time.moment()) :: Time.moment()

  def date_time_new_moon_at_or_after(t) when is_number(t) do
    t0 = nth_new_moon(0)
    phi = lunar_phase_at(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360.0))
    nth_new_moon(Math.next(n, &(nth_new_moon(&1) >= t)))
  end

  @doc """
  Returns the moment of the new
  moon nearest to a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * a `t:Astro.Time.moment/0` which is a float number of days
    since `0000-01-01`

  ### Example

      iex> Astro.Lunar.date_time_new_moon_nearest(738390)
      738375.5764755815

  """
  @doc since: "2.0.0"
  @spec date_time_new_moon_nearest(t :: Time.moment()) :: Time.moment()
  def date_time_new_moon_nearest(t) when is_number(t) do
    new_moon = new_moon_phase()

    at_or_before = date_time_lunar_phase_at_or_before(t, new_moon)
    at_or_after = date_time_lunar_phase_at_or_after(t, new_moon)

    if abs(t - at_or_before) < abs(t - at_or_after) do
      at_or_before
    else
      at_or_after
    end
  end

  @doc """
  Returns the lunar phase as a float number of degrees at
  a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * the lunar phase as a float number of
    degrees.

  ### Example

      iex> Astro.Lunar.lunar_phase_at(738389.5007195644)
      179.9911519346108

      iex> Astro.Lunar.lunar_phase_at(738346.0544609067)
      0.013592004555277981

  """
  @doc since: "0.5.0"
  @spec lunar_phase_at(t :: Astro.Time.moment()) :: Astro.angle()

  def lunar_phase_at(t) when is_number(t) do
    phi = mod(lunar_ecliptic_longitude(t) - solar_ecliptic_longitude(t), 360)
    t0 = nth_new_moon(0)
    n = round((t - t0) / mean_synodic_month())
    phi_prime = deg(360) * mod((t - nth_new_moon(n)) / mean_synodic_month(), 1)

    if abs(phi - phi_prime) > deg(180.0) do
      phi_prime
    else
      phi
    end
  end

  @doc """
  Returns the date time of a given
  lunar phase at or before a given
  moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0.0` and
    `360.0`

  ### Returns

  * A `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Example

      iex> Astro.Lunar.date_time_lunar_phase_at_or_before(738368, Astro.Lunar.new_moon_phase())
      738346.053171558

  """
  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_before(t :: Time.moment(), phase :: Astro.phase()) ::
          Time.moment()

  def date_time_lunar_phase_at_or_before(t, phase) do
    tau = t - mean_synodic_month() * (1.0 / deg(360.0)) * mod(lunar_phase_at(t) - phase, 360.0)
    a = tau - 2
    b = min(t, tau + 2)
    invert_angular(&lunar_phase_at/1, phase, a, b)
  end

  @doc """
  Returns the date time of a given
  lunar phase at or after a given
  date time or date.

  ### Arguments

  * `t`, a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0` and
    `360`

  ### Returns

  * a `t:Astro.Time.moment/0` which is a float number of days
    since `0000-01-01`.

  ### Example

      iex> Astro.Lunar.date_time_lunar_phase_at_or_after(738368, Astro.Lunar.full_moon_phase())
      738389.5014214877

  """
  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_after(t :: Time.moment(), phase :: Astro.phase()) ::
          Time.moment()

  def date_time_lunar_phase_at_or_after(t, phase) do
    tau = t + mean_synodic_month() * (1 / deg(360.0)) * mod(phase - lunar_phase_at(t), 360.0)
    a = max(t, tau - 2)
    b = tau + 2
    invert_angular(&lunar_phase_at/1, phase, a, b)
  end

  @doc """
  Returns the Moon's equatorial position (right ascension, declination,
  distance) for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * A 3-tuple `{right_ascension, declination, distance}` where
    right ascension and declination are in degrees and distance
    is in meters.

  ### Examples

      iex> {ra, _dec, _dist} = Astro.Lunar.lunar_position(738390)
      iex> Float.round(ra, 2)
      -19.96

  """
  @doc since: "0.6.0"
  @spec lunar_position(Time.moment()) ::
          {Astro.angle(), Astro.angle(), Astro.meters()}

  def lunar_position(t) do
    lambda = lunar_ecliptic_longitude(t)
    beta = lunar_latitude(t)
    distance = lunar_distance(t)

    {Astro.right_ascension(t, beta, lambda), Astro.declination(t, beta, lambda), distance}
  end

  @doc """
  Returns the fractional illumination of the Moon
  for a given moment as a float between 0.0 and 1.0.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The fractional illumination of the Moon as a float
    between `0.0` (new moon) and `1.0` (full moon).

  ### Examples

      iex> Astro.Lunar.illuminated_fraction_of_moon(738390)
      ...> |> Float.round(4)
      0.9951

  """
  @doc since: "0.6.0"
  @spec illuminated_fraction_of_moon(Time.time()) :: float()

  def illuminated_fraction_of_moon(t) do
    {a0, d0, r0} = lunar_position(t)
    {a, d, r} = Solar.solar_position(t)
    r = Math.au_to_m(r)

    phi = :math.acos(sin(d0) * sin(d) + cos(d0) * cos(d) * cos(a0 - a))
    i = Math.atan_r(r * :math.sin(phi), r0 - r * :math.cos(phi))

    0.5 * (1 + :math.cos(i))
  end

  @doc """
  Returns the new moon phase angle in degrees.

  ### Returns

  * `0.0`

  ### Examples

      iex> Astro.Lunar.new_moon_phase()
      0.0

  """
  @doc since: "0.5.0"
  @spec new_moon_phase() :: Astro.phase()
  def new_moon_phase() do
    deg(0.0)
  end

  @doc """
  Returns the full moon phase angle in degrees.

  ### Returns

  * `180.0`

  ### Examples

      iex> Astro.Lunar.full_moon_phase()
      180.0

  """
  @doc since: "0.5.0"
  @spec full_moon_phase() :: Astro.phase()
  def full_moon_phase() do
    deg(180.0)
  end

  @doc """
  Returns the first quarter phase angle in degrees.

  ### Returns

  * `90.0`

  ### Examples

      iex> Astro.Lunar.first_quarter_phase()
      90.0

  """
  @doc since: "0.5.0"
  @spec first_quarter_phase() :: Astro.phase()
  def first_quarter_phase() do
    deg(90.0)
  end

  @doc """
  Returns the last quarter phase angle in degrees.

  ### Returns

  * `270.0`

  ### Examples

      iex> Astro.Lunar.last_quarter_phase()
      270.0

  """
  @doc since: "0.5.0"
  @spec last_quarter_phase() :: Astro.phase()

  def last_quarter_phase() do
    deg(270.0)
  end

  @doc false
  @doc since: "0.5.0"
  @spec lunar_ecliptic_longitude(Time.moment()) :: Astro.phase()

  def lunar_ecliptic_longitude(t) do
    c = julian_centuries_from_moment(t)
    l = mean_lunar_ecliptic_longitude(c)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    correction =
      deg(1 / 1_000_000) *
        sigma(
          [
            @ecliptic_lng_coeff,
            @ecliptic_lng_d,
            @ecliptic_lng_m,
            @ecliptic_lng_m_prime,
            @ecliptic_lng_f
          ],
          fn [v, w, x, y, z] ->
            v * :math.pow(e, abs(x)) * sin(w * d + x * m + y * m_prime + z * f)
          end
        )

    venus =
      deg(3958 / 1_000_000) *
        sin(deg(119.75) + c * deg(131.849))

    jupiter =
      deg(318 / 1_000_000) *
        sin(deg(53.09) + c * deg(479_264.29))

    flat_earth =
      deg(1962 / 1_000_000) *
        sin(l - f)

    {dpsi, _deps, _eps0} = Earth.nutation(c)
    mod(l + correction + venus + jupiter + flat_earth + dpsi, 360)
  end

  @doc """
  Returns the Moon's ecliptic latitude in degrees for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The ecliptic latitude as a float in degrees.

  ### Examples

      iex> Astro.Lunar.lunar_latitude(738390) |> Float.round(4)
      -5.0099

  """
  @doc since: "0.6.0"
  @spec lunar_latitude(Time.moment()) :: Astro.angle()

  def lunar_latitude(t) do
    c = julian_centuries_from_moment(t)
    l = mean_lunar_ecliptic_longitude(c)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    beta =
      deg(1.0 / 1_000_000.0) *
        sigma(
          [@latitude_coeff, @latitude_d, @latitude_m, @latitude_m_prime, @latitude_f],
          fn [v, w, x, y, z] ->
            v * :math.pow(e, abs(x)) * sin(w * d + x * m + y * m_prime + z * f)
          end
        )

    venus =
      deg(175.0 / 1_000_000.0) *
        sin(deg(119.75) + c * deg(131.849) + f) *
        sin(deg(119.75) + c * deg(131.849) - f)

    flat_earth =
      deg(-2235.0 / 1_000_000.0) * sin(l) +
        deg(127.0 / 1_000_000.0) * sin(l - m_prime) +
        deg(-115.0 / 1_000_000.0) * sin(l + m_prime)

    extra = deg(382.0 / 1_000_000.0) * sin(deg(313.45) + c * deg(481_266.484))

    beta + venus + flat_earth + extra
  end

  @doc """
  Returns the Moon's geocentric altitude in degrees for a given moment
  and observer location.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  * `location` is a `Geo.PointZ` struct with `{longitude, latitude, altitude}`
    coordinates.

  ### Returns

  * The geocentric altitude in degrees, ranging from -180.0 to 180.0.

  """
  @doc since: "0.4.0"
  @spec lunar_altitude(Time.moment(), Geo.PointZ.t()) :: Astro.angle()

  def lunar_altitude(t, %Geo.PointZ{coordinates: {psi, phi, _alt}}) do
    lambda = lunar_ecliptic_longitude(t)
    beta = lunar_latitude(t)
    alpha = Astro.right_ascension(t, beta, lambda)
    delta = Astro.declination(t, beta, lambda)
    theta = Time.mean_sidereal_from_moment(t)
    h = mod(theta + psi - alpha, 360.0)
    altitude = asin(sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h))
    mod(altitude + deg(180.0), 360.0) - deg(180.0)
  end

  @doc false
  @doc since: "2.0.0"
  @spec topocentric_lunar_altitude(t :: Time.moment(), location :: Geo.PointZ.t()) ::
          Astro.angle()

  def topocentric_lunar_altitude(t, location) do
    lunar_altitude(t, location) - topocentric_lunar_parallax(t, location)
  end

  @doc """
  Returns the Moon's distance from the Earth in meters for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The Earth-Moon distance as a float in meters.

  ### Examples

      iex> Astro.Lunar.lunar_distance(738390) |> trunc()
      381251299

  """
  @doc since: "0.6.0"
  @spec lunar_distance(t :: Time.moment()) :: Astro.meters()

  def lunar_distance(t) do
    c = Time.julian_centuries_from_moment(t)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    correction =
      sigma(
        [@distance_coeff, @distance_d, @distance_m, @distance_m_prime, @distance_f],
        fn [v, w, x, y, z] ->
          v * :math.pow(e, abs(x)) * cos(w * d + x * m + y * m_prime + z * f)
        end
      )

    mt(@average_distance_earth_to_moon) + correction
  end

  @doc false
  @doc since: "0.4.0"
  @spec nth_new_moon(number()) :: Time.moment()

  def nth_new_moon(n) do
    k = n - @months_epoch_to_j2000
    c = k / 1_236.85

    approx =
      j2000() +
        poly(c, [
          5.09766,
          mean_synodic_month() * 1236.85,
          0.0001437,
          -0.000000150,
          0.00000000073
        ])

    e =
      poly(c, [
        1,
        -0.002516,
        -0.0000074
      ])

    solar_anomaly =
      poly(c, [
        2.5534,
        1236.85 * 29.10535669,
        -0.0000014,
        -0.00000011
      ])

    lunar_anomaly =
      poly(c, [
        201.5643,
        385.81693528 * 1236.85,
        0.0107582,
        0.00001238,
        -0.000000058
      ])

    moon_argument =
      poly(c, [
        160.7108,
        390.67050284 * 1236.85,
        -0.0016118,
        -0.00000227,
        0.000000011
      ])

    omega =
      poly(c, [
        124.7746,
        -1.56375588 * 1236.85,
        0.0020672,
        0.00000215
      ])

    e_factor = [
      0,
      1,
      0,
      0,
      1,
      1,
      2,
      0,
      0,
      1,
      0,
      1,
      1,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0
    ]

    solar_coeff = [
      0,
      1,
      0,
      0,
      -1,
      1,
      2,
      0,
      0,
      1,
      0,
      1,
      1,
      -1,
      2,
      0,
      3,
      1,
      0,
      1,
      -1,
      -1,
      1,
      0
    ]

    lunar_coeff = [
      1,
      0,
      2,
      0,
      1,
      1,
      0,
      1,
      1,
      2,
      3,
      0,
      0,
      2,
      1,
      2,
      0,
      1,
      2,
      1,
      1,
      1,
      3,
      4
    ]

    moon_coeff = [
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      -2,
      2,
      0,
      0,
      2,
      -2,
      0,
      0,
      -2,
      0,
      -2,
      2,
      2,
      2,
      -2,
      0,
      0
    ]

    sine_coeff = [
      -0.40720,
      0.17241,
      0.01608,
      0.01039,
      0.00739,
      -0.00514,
      0.00208,
      -0.00111,
      -0.00057,
      0.00056,
      -0.00042,
      0.00042,
      0.00038,
      -0.00024,
      -0.00007,
      0.00004,
      0.00004,
      0.00003,
      0.00003,
      -0.00003,
      0.00003,
      -0.00002,
      -0.00002,
      0.00002
    ]

    correction =
      deg(-0.00017) * sin(omega) +
        sigma(
          [sine_coeff, e_factor, solar_coeff, lunar_coeff, moon_coeff],
          fn [v, w, x, y, z] ->
            v * :math.pow(e, w) *
              sin(x * solar_anomaly + y * lunar_anomaly + z * moon_argument)
          end
        )

    extra =
      deg(0.000325) *
        sin(poly(c, [299.77, 132.8475848, -0.009173]))

    add_const = [
      251.88,
      251.83,
      349.42,
      84.66,
      141.74,
      207.14,
      154.84,
      34.52,
      207.19,
      291.34,
      161.72,
      239.56,
      331.55
    ]

    add_coeff = [
      0.016321,
      26.651886,
      36.412478,
      18.206239,
      53.303771,
      2.453732,
      7.306860,
      27.261239,
      0.121824,
      1.844379,
      24.198154,
      25.513099,
      3.592518
    ]

    add_factor = [
      0.000165,
      0.000164,
      0.000126,
      0.000110,
      0.000062,
      0.000060,
      0.000056,
      0.000047,
      0.000042,
      0.000040,
      0.000037,
      0.000035,
      0.000023
    ]

    additional = sigma([add_const, add_coeff, add_factor], fn [i, j, l] -> l * sin(i + j * k) end)

    Time.universal_from_dynamical(approx + correction + extra + additional)
  end

  @doc """
  Returns the Moon's equatorial horizontal parallax in degrees for a
  given moment.

  The horizontal parallax is the angle subtended by Earth's equatorial
  radius as seen from the Moon, or equivalently the maximum apparent
  displacement of the Moon caused by the observer being on Earth's surface
  rather than its centre.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The equatorial horizontal parallax as a float in degrees.

  ### Examples

      iex> Astro.Lunar.equatorial_horizontal_parallax(738390)
      ...> |> Float.round(4)
      0.0167

  """
  @spec equatorial_horizontal_parallax(t :: Time.moment()) :: Astro.angle()
  def equatorial_horizontal_parallax(t) do
    asin(Earth.earth_radius_m() / lunar_distance(t))
    |> to_degrees()
  end

  @doc """
  Returns the topocentric lunar parallax in degrees for a given moment
  and observer location.

  This is the observer-specific parallax (also called the parallax in
  altitude), which varies with the observer's latitude and the Moon's
  altitude above their horizon — as opposed to the equatorial horizontal
  parallax returned by `equatorial_horizontal_parallax/1`, which is
  location-independent.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  * `location` is a `Geo.PointZ` struct with `{longitude, latitude, altitude}`
    coordinates.

  ### Returns

  * The topocentric parallax as a float in degrees.

  """
  @spec topocentric_lunar_parallax(t :: Time.moment(), location :: Geo.PointZ.t()) ::
          Astro.angle()

  def topocentric_lunar_parallax(t, location) do
    :math.asin(sin(equatorial_horizontal_parallax(t)) * cos(lunar_altitude(t, location)))
    |> to_degrees()
  end

  @doc """
  Returns the mean lunar ecliptic longitude in degrees for a given
  number of Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean ecliptic longitude as a float in degrees.

  """
  @spec mean_lunar_ecliptic_longitude(c :: Time.julian_centuries()) :: Astro.angle()
  def mean_lunar_ecliptic_longitude(c) do
    c
    |> poly([218.3164477, 481_267.88123421, -0.0015786, 1 / 538_841.0, -1 / 65_194_000.0])
    |> degrees()
  end

  @doc """
  Returns the mean lunar elongation in degrees for a given number of
  Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean elongation as a float in degrees.

  """
  @spec lunar_elongation(c :: Time.julian_centuries()) :: Astro.angle()
  def lunar_elongation(c) do
    c
    |> poly([297.8501921, 445_267.1114034, -0.0018819, 1 / 545_868, -1 / 113_065_000.0])
    |> degrees()
  end

  @doc """
  Returns the Moon's angular semi-diameter in degrees for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The angular semi-diameter as a float in degrees.

  """
  @spec angular_semi_diameter(t :: Time.moment()) :: Astro.angle()
  def angular_semi_diameter(t) do
    asin(@lunar_radius_m / lunar_distance(t))
    |> to_degrees()
  end

  @doc """
  Returns the Moon's horizontal dip angle in degrees for a given moment.

  The horizontal dip combines atmospheric refraction, the Moon's angular
  semi-diameter and the equatorial horizontal parallax to define the
  threshold altitude for moonrise/moonset.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The horizontal dip as a float in degrees (negative value).

  """
  @spec horizontal_dip(t :: Time.moment()) :: Astro.angle()
  def horizontal_dip(t) do
    -(Earth.refraction() + angular_semi_diameter(t) - equatorial_horizontal_parallax(t))
  end

  @doc """
  Returns the Sun's mean anomaly in degrees for a given number of
  Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean solar anomaly as a float in degrees.

  """
  @spec solar_anomaly(c :: Time.julian_centuries()) :: Astro.angle()
  def solar_anomaly(c) do
    c
    |> poly([357.5291092, 35999.0502909, -0.0001536, 1 / 24_490_000.0])
    |> degrees()
  end

  @doc """
  Returns the Moon's mean anomaly in degrees for a given number of
  Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean lunar anomaly as a float in degrees.

  """
  @spec lunar_anomaly(c :: Time.julian_centuries()) :: Astro.angle()
  def lunar_anomaly(c) do
    c
    |> poly([134.9633964, 477_198.8675055, 0.0087414, 1 / 69699.0, -1 / 14_712_000.0])
    |> degrees()
  end

  defp solar_ecliptic_longitude(t) do
    c = julian_centuries_from_moment(t)
    Astro.Solar.sun_apparent_longitude_alt(c)
  end

  @doc """
  Returns the Moon's ascending node longitude in degrees for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The ascending node longitude as a float in degrees,
    ranging from -90.0 to 90.0.

  """
  @spec lunar_node(t :: Time.moment()) :: Astro.angle()
  def lunar_node(t) do
    c = julian_centuries_from_moment(t)

    moon_node(c + deg(90.0))
    |> mod(180.0)
    |> Kernel.-(90.0)
  end

  @doc """
  Returns the mean longitude of the Moon's ascending node in degrees
  for a given number of Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean longitude of the ascending node as a float in degrees.

  """
  @spec moon_node(c :: Time.julian_centuries()) :: Astro.angle()
  def moon_node(c) do
    c
    |> poly([93.2720950, 483_202.0175233, -0.0036539, -1 / 3_526_000.0, 1 / 863_310_000.0])
    |> degrees()
  end
end
