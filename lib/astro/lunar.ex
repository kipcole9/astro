defmodule Astro.Lunar do
  @moduledoc """
  Calculates lunar position, phases, distance and related quantities.

  This module provides the Moon's position and derived quantities such as
  the phase, the illuminated fraction, parallax and angular semi-diameter.
  These functions underpin the higher-level lunar API in `Astro` and the
  topocentric moonrise/moonset algorithm in `Astro.Lunar.MoonRiseSet`.

  ## Two sources of the Moon's position

  The Moon's apparent position comes from one of two sources:

  * **The JPL DE440s ephemeris**, read by `Astro.Ephemeris`. It is a
    numerical integration fitted to lunar laser ranging, accurate to well
    under a milliarcsecond, but it covers a limited span of years
    (1900–2100 for the file bundled with Astro).

  * **Analytical series**, computed in this module: the periodic series
    of Meeus, *Astronomical Algorithms*, chapter 47, abridged from the
    ELP-2000/82 lunar theory. They are less accurate (about 3″ RMS in
    longitude near the present) but give a position for any date.

  The [accuracy guide](accuracy.md) compares the two.

  The series are sums of sine and cosine terms whose arguments combine
  five fundamental arguments: `mean_lunar_ecliptic_longitude/1`,
  `lunar_elongation/1`, `solar_anomaly/1`, `lunar_anomaly/1` and
  `moon_node/1`.

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

  * `lunar_position/1` — right ascension, declination and distance
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

  ### Analytical series

  * `analytical_lunar_ecliptic_position/1` — apparent ecliptic longitude, latitude and distance
  * `analytical_lunar_position/1` — apparent right ascension, declination and distance

  ### Fundamental arguments (Julian centuries)

  * `mean_lunar_ecliptic_longitude/1`, `lunar_elongation/1`
  * `solar_anomaly/1`, `lunar_anomaly/1`, `moon_node/1`, `lunar_node/1`

  ## Time convention

  Most functions in this module accept a **moment** (fractional
  days since the epoch 0000-01-01). Use `Astro.Time.date_time_to_moment/1`
  to convert dates or datetimes. Functions that accept Julian centuries
  note this in their documentation.

  """

  alias Astro.{Earth, Math, Solar, Time}

  import Astro.Math,
    only: [
      deg: 1,
      sin: 1,
      cos: 1,
      asin: 1,
      sigma: 2,
      mod: 2,
      degrees: 1,
      poly: 2,
      invert_angular: 5,
      to_degrees: 1,
      zip_terms: 1
    ]

  import Astro.Time,
    only: [
      j2000: 0,
      julian_centuries_from_moment: 1,
      mean_synodic_month: 0
    ]

  @months_epoch_to_j2000 24_724

  # The moment of lunation 0, `nth_new_moon(0)` (11 January 1 CE), from which
  # the lunation nearest a moment is estimated in mean synodic months.
  @new_moon_zero 376.45466366536925

  # The lunar phase advances by 360° each mean synodic month, about 12.2° a
  # day. The secant search for a new moon takes its first step at this rate.
  @mean_phase_rate 360.0 / Astro.Time.mean_synodic_month()

  # The secant search for a new moon stops when a step is shorter than this
  # many days (under a millisecond), or after this many steps.
  @new_moon_tolerance_days 1.0e-8
  @new_moon_steps 20

  # Consecutive new moons are never closer than about 29.27 days, so a new
  # moon on the right side of a moment and within this of it is the nearest.
  @shortest_lunation_days 29.0

  # A search for a lunar phase ends when its bracket is under a millisecond,
  # so that it finds a new moon at the same moment as the secant search.
  @phase_search_tolerance_days 1.0e-8

  # New moons are found within this many years of J2000. The chapter 49
  # estimates drift from the series' zero-phase crossings as the two
  # theories' polynomials diverge: about 3 days at ±30,000 years and 11 to
  # 12 days at ±40,000. Within the range each search still lands on the
  # right crossing; beyond it the drift passes half a lunation and a search
  # can settle on a neighbouring lunation's new moon.
  @new_moon_range_years 50_000
  @new_moon_range_days @new_moon_range_years * 365.2425
  @j2000_moment Astro.Time.j2000()

  # IAU 2015 lunar radius in km
  @lunar_radius 1_737.4
  @lunar_radius_m @lunar_radius * Earth.meters_per_kilometer()

  # Moon's mean radius / Earth's equatorial radius (Meeus Ch.47).
  @lunar_k @lunar_radius_m / Earth.earth_radius_m()

  # Mean distance of the Moon (Meeus, Astronomical Algorithms, chapter 47),
  # to which the periodic terms in 0.001 km are added.
  @moon_mean_distance_km 385_000.56

  # Meeus Ch.47 coefficient tables for lunar ecliptic longitude,
  # latitude and distance.  Each row is one periodic term; columns
  # are D (lunar elongation), M (solar anomaly), M' (lunar anomaly),
  # F (moon node) multipliers and the sine/cosine coefficient.
  #
  # The tables are stored as heredoc strings and parsed at compile
  # time into integer lists.
  # -------------------------------------------------------------------

  # -- Ecliptic longitude (Meeus Table 47.A) --------------------------

  @moon_longitude_d ~w"""
                       0  2  2  0  0  0  2  2  2  2
                       0  1  0  2  0  0  4  0  4  2
                       2  1  1  2  2  4  2  0  2  2
                       1  2  0  0  2  2  2  4  0  3
                       2  4  0  2  2  2  4  0  4  1
                       2  0  1  3  4  2  0  1  2
                    """
                    |> Enum.map(&String.to_integer/1)

  @moon_longitude_m ~w"""
                       0  0  0  0  1  0  0 -1  0 -1
                       1  0  1  0  0  0  0  0  0  1
                       1  0  1 -1  0  0  0  1  0 -1
                       0 -2  1  2 -2  0  0 -1  0  0
                       1 -1  2  2  1 -1  0  0 -1  0
                       1  0  1  0  0 -1  2  1  0
                    """
                    |> Enum.map(&String.to_integer/1)

  @moon_longitude_m_prime ~w"""
                             1 -1  0  2  0  0 -2 -1  1  0
                            -1  0  1  0  1  1 -1  3 -2 -1
                             0 -1  0  1  2  0 -3 -2 -1 -2
                             1  0  2  0 -1  1  0 -1  2 -1
                             1 -2 -1 -1 -2  0  1  4  0 -2
                             0  2  1 -2 -3  2  1 -1  3
                          """
                          |> Enum.map(&String.to_integer/1)

  @moon_longitude_f ~w"""
                       0  0  0  0  0  2  0  0  0  0
                       0  0  0 -2  2 -2  0  0  0  0
                       0  0  0  0  0  0  0  0  2  0
                       0  0  0  0  0 -2  2  0  2  0
                       0  0  0  0  0 -2  0  0  0  0
                      -2 -2  0  0  0  0  0  0  0
                    """
                    |> Enum.map(&String.to_integer/1)

  @moon_longitude_coeff ~w"""
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

  @moon_longitude_terms zip_terms([
                          @moon_longitude_coeff,
                          @moon_longitude_d,
                          @moon_longitude_m,
                          @moon_longitude_m_prime,
                          @moon_longitude_f
                        ])

  # -- Latitude (Meeus Table 47.B) ------------------------------------

  @moon_latitude_d ~w"""
                      0  0  0  2  2  2  2  0  2  0
                      2  2  2  2  2  2  2  0  4  0
                      0  0  1  0  0  0  1  0  4  4
                      0  4  2  2  2  2  0  2  2  2
                      2  4  2  2  0  2  1  1  0  2
                      1  2  0  4  4  1  4  1  4  2
                   """
                   |> Enum.map(&String.to_integer/1)

  @moon_latitude_m ~w"""
                      0  0  0  0  0  0  0  0  0  0
                     -1  0  0  1 -1 -1 -1  1  0  1
                      0  1  0  1  1  1  0  0  0  0
                      0  0  0  0 -1  0  0  0  0  1
                      1  0 -1 -2  0  1  1  1  1  1
                      0 -1  1  0 -1  0  0  0 -1 -2
                   """
                   |> Enum.map(&String.to_integer/1)

  @moon_latitude_m_prime ~w"""
                            0  1  1  0 -1 -1  0  2  1  2
                            0 -2  1  0 -1  0 -1 -1 -1  0
                            0 -1  0  1  1  0  0  3  0 -1
                            1 -2  0  2  1 -2  3  2 -3 -1
                            0  0  1  0  1  1  0  0 -2 -1
                            1 -2  2 -2 -1  1  1 -2  0  0
                         """
                         |> Enum.map(&String.to_integer/1)

  @moon_latitude_f ~w"""
                      1  1 -1 -1  1 -1  1  1 -1 -1
                     -1 -1  1 -1  1  1 -1 -1 -1  1
                      3  1  1  1 -1 -1 -1  1 -1  1
                     -3  1 -3 -1 -1  1 -1  1 -1  1
                      1  1  1 -1  3 -1 -1  1 -1 -1
                      1 -1  1 -1 -1 -1 -1 -1 -1  1
                   """
                   |> Enum.map(&String.to_integer/1)

  @moon_latitude_coeff ~w"""
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

  @moon_latitude_terms zip_terms([
                         @moon_latitude_coeff,
                         @moon_latitude_d,
                         @moon_latitude_m,
                         @moon_latitude_m_prime,
                         @moon_latitude_f
                       ])

  # -- Distance (Meeus Table 47.A cosine terms) -----------------------

  @moon_distance_d ~w"""
                      0  2  2  0  0  0  2  2  2  2
                      0  1  0  2  0  0  4  0  4  2
                      2  1  1  2  2  4  2  0  2  2
                      1  2  0  0  2  2  2  4  0  3
                      2  4  0  2  2  2  4  0  4  1
                      2  0  1  3  4  2  0  1  2  2
                   """
                   |> Enum.map(&String.to_integer/1)

  @moon_distance_m ~w"""
                      0  0  0  0  1  0  0 -1  0 -1
                      1  0  1  0  0  0  0  0  0  1
                      1  0  1 -1  0  0  0  1  0 -1
                      0 -2  1  2 -2  0  0 -1  0  0
                      1 -1  2  2  1 -1  0  0 -1  0
                      1  0  1  0  0 -1  2  1  0  0
                   """
                   |> Enum.map(&String.to_integer/1)

  @moon_distance_m_prime ~w"""
                            1 -1  0  2  0  0 -2 -1  1  0
                           -1  0  1  0  1  1 -1  3 -2 -1
                            0 -1  0  1  2  0 -3 -2 -1 -2
                            1  0  2  0 -1  1  0 -1  2 -1
                            1 -2 -1 -1 -2  0  1  4  0 -2
                            0  2  1 -2 -3  2  1 -1  3 -1
                         """
                         |> Enum.map(&String.to_integer/1)

  @moon_distance_f ~w"""
                      0  0  0  0  0  2  0  0  0  0
                      0  0  0 -2  2 -2  0  0  0  0
                      0  0  0  0  0  0  0  0  2  0
                      0  0  0  0  0 -2  2  0  2  0
                      0  0  0  0  0 -2  0  0  0  0
                     -2 -2  0  0  0  0  0  0  0 -2
                   """
                   |> Enum.map(&String.to_integer/1)

  @moon_distance_coeff ~w"""
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

  @moon_distance_terms zip_terms([
                         @moon_distance_coeff,
                         @moon_distance_d,
                         @moon_distance_m,
                         @moon_distance_m_prime,
                         @moon_distance_f
                       ])

  # -- New moon (periodic and additional correction terms) ----------

  @new_moon_sine_coeff [
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

  @new_moon_e_factor [
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

  @new_moon_solar_coeff [
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

  @new_moon_lunar_coeff [
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

  @new_moon_moon_coeff [
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

  @new_moon_terms zip_terms([
                    @new_moon_sine_coeff,
                    @new_moon_e_factor,
                    @new_moon_solar_coeff,
                    @new_moon_lunar_coeff,
                    @new_moon_moon_coeff
                  ])

  @new_moon_add_const [
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

  @new_moon_add_coeff [
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

  @new_moon_add_factor [
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

  @new_moon_additional_terms zip_terms([
                               @new_moon_add_const,
                               @new_moon_add_coeff,
                               @new_moon_add_factor
                             ])

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

  A new moon is the moment the lunar phase, the Moon's apparent ecliptic
  longitude minus the Sun's, passes 0°. It is found by refining the
  estimate of `nth_new_moon/1` (Meeus, *Astronomical Algorithms*, chapter
  49) to that crossing.

  Raises `ArgumentError` for a moment more than 50,000 years from J2000.
  Beyond about 75,000 years the chapter 49 estimates can be more than half
  a month from the new moons, and a search could settle on a neighbouring
  lunation's.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * A `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Accuracy

  Within a millisecond of the moment the phase passes 0°. Inside the
  ephemeris this matches Meeus's correct time for the new moon of 18
  February 1977 (example 49.a) to the second; outside it the series
  place new moons within 6.0 s RMS of JPL over 1900–2100. See
  `Astro.date_time_new_moon_before/1`.

  ### Examples

      iex> Astro.Lunar.date_time_new_moon_before 738390
      738375.5764820824

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 49 (phases of the Moon).

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_before(t :: Time.moment()) :: Time.moment()

  def date_time_new_moon_before(t) when is_number(t) do
    {lunation, _next_lunation} = searchable_lunations_around(t)
    new_moon = new_moon(lunation)

    cond do
      new_moon >= t -> new_moon(lunation - 1)
      t - new_moon < @shortest_lunation_days -> new_moon
      true -> latest_new_moon_before(t, new_moon, lunation + 1)
    end
  end

  @doc """
  Returns the date time of the new
  moon at or after a given moment.

  A new moon is the moment the lunar phase, the Moon's apparent ecliptic
  longitude minus the Sun's, passes 0°. It is found by refining the
  estimate of `nth_new_moon/1` (Meeus, *Astronomical Algorithms*, chapter
  49) to that crossing.

  Raises `ArgumentError` for a moment more than 50,000 years from J2000.
  Beyond about 75,000 years the chapter 49 estimates can be more than half
  a month from the new moons, and a search could settle on a neighbouring
  lunation's.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * a `t:Astro.Time.moment/0` which is a float number of days
    since `0000-01-01`.

  ### Accuracy

  Within a millisecond of the moment the phase passes 0°. Inside the
  ephemeris this matches Meeus's correct time for the new moon of 18
  February 1977 (example 49.a) to the second; outside it the series
  place new moons within 6.0 s RMS of JPL over 1900–2100. See
  `Astro.date_time_new_moon_before/1`.

  ### Examples

      iex> Astro.Lunar.date_time_new_moon_at_or_after(738390)
      738405.0359526364

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 49 (phases of the Moon).

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_at_or_after(t :: Time.moment()) :: Time.moment()

  def date_time_new_moon_at_or_after(t) when is_number(t) do
    {_previous_lunation, lunation} = searchable_lunations_around(t)
    new_moon = new_moon(lunation)

    cond do
      new_moon < t -> new_moon(lunation + 1)
      new_moon - t < @shortest_lunation_days -> new_moon
      true -> earliest_new_moon_at_or_after(t, new_moon, lunation - 1)
    end
  end

  @doc false
  # `{:ok, t}` when the new moon and lunar phase searches can answer for
  # `t`, within 50,000 years of J2000, and `{:error, :year_out_of_range}`
  # otherwise. `Astro` checks this so that its searches return an error
  # where the searches here raise.
  def checked_search_moment(t) when abs(t - @j2000_moment) > @new_moon_range_days do
    {:error, :year_out_of_range}
  end

  def checked_search_moment(t) do
    {:ok, t}
  end

  # The new moon searches start from the lunations whose Meeus chapter 49
  # estimates bracket `t`, and refine only the one they need to its
  # zero-phase crossing. When `t` falls between an estimate and its
  # crossing, the refined new moon lands on the other side of `t` and the
  # neighbouring lunation is the answer. Consecutive new moons are more than
  # 29 days apart, so a refined new moon on the right side of `t` and within
  # that of it is the answer; only further away is the neighbour refined to
  # check. A new moon is always refined from its own lunation's estimate,
  # so the same new moon is the same moment however it is reached.
  defp searchable_lunations_around(t) when abs(t - @j2000_moment) > @new_moon_range_days do
    raise ArgumentError,
          "new moons are found within #{@new_moon_range_years} years of J2000, " <>
            "where the Meeus chapter 49 estimates identify each lunation; " <>
            "moment #{inspect(t)} is outside that range"
  end

  defp searchable_lunations_around(t) do
    lunations_around(t)
  end

  # `new_moon` is before `t`; the next lunation's new moon may be too.
  defp latest_new_moon_before(t, new_moon, next_lunation) do
    next_new_moon = new_moon(next_lunation)

    if next_new_moon < t do
      next_new_moon
    else
      new_moon
    end
  end

  # `new_moon` is at or after `t`; the previous lunation's may be too.
  defp earliest_new_moon_at_or_after(t, new_moon, previous_lunation) do
    previous_new_moon = new_moon(previous_lunation)

    if previous_new_moon >= t do
      previous_new_moon
    else
      new_moon
    end
  end

  # The moment a lunation's new moon occurs: where the lunar phase passes 0°
  # near its Meeus chapter 49 estimate.
  #
  # The phase is smooth, so the secant method finds the crossing in a few
  # steps. The first step assumes the mean rate of the phase; each later
  # step draws the line through the last two phases and moves to where it
  # meets zero. The estimate is within seconds of the crossing near the
  # present and drifts as the square of the time from J2000 (about four
  # hours at −10,000), well inside the half month either side in which the
  # phase passes 0° only once.
  defp new_moon(lunation) do
    estimate = nth_new_moon(lunation)
    estimate_phase = signed_phase(estimate)
    first_step = estimate - estimate_phase / @mean_phase_rate
    secant(estimate, estimate_phase, first_step, @new_moon_steps)
  end

  defp secant(_previous, _previous_phase, current, 0) do
    current
  end

  defp secant(previous, previous_phase, current, steps) do
    current_phase = signed_phase(current)
    secant_step(previous, previous_phase, current, current_phase, steps)
  end

  defp secant_step(_previous, previous_phase, current, current_phase, _steps)
       when current_phase == previous_phase do
    current
  end

  defp secant_step(previous, previous_phase, current, current_phase, steps) do
    step = current_phase * (current - previous) / (current_phase - previous_phase)
    next = current - step

    if abs(step) < @new_moon_tolerance_days do
      next
    else
      secant(current, current_phase, next, steps - 1)
    end
  end

  # The lunar phase in the range -180° to 180°, so that it passes smoothly
  # through zero at new moon.
  defp signed_phase(t) do
    mod(lunar_phase_at(t) + 180.0, 360.0) - 180.0
  end

  # The lunations whose Meeus chapter 49 estimates are the last before `t`
  # and the first at or after it. Estimates strictly increase with the
  # lunation number, so the pair is found by starting from the lunation
  # nearest `t` in mean months and walking to its neighbour on the other side
  # of `t`. That start is within a couple of days of the estimate, so the
  # walk ends after one or two steps.
  defp lunations_around(t) do
    lunation = round((t - @new_moon_zero) / mean_synodic_month())

    if nth_new_moon(lunation) < t do
      walk_forward(lunation + 1, t)
    else
      walk_back(lunation - 1, t)
    end
  end

  # Lunation `lunation - 1` is before `t`.
  defp walk_forward(lunation, t) do
    if nth_new_moon(lunation) < t do
      walk_forward(lunation + 1, t)
    else
      {lunation - 1, lunation}
    end
  end

  # Lunation `lunation + 1` is at or after `t`.
  defp walk_back(lunation, t) do
    if nth_new_moon(lunation) < t do
      {lunation, lunation + 1}
    else
      walk_back(lunation - 1, t)
    end
  end

  @doc """
  Returns the moment of the new
  moon nearest to a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * a `t:Astro.Time.moment/0` which is a float number of days
    since `0000-01-01`.

  ### Accuracy

  Within a millisecond of the moment the phase passes 0°. Inside the
  ephemeris this matches Meeus's correct time for the new moon of 18
  February 1977 (example 49.a) to the second; outside it the series
  place new moons within 6.0 s RMS of JPL over 1900–2100. See
  `Astro.date_time_new_moon_before/1`.

  ### Examples

      iex> Astro.Lunar.date_time_new_moon_nearest(738390)
      738375.5764820818

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 49 (phases of the Moon).

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

  The phase is the Moon's apparent ecliptic longitude minus the Sun's,
  reduced to the range 0 to 360: 0° at new moon, 90° at first quarter,
  180° at full moon and 270° at last quarter.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * the lunar phase as a float number of
    degrees.

  ### Accuracy

  Outside the ephemeris the series agree with JPL over 1900–2100 to
  2.8″ RMS and 11.5″ at most, about 6 s in the time a phase is
  reached. See `Astro.lunar_phase_at/1`.

  ### Examples

      iex> Astro.Lunar.lunar_phase_at(738389.5007195644)
      179.99179178758195

      iex> Astro.Lunar.lunar_phase_at(738346.0544609067)
      0.014270322532084379

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Lunar phase](https://en.wikipedia.org/wiki/Lunar_phase), Wikipedia.

  """
  @doc since: "0.5.0"
  @spec lunar_phase_at(t :: Astro.Time.moment()) :: Astro.angle()

  def lunar_phase_at(t) when is_number(t) do
    mod(lunar_ecliptic_longitude(t) - Solar.solar_ecliptic_longitude(t), 360.0)
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
    `360.0`.

  ### Returns

  * A `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Accuracy

  The search ends within a millisecond of the crossing. Outside the
  ephemeris the series place the phases within about 6 s RMS of JPL
  over 1900–2100. See `Astro.date_time_lunar_phase_at_or_after/2`.

  ### Examples

      iex> Astro.Lunar.date_time_lunar_phase_at_or_before(738368, Astro.Lunar.new_moon_phase())
      738346.0532093873

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 49 (phases of the Moon).

  """
  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_before(t :: Time.moment(), phase :: Astro.phase()) ::
          Time.moment()

  def date_time_lunar_phase_at_or_before(t, phase) do
    tau = t - mean_synodic_month() * (1.0 / deg(360.0)) * mod(lunar_phase_at(t) - phase, 360.0)
    a = tau - 2
    b = min(t, tau + 2)
    invert_angular(&lunar_phase_at/1, phase, a, b, @phase_search_tolerance_days)
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
    `360`.

  ### Returns

  * a `t:Astro.Time.moment/0` which is a float number of days
    since `0000-01-01`.

  ### Accuracy

  The search ends within a millisecond of the crossing. Outside the
  ephemeris the series place the phases within about 6 s RMS of JPL
  over 1900–2100. See `Astro.date_time_lunar_phase_at_or_after/2`.

  ### Examples

      iex> Astro.Lunar.date_time_lunar_phase_at_or_after(738368, Astro.Lunar.full_moon_phase())
      738389.5013675035

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 49 (phases of the Moon).

  """
  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_after(t :: Time.moment(), phase :: Astro.phase()) ::
          Time.moment()

  def date_time_lunar_phase_at_or_after(t, phase) do
    tau = t + mean_synodic_month() * (1 / deg(360.0)) * mod(phase - lunar_phase_at(t), 360.0)
    a = max(t, tau - 2)
    b = tau + 2
    invert_angular(&lunar_phase_at/1, phase, a, b, @phase_search_tolerance_days)
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

  ### Accuracy

  From JPL inside the loaded ephemeris; elsewhere from
  `analytical_lunar_position/1`, within 2.7″ RMS in right ascension and
  1.3″ in declination of JPL over 1900–2100. See `Astro.moon_position_at/1`.

  ### Examples

      iex> {ra, _dec, _dist} = Astro.Lunar.lunar_position(738390)
      iex> Float.round(ra, 2)
      -19.96

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  """
  @doc since: "0.6.0"
  @spec lunar_position(Time.moment()) ::
          {Astro.angle(), Astro.angle(), Astro.meters()}

  def lunar_position(t) do
    {right_ascension, declination, distance} = apparent_moon_position(t)

    # Callers expect right ascension in (-180, 180], the range of the
    # previous atan2-based result, so it can occupy a Geo.PointZ longitude.
    right_ascension =
      if right_ascension > 180.0, do: right_ascension - 360.0, else: right_ascension

    {right_ascension, declination, distance}
  end

  # ── Choosing the source ───────────────────────────────────────────────────────
  #
  # The Moon's apparent position comes from the JPL ephemeris where the
  # loaded kernel covers the moment, and from the analytical series
  # everywhere else. Every position in this module goes through these two
  # functions, so the choice is made in one place. Distances are in metres.

  defp apparent_moon_position(t) do
    case Astro.Ephemeris.moon_position_from_moment(t) do
      {:ok, {right_ascension, declination, distance_km}} ->
        {right_ascension, declination, distance_km * Earth.meters_per_kilometer()}

      {:error, :not_found} ->
        analytical_lunar_position(t)
    end
  end

  defp apparent_moon_ecliptic_position(t) do
    case Astro.Ephemeris.moon_ecliptic_position(t) do
      {:ok, {longitude, latitude, distance_km}} ->
        {longitude, latitude, distance_km * Earth.meters_per_kilometer()}

      {:error, :not_found} ->
        analytical_lunar_ecliptic_position(t)
    end
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

  ### Accuracy

  For Meeus's example 48.a the result is 0.67856, against Meeus's
  0.6786. Outside the ephemeris the series agree with JPL to 0.0000045
  RMS over 1900–2100.

  ### Examples

      iex> Astro.Lunar.illuminated_fraction_of_moon(738390)
      ...> |> Float.round(4)
      0.9951

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 48 (illuminated fraction of the Moon's disk).

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

  * `0.0`.

  ### Examples

      iex> Astro.Lunar.new_moon_phase()
      0.0

  """
  @doc since: "0.5.0"
  @spec new_moon_phase() :: Astro.phase()
  def new_moon_phase do
    deg(0.0)
  end

  @doc """
  Returns the full moon phase angle in degrees.

  ### Returns

  * `180.0`.

  ### Examples

      iex> Astro.Lunar.full_moon_phase()
      180.0

  """
  @doc since: "0.5.0"
  @spec full_moon_phase() :: Astro.phase()
  def full_moon_phase do
    deg(180.0)
  end

  @doc """
  Returns the first quarter phase angle in degrees.

  ### Returns

  * `90.0`.

  ### Examples

      iex> Astro.Lunar.first_quarter_phase()
      90.0

  """
  @doc since: "0.5.0"
  @spec first_quarter_phase() :: Astro.phase()
  def first_quarter_phase do
    deg(90.0)
  end

  @doc """
  Returns the last quarter phase angle in degrees.

  ### Returns

  * `270.0`.

  ### Examples

      iex> Astro.Lunar.last_quarter_phase()
      270.0

  """
  @doc since: "0.5.0"
  @spec last_quarter_phase() :: Astro.phase()

  def last_quarter_phase do
    deg(270.0)
  end

  @doc false
  @doc since: "0.5.0"
  @spec lunar_ecliptic_longitude(Time.moment()) :: Astro.phase()

  def lunar_ecliptic_longitude(t) do
    case Astro.Ephemeris.moon_ecliptic_position(t) do
      {:ok, {longitude, _latitude, _distance}} -> longitude
      {:error, :not_found} -> analytical_lunar_longitude(t)
    end
  end

  @doc """
  Returns the Moon's ecliptic latitude in degrees for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The ecliptic latitude as a float in degrees.

  ### Accuracy

  From JPL inside the loaded ephemeris; elsewhere from the series,
  within 1.1″ RMS and 4.9″ at most of JPL over 1900–2100.

  ### Examples

      iex> Astro.Lunar.lunar_latitude(738390) |> Float.round(4)
      -5.0095

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  """
  @doc since: "0.6.0"
  @spec lunar_latitude(Time.moment()) :: Astro.angle()

  def lunar_latitude(t) do
    {_longitude, latitude, _distance} = apparent_moon_ecliptic_position(t)
    latitude
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

  ### Accuracy

  As accurate as the Moon's position (see `lunar_position/1`). It is
  geocentric and airless: seen from the Earth's surface the Moon is up
  to about 1° lower, its parallax, and refraction raises it by about
  34′ at the horizon.

  ### Examples

      iex> sydney = %Geo.PointZ{coordinates: {151.20666584, -33.8559799094, 0.0}}
      iex> Astro.Lunar.lunar_altitude(Astro.Time.j2000(), sydney) |> Float.round(4)
      -37.3277

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 13 (transformation of coordinates).

  * [Horizontal coordinate system](https://en.wikipedia.org/wiki/Horizontal_coordinate_system), Wikipedia.

  """
  @doc since: "0.4.0"
  @spec lunar_altitude(Time.moment(), Geo.PointZ.t()) :: Astro.angle()

  def lunar_altitude(t, %Geo.PointZ{coordinates: {psi, phi, _alt}}) do
    {alpha, delta, _distance} = apparent_moon_position(t)
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

  ### Accuracy

  From JPL inside the loaded ephemeris; elsewhere from the series,
  within 2.9 km RMS and 11.7 km at most of JPL over 1900–2100.

  ### Examples

      iex> Astro.Lunar.lunar_distance(738390) |> trunc()
      381257780

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  """
  @doc since: "0.6.0"
  @spec lunar_distance(t :: Time.moment()) :: Astro.meters()

  def lunar_distance(t) do
    {_longitude, _latitude, distance} = apparent_moon_ecliptic_position(t)
    distance
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

    correction =
      deg(-0.00017) * sin(omega) +
        sigma(
          @new_moon_terms,
          fn {v, w, x, y, z} ->
            v * :math.pow(e, w) *
              sin(x * solar_anomaly + y * lunar_anomaly + z * moon_argument)
          end
        )

    extra =
      deg(0.000325) *
        sin(poly(c, [299.77, 132.8475848, -0.009173]))

    additional = sigma(@new_moon_additional_terms, fn {i, j, l} -> l * sin(i + j * k) end)

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

  ### Accuracy

  It follows from the Moon's distance, which the series give within
  2.9 km RMS of JPL; that changes it by under 0.03″.

  ### Examples

      iex> Astro.Lunar.equatorial_horizontal_parallax(738390)
      ...> |> Float.round(4)
      0.9586

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Lunar parallax](https://en.wikipedia.org/wiki/Lunar_parallax), Wikipedia.

  """
  @spec equatorial_horizontal_parallax(t :: Time.moment()) :: Astro.angle()
  def equatorial_horizontal_parallax(t) do
    asin(Earth.earth_radius_m() / lunar_distance(t))
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

  ### Accuracy

  It follows from the Moon's distance, which the series give within
  2.9 km RMS of JPL; that changes it by under 0.03″.

  ### Examples

      iex> sydney = %Geo.PointZ{coordinates: {151.20666584, -33.8559799094, 0.0}}
      iex> Astro.Lunar.topocentric_lunar_parallax(Astro.Time.j2000(), sydney) |> Float.round(4)
      0.7221

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 40 (correction for parallax).

  * [Lunar parallax](https://en.wikipedia.org/wiki/Lunar_parallax), Wikipedia.

  """
  @spec topocentric_lunar_parallax(t :: Time.moment(), location :: Geo.PointZ.t()) ::
          Astro.angle()

  def topocentric_lunar_parallax(t, location) do
    :math.asin(sin(equatorial_horizontal_parallax(t)) * cos(lunar_altitude(t, location)))
    |> to_degrees()
  end

  @doc """
  Returns the Moon's angular semi-diameter in degrees for a given moment.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The angular semi-diameter as a float in degrees.

  ### Accuracy

  It follows from the Moon's distance, which the series give within
  2.9 km RMS of JPL; that changes it by under 0.03″.

  ### Examples

      iex> Astro.Lunar.angular_semi_diameter(Astro.Time.j2000()) |> Float.round(4)
      0.2473

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 55 (semidiameters of the Sun, Moon and planets).

  * [Angular diameter](https://en.wikipedia.org/wiki/Angular_diameter), Wikipedia.

  """
  @spec angular_semi_diameter(t :: Time.moment()) :: Astro.angle()
  def angular_semi_diameter(t) do
    asin(@lunar_radius_m / lunar_distance(t))
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

  * The horizontal dip as a float in degrees. For the Moon it is
    usually slightly positive, because its parallax exceeds refraction
    and its semi-diameter together.

  ### Accuracy

  It follows from the Moon's distance and the standard 34′ of
  refraction; the refraction of the real atmosphere at the horizon
  varies far more than the distance does.

  ### Examples

      iex> Astro.Lunar.horizontal_dip(Astro.Time.j2000()) |> Float.round(4)
      0.0941

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 15 (rising, transit and setting).

  """
  @spec horizontal_dip(t :: Time.moment()) :: Astro.angle()
  def horizontal_dip(t) do
    -(Earth.refraction() + angular_semi_diameter(t) - equatorial_horizontal_parallax(t))
  end

  # ── Fundamental arguments ───────────────────────────────────────────────────

  @doc """
  Returns the Moon's mean longitude in degrees for a given number of
  Julian centuries from J2000.0.

  The mean longitude is where the Moon would be if it moved uniformly
  along the ecliptic, measured from the equinox (Meeus, *Astronomical
  Algorithms*, equation 47.1). It is the base to which the periodic terms
  of the analytical series are added.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean longitude as a float in degrees, in the range 0 to 360.

  ### Accuracy

  This is a mean element, not a position: a polynomial in time on
  which the periodic terms of Meeus's chapter 47 series are built.
  The positions the series give are within 2.7″ RMS of JPL in
  longitude over 1900–2100; see `analytical_lunar_ecliptic_position/1`.

  ### Examples

      iex> Astro.Lunar.mean_lunar_ecliptic_longitude(0.0)
      218.3164477

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Mean longitude](https://en.wikipedia.org/wiki/Mean_longitude), Wikipedia.

  """
  @spec mean_lunar_ecliptic_longitude(c :: Time.julian_centuries()) :: Astro.angle()
  def mean_lunar_ecliptic_longitude(c) do
    c
    |> poly([218.3164477, 481_267.88123421, -0.0015786, 1 / 538_841.0, -1 / 65_194_000.0])
    |> degrees()
  end

  @doc """
  Returns the Moon's mean elongation from the Sun in degrees for a given
  number of Julian centuries from J2000.0.

  The mean elongation is the angle between the mean Moon and the mean
  Sun (Meeus, *Astronomical Algorithms*, equation 47.2): 0° at a mean new
  moon and 180° at a mean full moon.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean elongation as a float in degrees, in the range 0 to 360.

  ### Accuracy

  This is a mean element, not a position: a polynomial in time on
  which the periodic terms of Meeus's chapter 47 series are built.
  The positions the series give are within 2.7″ RMS of JPL in
  longitude over 1900–2100; see `analytical_lunar_ecliptic_position/1`.

  ### Examples

      iex> Astro.Lunar.lunar_elongation(0.0)
      297.8501921

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Elongation](https://en.wikipedia.org/wiki/Elongation_(astronomy)), Wikipedia.

  """
  @spec lunar_elongation(c :: Time.julian_centuries()) :: Astro.angle()
  def lunar_elongation(c) do
    c
    |> poly([297.8501921, 445_267.1114034, -0.0018819, 1 / 545_868, -1 / 113_065_000.0])
    |> degrees()
  end

  @doc """
  Returns the Sun's mean anomaly in degrees for a given number of
  Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean solar anomaly as a float in degrees.

  ### Accuracy

  This is a mean element, not a position: a polynomial in time on
  which the periodic terms of Meeus's chapter 47 series are built.
  The positions the series give are within 2.7″ RMS of JPL in
  longitude over 1900–2100; see `analytical_lunar_ecliptic_position/1`.

  ### Examples

      iex> Astro.Lunar.solar_anomaly(0.0)
      357.5291092

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Mean anomaly](https://en.wikipedia.org/wiki/Mean_anomaly), Wikipedia.

  """
  @spec solar_anomaly(c :: Time.julian_centuries()) :: Astro.angle()
  def solar_anomaly(c) do
    c
    |> poly([357.5291092, 35_999.0502909, -0.0001536, 1 / 24_490_000.0])
    |> degrees()
  end

  @doc """
  Returns the Moon's mean anomaly in degrees for a given number of
  Julian centuries from J2000.0.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean lunar anomaly as a float in degrees.

  ### Accuracy

  This is a mean element, not a position: a polynomial in time on
  which the periodic terms of Meeus's chapter 47 series are built.
  The positions the series give are within 2.7″ RMS of JPL in
  longitude over 1900–2100; see `analytical_lunar_ecliptic_position/1`.

  ### Examples

      iex> Astro.Lunar.lunar_anomaly(0.0)
      134.9633964

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Mean anomaly](https://en.wikipedia.org/wiki/Mean_anomaly), Wikipedia.

  """
  @spec lunar_anomaly(c :: Time.julian_centuries()) :: Astro.angle()
  def lunar_anomaly(c) do
    c
    |> poly([134.9633964, 477_198.8675055, 0.0087414, 1 / 69_699.0, -1 / 14_712_000.0])
    |> degrees()
  end

  @doc """
  Returns the angular distance of the Moon's node from the equinoctial
  point in degrees for a given moment.

  This is the Moon's argument of latitude, `moon_node/1`, reduced to the
  range -90.0 to 90.0.

  ### Arguments

  * `t` is a `t:Astro.Time.moment/0` float number of days
    since `0000-01-01`.

  ### Returns

  * The angular distance as a float in degrees, from -90.0 to 90.0.

  ### Examples

      iex> Astro.Lunar.lunar_node(Astro.Time.j2000()) |> Float.round(6)
      -86.718131

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Lunar node](https://en.wikipedia.org/wiki/Lunar_node), Wikipedia.

  """
  @spec lunar_node(t :: Time.moment()) :: Astro.angle()
  def lunar_node(t) do
    c = julian_centuries_from_moment(t)

    (moon_node(c) + deg(90.0))
    |> mod(180.0)
    |> Kernel.-(90.0)
  end

  @doc """
  Returns the Moon's mean argument of latitude, its mean angular
  distance from its ascending node, in degrees for a given number of
  Julian centuries from J2000.0.

  This is Meeus's *F* (Astronomical Algorithms, eq. 47.5), named
  `moon-node` in Calendrical Calculations.

  ### Arguments

  * `c` is the number of Julian centuries from J2000.0.

  ### Returns

  * The mean argument of latitude as a float in degrees.

  ### Accuracy

  This is a mean element, not a position: a polynomial in time on
  which the periodic terms of Meeus's chapter 47 series are built.
  The positions the series give are within 2.7″ RMS of JPL in
  longitude over 1900–2100; see `analytical_lunar_ecliptic_position/1`.

  ### Examples

      iex> Astro.Lunar.moon_node(0.0)
      93.272095

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Argument of latitude](https://en.wikipedia.org/wiki/Argument_of_latitude), Wikipedia.

  """
  @spec moon_node(c :: Time.julian_centuries()) :: Astro.angle()
  def moon_node(c) do
    c
    |> poly([93.2720950, 483_202.0175233, -0.0036539, -1 / 3_526_000.0, 1 / 863_310_000.0])
    |> degrees()
  end

  # ── Analytical series ─────────────────────────────────────────────────────────

  @doc """
  Returns the Moon's apparent geocentric ecliptic position from analytical
  series.

  The longitude, latitude and distance are the periodic series of Meeus,
  *Astronomical Algorithms*, chapter 47, with the nutation in longitude of
  `Astro.Earth.nutation/1` added to give the apparent longitude. Each
  periodic term's argument combines the fundamental arguments; terms that
  depend on the Sun's anomaly are scaled by the eccentricity factor of the
  Earth's orbit. Over 1900–2100 the longitude agrees with the JPL DE440s
  ephemeris to about 3″ RMS.

  ### Arguments

  * `t` is a moment (fractional days since the epoch).

  ### Returns

  * `{longitude, latitude, distance}` where `longitude` is in degrees in
    the range 0 to 360, `latitude` is in degrees and `distance` is in
    metres.

  ### Accuracy

  Against JPL over 1900–2100: longitude 2.7″ RMS and 13.5″ at most,
  latitude 1.1″ RMS and 4.9″ at most, and distance 2.9 km RMS. The
  [accuracy guide](accuracy.md) gives the details, and how the series
  drift far from the present.

  ### Examples

  Meeus, *Astronomical Algorithms*, example 47.a, gives 133.167265°,
  −3.229126° and 368,409.7 km for 1992 April 12 at 0h TD; the small
  difference is Meeus's value of the nutation:

      iex> moment = Astro.Time.dynamical_time_to_moment((2_448_724.5 - 2_451_545.0) * 86_400.0)
      iex> {longitude, latitude, distance} = Astro.Lunar.analytical_lunar_ecliptic_position(moment)
      iex> {Float.round(longitude, 6), Float.round(latitude, 6), Float.round(distance / 1000.0, 1)}
      {133.167263, -3.229131, 368409.7}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * [Ephemeride Lunaire Parisienne](https://en.wikipedia.org/wiki/Ephemeride_Lunaire_Parisienne), Wikipedia.

  """
  @doc since: "2.10.0"
  @spec analytical_lunar_ecliptic_position(Time.moment()) :: {float(), float(), float()}
  def analytical_lunar_ecliptic_position(t) do
    {longitude, latitude, distance, _true_obliquity} = analytical_moon(t)
    {longitude, latitude, distance}
  end

  @doc """
  Returns the Moon's apparent geocentric right ascension, declination and
  distance from analytical series.

  The ecliptic position of `analytical_lunar_ecliptic_position/1` is
  rotated to the equator with the true obliquity of the ecliptic by
  `Astro.Coordinates.ecliptic_to_equatorial/3`.

  ### Arguments

  * `t` is a moment (fractional days since the epoch).

  ### Returns

  * `{right_ascension, declination, distance}` where `right_ascension`
    is in degrees in the range 0 to 360, `declination` is in degrees and
    `distance` is in metres.

  ### Accuracy

  Against JPL over 1900–2100: right ascension 2.7″ RMS and
  declination 1.3″ RMS (10.1″ and 6.5″ at most). The
  [accuracy guide](accuracy.md) gives the details.

  ### Examples

  Meeus, *Astronomical Algorithms*, example 47.a, gives 134.688470° and
  13.768368° for 1992 April 12 at 0h TD:

      iex> moment = Astro.Time.dynamical_time_to_moment((2_448_724.5 - 2_451_545.0) * 86_400.0)
      iex> {right_ascension, declination, _distance} = Astro.Lunar.analytical_lunar_position(moment)
      iex> {Float.round(right_ascension, 6), Float.round(declination, 6)}
      {134.688466, 13.768364}

  ### Reference

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 47 (position of the Moon).

  * Jean Meeus, *Astronomical Algorithms*, 2nd edition (1998),
    chapter 13 (transformation of coordinates).

  """
  @doc since: "2.10.0"
  @spec analytical_lunar_position(Time.moment()) :: {float(), float(), float()}
  def analytical_lunar_position(t) do
    {longitude, latitude, distance, true_obliquity} = analytical_moon(t)

    {right_ascension, declination} =
      Astro.Coordinates.ecliptic_to_equatorial(longitude, latitude, true_obliquity)

    {right_ascension, declination, distance}
  end

  # The Moon's apparent longitude and latitude in degrees, its distance in
  # metres and the true obliquity in degrees, sharing one evaluation of the
  # fundamental arguments and of the nutation.
  defp analytical_moon(t) do
    c = julian_centuries_from_moment(t)
    {delta_psi, delta_epsilon, mean_obliquity} = Earth.nutation(c)
    arguments = fundamental_arguments(c)

    longitude = apparent_series_longitude(c, arguments, delta_psi)
    distance = lunar_distance_series(arguments) * Earth.meters_per_kilometer()

    {longitude, lunar_latitude_series(c, arguments), distance,
     Math.to_degrees(mean_obliquity + delta_epsilon)}
  end

  # The apparent longitude alone, for the lunar phase, which needs neither
  # the latitude nor the distance series.
  defp analytical_lunar_longitude(t) do
    c = julian_centuries_from_moment(t)
    {delta_psi, _delta_epsilon, _mean_obliquity} = Earth.nutation(c)
    apparent_series_longitude(c, fundamental_arguments(c), delta_psi)
  end

  # The series longitude plus the nutation in longitude, from 0° to 360°.
  defp apparent_series_longitude(c, arguments, delta_psi) do
    mod(lunar_longitude_series(c, arguments) + Math.to_degrees(delta_psi), 360.0)
  end

  # The five fundamental arguments of Meeus 47.1 to 47.5, in degrees, and
  # the eccentricity factor E of Meeus 47.6, which scales the terms that
  # depend on the Sun's anomaly as the Earth's orbit grows more circular.
  defp fundamental_arguments(c) do
    %{
      mean_longitude: mean_lunar_ecliptic_longitude(c),
      elongation: lunar_elongation(c),
      sun_anomaly: solar_anomaly(c),
      moon_anomaly: lunar_anomaly(c),
      argument_of_latitude: moon_node(c),
      eccentricity: poly(c, [1.0, -0.002516, -0.0000074])
    }
  end

  # Sum of one table's periodic terms. Each term's argument is
  # D·elongation + M·sun anomaly + M'·moon anomaly + F·argument of latitude,
  # and a term with |M| of 1 or 2 is scaled by E or E².
  defp periodic_terms(terms, arguments, trigonometric) do
    %{
      elongation: elongation,
      sun_anomaly: sun_anomaly,
      moon_anomaly: moon_anomaly,
      argument_of_latitude: argument_of_latitude,
      eccentricity: eccentricity
    } = arguments

    sigma(terms, fn {coefficient, d, m, m_prime, f} ->
      argument =
        d * elongation + m * sun_anomaly + m_prime * moon_anomaly + f * argument_of_latitude

      coefficient * :math.pow(eccentricity, abs(m)) * trigonometric.(argument)
    end)
  end

  # Meeus 47.7 and the additive terms for Venus (A1), Jupiter (A2) and the
  # flattening of the Earth, in units of 0.000001°.
  defp lunar_longitude_series(c, arguments) do
    %{mean_longitude: mean_longitude, argument_of_latitude: argument_of_latitude} = arguments

    additive =
      3958 * sin(119.75 + 131.849 * c) + 1962 * sin(mean_longitude - argument_of_latitude) +
        318 * sin(53.09 + 479_264.29 * c)

    mean_longitude +
      (periodic_terms(@moon_longitude_terms, arguments, &sin/1) + additive) / 1_000_000
  end

  # Meeus 47.8 and its additive terms, in units of 0.000001°.
  defp lunar_latitude_series(c, arguments) do
    %{
      mean_longitude: mean_longitude,
      moon_anomaly: moon_anomaly,
      argument_of_latitude: argument_of_latitude
    } = arguments

    a1 = 119.75 + 131.849 * c
    a3 = 313.45 + 481_266.484 * c

    additive =
      -2235 * sin(mean_longitude) + 382 * sin(a3) + 175 * sin(a1 - argument_of_latitude) +
        175 * sin(a1 + argument_of_latitude) + 127 * sin(mean_longitude - moon_anomaly) -
        115 * sin(mean_longitude + moon_anomaly)

    (periodic_terms(@moon_latitude_terms, arguments, &sin/1) + additive) / 1_000_000
  end

  # Meeus 47.9: the mean distance in kilometres plus the cosine terms in
  # units of 0.001 km.
  defp lunar_distance_series(arguments) do
    @moon_mean_distance_km + periodic_terms(@moon_distance_terms, arguments, &cos/1) / 1000
  end
end
