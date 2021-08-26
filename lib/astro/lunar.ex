defmodule Astro.Lunar do
  @moduledoc """
  Calulates lunar phases.

  Each of the phases of the Moon is defined by the
  angle between the Moon and Sun in the sky. When the Moon
  is in between the Earth and the Sun, so that there is nearly a
  zero degree separation, we see a New Moon.

  Because the orbit of the Moon is tilted in relation to the
  Earth’s orbit around the Sun, a New Moon can still be as much
  as 5.2 degrees away from the Sun, thus why there isn't a
  solar eclipse every month.

  A crescent moon is 45 degrees from the Sun, a quarter moon
  is 90 degrees from the Sun, a gibbous moon is 135 degrees
  from the Sun, and the Full Moon is 180 degrees away from
  the Sun.

  """

  alias Astro.{Math, Time}

  import Astro.Math, only: [
    deg: 1,
    sin: 1,
    cos: 1,
    sigma: 2,
    mod: 2,
    degrees: 1,
    poly: 2,
    invert_angular: 4
  ]

  import Astro.Time, only: [
    j2000: 0,
    julian_centuries_from_moment: 1
  ]

  @mean_synodic_month 29.530588861
  @months_epoch_to_j2000 24_724.0
  # @average_distance_earth_to_moon 385_000_560.0

  @doc """
  Returns the date time of the new
  moon before a given moment.

  ## Arguments

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Returns

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Example

      iex> Astro.Lunar.date_time_new_moon_before 738390
      738375.5774296349

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_before(Time.moment()) :: Time.moment()

  def date_time_new_moon_before(t) when is_number(t) do
    t0 = nth_new_moon(0.0)
    phi = lunar_phase_at(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360.0))
    nth_new_moon(Math.final(1.0 - n, &(nth_new_moon(&1) < t)))
  end

  @doc """
  Returns the date time of the new
  moon at or after a given date or
  date time.

  ## Arguments

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Returns

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Example

      iex> Astro.Lunar.date_time_new_moon_at_or_after 738390
      738405.036174502

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_at_or_after(Time.moment()) :: Time.moment()

  def date_time_new_moon_at_or_after(t) when is_number(t) do
    t0 = nth_new_moon(0.0)
    phi = lunar_phase_at(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360.0))
    nth_new_moon(Math.next(n, &(nth_new_moon(&1) >= t)))
  end

  @doc """
  Returns the lunar phase as a
  float number of degrees at a given
  moment.

  ## Arguments

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Returns

  * the lunar phase as a float number of
    degrees.

  ## Example

      iex> Astro.Lunar.lunar_phase_at 738389.5007195644
      180.00001443052076

      iex> Astro.Lunar.lunar_phase_at 738346.0544609067
      359.9999929267571

  """
  @doc since: "0.5.0"
  @spec lunar_phase_at(Time.moment()) :: Time.moment()

  def lunar_phase_at(t) when is_number(t) do
    phi = mod(lunar_longitude(t) - solar_longitude(t), 360)
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

  ## Arguments

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0.0` and
    `360.0`

  ## Returns

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Example

      iex> Astro.Lunar.date_time_lunar_phase_at_or_before(738368, Astro.Lunar.new_moon())
      738346.0544609067

  """

  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_before(Time.moment(), Astro.phase()) :: Time.moment()

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

  ## Arguments

  * a `moment` which is a float number of days
    since `0000-01-01`

  * `phase` is the required lunar phase expressed
    as a float number of degrees between `0` and
    `3660`

  ## Returns

  * a `t:Time.moment()` which is a float number of days
    since `0000-01-01`

  ## Example

      iex> Astro.Lunar.date_time_lunar_phase_at_or_after(738368, Astro.Lunar.full_moon())
      738389.5007195644

  """

  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_after(Time.moment(), Astro.phase()) :: Time.moment()

  def date_time_lunar_phase_at_or_after(t, phase) do
    tau = t + mean_synodic_month() * (1 / deg(360.0)) * mod(phase - lunar_phase_at(t), 360.0)
    a = max(t, tau - 2)
    b = tau + 2
    invert_angular(&lunar_phase_at/1, phase, a, b)
  end

  @doc """
  Returns the new moon lunar
  phase expressed as a float number
  of degrees.

  """
  @doc since: "0.5.0"
  @spec new_moon() :: Astro.phase()
  def new_moon() do
    deg(0.0)
  end

  @doc """
  Returns the full moon lunar
  phase expressed as a float number
  of degrees.

  """
  @doc since: "0.5.0"
  @spec full_moon() :: Astro.phase()
  def full_moon() do
    deg(180.0)
  end

  @doc """
  Returns the first quarter lunar
  phase expressed as a float number
  of degrees.

  """
  @doc since: "0.5.0"
  @spec first_quarter() :: Astro.phase()
  def first_quarter() do
    deg(90.0)
  end

  @doc """
  Returns the last quarter lunar
  phase expressed as a float number
  of degrees.

  """
  @doc since: "0.5.0"
  @spec last_quarter() :: Astro.phase()
  def last_quarter() do
    deg(270.0)
  end

  @doc false
  def mean_synodic_month do
    @mean_synodic_month
  end

  @doc false
  @spec nth_new_moon(number()) :: Time.moment()
  defp nth_new_moon(n) do
    k = n - @months_epoch_to_j2000 # months since j2000
    c = k / 1_236.85

    approx =
      j2000() +
      poly(c, [5.09766, mean_synodic_month() * 1236.85, 0.0001437, -0.000000150, 0.00000000073])

    e =
      poly(c, [1.0, -0.002516, -0.0000074])

    solar_anomaly = poly(c,
      Enum.map([2.5534, 1236.85 * 29.10535670, -0.000 - 0014, -0.00000011], &deg/1))

    lunar_anomaly = poly(c,
      Enum.map([201.5643, 385.81693528 * 1236.85, 0.0107582, 0.00001238, -0.000000058], &deg/1))

    moon_argument = poly(c,
      Enum.map([160.7108, 390.67050284 * 1236.85, -0.0016118, -0.00000227, 0.000000011], &deg/1))

    omega = poly(c,
      Enum.map([124.7746, -1.56375588 * 1236.85, 0.0020672, 0.00000215], &deg/1))

    sine_coeff = [
      -0.40720, 0.17241, 0.01608, 0.01039, 0.00739,
      -0.00514, 0.00208, -0.00111, -0.00057, 0.00056,
      -0.00042, 0.00042, 0.00038, -0.00024, -0.00007,
      0.00004, 0.00004, 0.00003, 0.00003, -0.00003,
      0.00003, -0.00002, -0.00002, 0.00002
    ]

    e_factor = [
      0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 2.0, 0.0, 0.0, 1.0, 0.0, 1.0,
      1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    ]

    solar_coeff = [
      0.0, 1.0, 0.0, 0.0, -1.0, 1.0, 2.0, 0.0, 0.0, 1.0, 0.0, 1.0,
      1.0, -1.0, 2.0, 0.0, 3, 1.0, 0.0, 1.0, -1.0, -1.0, 1.0, 0.0
    ]

    lunar_coeff = [
      1.0, 0.0, 2.0, 0.0, 1.0, 1.0, 0.0, 1.0, 1.0, 2.0, 3.0, 0.0,
      0.0, 2.0, 1.0, 2.0, 0.0, 1.0, 2.0, 1.0, 1.0, 1.0, 3.0, 4.0
    ]

    moon_coeff = [
      0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, -2.0, 2.0, 0.0, 0.0, 2.0,
      -2.0, 0.0, 0.0, -2.0, 0.0, -2.0, 2.0, 2.0, 2.0, -2.0, 0.0, 0.0
    ]

    correction =
      deg(-0.00017) * sin(omega) +
      sigma(
        [sine_coeff, e_factor, solar_coeff, lunar_coeff, moon_coeff],
        fn [v,w,x,y,z] ->
          v * :math.pow(e, w) *
          sin(x * solar_anomaly + y * lunar_anomaly + z * moon_argument)
       end
      )

    extra =
      deg(0.000325) *
      sin(poly(c, Enum.map([299.77, 132.8475848, -0.009173], &deg/1)))

    add_const = [
      251.88, 251.83, 349.42, 84.66, 141.74, 207.14, 154.84,
      34.52, 207.19, 291.34, 161.72, 239.56, 331.55
    ]

    add_coeff = [
      0.016321, 26.651886, 36.412478, 18.206239, 53.303771,
      2.453732, 7.306860, 27.261239, 0.121824, 1.844379,
      24.198154, 25.513099, 3.592518
    ]

    add_factor = [
      0.000165, 0.000164, 0.000126, 0.000110, 0.000062, 0.000060,
      0.000056, 0.000047, 0.000042, 0.000040, 0.000037, 0.000035,
      0.000023
    ]

    additional = sigma([add_const, add_coeff, add_factor], fn [i,j,l] -> l * sin(i + j * k) end)
    Time.universal_from_dynamical(approx + correction + extra + additional)
  end

  @doc false
  @spec lunar_longitude(Time.moment()) :: Astro.phase()
  def lunar_longitude(t) do
    c = julian_centuries_from_moment(t)
    l = mean_lunar_longitude(c)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    args_lunar_elong = [
      0.0,2.0,2.0,0.0,0.0,0.0,2.0,2.0,2.0,2.0,0.0,1.0,0.0,2.0,0.0,0.0,4.0,0.0,4.0,2.0,2.0,1.0,
      1.0,2.0,2.0,4.0,2.0,0.0,2.0,2.0,1.0,2.0,0.0,0.0,2.0,2.0,2.0,4.0,0.0,3.0,2.0,4.0,0.0,2.0,
      2.0,2.0,4.0,0.0,4.0,1.0,2.0,0.0,1.0,3.0,4.0,2.0,0.0,1.0,2.0
    ]

    args_solar_anom = [
      0.0,0.0,0.0,0.0,1.0,0.0,0.0,-1.0,0.0,-1.0,1.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,1.0,
      0.0,1.0,-1.0,0.0,0.0,0.0,1.0,0.0,-1.0,0.0,-2.0,1.0,2.0,-2.0,0.0,0.0,-1.0,0.0,0.0,1.0,
      -1.0,2.0,2.0,1.0,-1.0,0.0,0.0,-1.0,0.0,1.0,0.0,1.0,0.0,0.0,-1.0,2.0,1.0,0.0
    ]

    args_lunar_anom = [
      1.0,-1.0,0.0,2.0,0.0,0.0,-2.0,-1.0,1.0,0.0,-1.0,0.0,1.0,0.0,1.0,1.0,-1.0,3.0,-2.0,
      -1.0,0.0,-1.0,0.0,1.0,2.0,0.0,-3.0,-2.0,-1.0,-2.0,1.0,0.0,2.0,0.0,-1.0,1.0,0.0,
      -1.0,2.0,-1.0,1.0,-2.0,-1.0,-1.0,-2.0,0.0,1.0,4.0,0.0,-2.0,0.0,2.0,1.0,-2.0,-3.0,
      2.0,1.0,-1.0,3.0
    ]

    args_moon_node = [
      0.0,0.0,0.0,0.0,0.0,2.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-2.0,2.0,-2.0,0.0,0.0,0.0,0.0,0.0,
      0.0,0.0,0.0,0.0,0.0,0.0,0.0,2.0,0.0,0.0,0.0,0.0,0.0,0.0,-2.0,2.0,0.0,2.0,0.0,0.0,0.0,0.0,
      0.0,0.0,-2.0,0.0,0.0,0.0,0.0,-2.0,-2.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0
    ]

    sine_coeff = [
      6288774.0, 1274027.0, 658314.0, 213618.0, -185116.0, -114332.0,
      58793.0, 57066.0, 53322.0, 45758.0, -40923.0, -34720.0, -30383.0,
      15327.0, -12528.0, 10980.0, 10675.0, 10034.0, 8548.0, -7888.0,
      -6766.0, -5163.0, 4987.0, 4036.0, 3994.0, 3861.0, 3665.0, -2689.0,
      -2602.0, 2390.0, -2348.0, 2236.0, -2120.0, -2069.0, 2048.0, -1773.0,
      -1595.0, 1215.0, -1110.0, -892.0, -810.0, 759.0, -713.0, -700.0, 691.0,
      596.0, 549.0, 537.0, 520.0, -487.0, -399.0, -381.0, 351.0, -340.0, 330.0,
      327.0, -323.0, 299.0, 294.0
    ]

    correction = deg(1.0 / 1000000.0) * Math.sigma(
        [sine_coeff, args_lunar_elong, args_solar_anom, args_lunar_anom, args_moon_node],
        fn [v,w,x,y,z] ->
            v * :math.pow(e, abs(x)) * sin(w * d + x * m + y * m_prime + z * f)
        end
    )
    venus = deg(3958.0 / 1000000.0) * sin(deg(119.75) + c * deg(131.849))
    jupiter = deg(318.0 / 1000000.0) * sin(deg(53.09) + c * deg(479264.29))
    flat_earth = deg(1962.0 / 1000000.0) * sin(l - f)
    mod(l + correction + venus + jupiter + flat_earth + nutation(t), 360.0)
  end

  @doc false
  def mean_lunar_longitude(c) do
    degrees(poly(c,
      Enum.map([218.3164477, 481267.88123421, -0.0015786, 1/538841, -1/65194000], &deg/1)
    ))
  end

  @doc false
  def lunar_elongation(c) do
    degrees(poly(c,
      Enum.map([297.8501921, 445267.1114034, -0.0018819, 1/545868, -1/113065000], &deg/1)
    ))
  end

  @doc false
  def solar_anomaly(c) do
    degrees(poly(c,
      Enum.map([357.5291092, 35999.0502909, -0.0001536, 1.0 / 24490000.0], &deg/1)
    ))
  end

  @doc false
  def lunar_anomaly(c) do
    degrees(poly(c,
      Enum.map([134.9633964, 477198.8675055, 0.0087414, 1/69699, -1/14712000], &deg/1)
    ))
  end

  @doc false
  defp moon_node(x) do
    degrees(poly(x,
      Enum.map([93.2720950, 483202.0175233, -0.0036539, -1 / 3526000.0, 1 / 863310000.0], &deg/1)
    ))
  end

  @doc false
  @spec nutation(Time.moment()) :: Astro.angle()
  def nutation(t) do
    c = julian_centuries_from_moment(t)
    a = poly(c, Enum.map([124.90, -1934.134, 0.002063], &deg/1))
    b = poly(c, Enum.map([201.11, 72001.5377, 0.00057], &deg/1))
    deg(-0.004778) * sin(a) + deg(-0.0003667) * sin(b)
  end

  # This should be replacable with the functions in Astro.Solar but
  # need to work out which one is is: mean, apparent or true

  @doc false
  @spec solar_longitude(Time.moment()) :: Time.season()
  def solar_longitude(t) do
    c = julian_centuries_from_moment(t)

    coefficients = [
      403406.0, 195207.0, 119433.0, 112392.0, 3891.0, 2819.0, 1721.0,
      660.0, 350.0, 334.0, 314.0, 268.0, 242.0, 234.0, 158.0, 132.0, 129.0, 114.0,
      99.0, 93.0, 86.0, 78.0, 72.0, 68.0, 64.0, 46.0, 38.0, 37.0, 32.0, 29.0, 28.0, 27.0, 27.0,
      25.0, 24.0, 21.0, 21.0, 20.0, 18.0, 17.0, 14.0, 13.0, 13.0, 13.0, 12.0, 10.0, 10.0, 10.0,
      10.0
    ]

    multipliers = [
      0.9287892, 35999.1376958, 35999.4089666,
      35998.7287385, 71998.20261, 71998.4403,
      36000.35726, 71997.4812, 32964.4678,
      -19.4410, 445267.1117, 45036.8840, 3.1008,
      22518.4434, -19.9739, 65928.9345,
      9038.0293, 3034.7684, 33718.148, 3034.448,
      -2280.773, 29929.992, 31556.493, 149.588,
      9037.750, 107997.405, -4444.176, 151.771,
      67555.316, 31556.080, -4561.540,
      107996.706, 1221.655, 62894.167,
      31437.369, 14578.298, -31931.757,
      34777.243, 1221.999, 62894.511,
      -4442.039, 107997.909, 119.066, 16859.071,
      -4.578, 26895.292, -39.127, 12297.536,
      90073.778
    ]

    addends = [
      270.54861, 340.19128, 63.91854, 331.26220,
      317.843, 86.631, 240.052, 310.26, 247.23,
      260.87, 297.82, 343.14, 166.79, 81.53,
      3.50, 132.75, 182.95, 162.03, 29.8,
      266.4, 249.2, 157.6, 257.8, 185.1, 69.9,
      8.0, 197.1, 250.4, 65.3, 162.7, 341.5,
      291.6, 98.5, 146.7, 110.0, 5.2, 342.6,
      230.9, 256.1, 45.3, 242.9, 115.2, 151.8,
      285.3, 53.3, 126.6, 205.7, 85.9,
      146.1
    ]

    lambda =
      deg(282.7771834) + deg(36000.76953744) * c +
      deg(0.000005729577951308232) *
      sigma(
        [coefficients, addends, multipliers],
        fn [x, y, z] -> x * sin(y + z * c) end
      )

    mod(lambda + aberration(t) + nutation(t), 360.0)
  end

  @doc false
  @spec aberration(Time.moment()) :: Astro.angle()
  def aberration(t) do
    c = julian_centuries_from_moment(t)
    deg(0.0000974) * cos(deg(177.63) + deg(35999.01848) * c) - deg(0.005575)
  end

end
