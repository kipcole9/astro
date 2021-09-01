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

  alias Astro.{Math, Time, Solar}

  import Astro.Math, only: [
    deg: 1,
    sin: 1,
    cos: 1,
    mt: 1,
    asin: 1,
    sigma: 2,
    mod: 2,
    degrees: 1,
    poly: 2,
    invert_angular: 4
  ]

  import Astro.Time, only: [
    j2000: 0,
    julian_centuries_from_moment: 1,
    mean_synodic_month: 0
  ]

  import Astro.Earth, only: [
    nutation: 1
  ]

  @months_epoch_to_j2000 24_724
  @average_distance_earth_to_moon 385_000_560.0

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
      738375.5774295913

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_before(Time.moment()) :: Time.moment()

  def date_time_new_moon_before(t) when is_number(t) do
    t0 = nth_new_moon(0)
    phi = lunar_phase_at(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360)) |> trunc()
    nth_new_moon(Math.final(n - 1, &(nth_new_moon(&1) < t)))
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
      738405.0361744585

  """
  @doc since: "0.5.0"
  @spec date_time_new_moon_at_or_after(Time.moment()) :: Time.moment()

  def date_time_new_moon_at_or_after(t) when is_number(t) do
    t0 = nth_new_moon(0)
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
      180.00001498208536

      iex> Astro.Lunar.lunar_phase_at 738346.0544609067
      359.9999934575342

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
      738346.0544608677

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
      738389.5007195254

  """
  @doc since: "0.5.0"
  @spec date_time_lunar_phase_at_or_after(Time.moment(), Astro.phase()) :: Time.moment()

  def date_time_lunar_phase_at_or_after(t, phase) do
    tau = t + mean_synodic_month() * (1 / deg(360.0)) * mod(phase - lunar_phase_at(t), 360.0)
    a = max(t, tau - 2)
    b = tau + 2
    invert_angular(&lunar_phase_at/1, phase, a, b)
  end

  @doc since: "0.6.0"
  @spec lunar_position(Time.moment()) :: {Astro.angle(), Astro.angle(), Astro.meters()}

  def lunar_position(t) do
    lambda = lunar_longitude(t)
    beta = lunar_latitude(t)
    distance = lunar_distance(t)

    {Astro.right_ascension(t, beta, lambda), Astro.declination(t, beta, lambda), distance}
  end

  @doc """
  Returns the fractional illumination of the moon
  at a given time as a fraction between 0.0 and 1.0.

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
  @doc since: "0.5.0"
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
      0, 2, 2, 0, 0, 0, 2, 2, 2, 2, 0, 1, 0, 2, 0, 0, 4, 0, 4, 2, 2, 1,
      1, 2, 2, 4, 2, 0, 2, 2, 1, 2, 0, 0, 2, 2, 2, 4, 0, 3, 2, 4, 0, 2,
      2, 2, 4, 0, 4, 1, 2, 0, 1, 3, 4, 2, 0, 1, 2
    ]

    args_solar_anom = [
      0, 0, 0, 0, 1, 0, 0, -1, 0, -1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1,
      0, 1, -1, 0, 0, 0, 1, 0, -1, 0, -2, 1, 2, -2, 0, 0, -1, 0, 0, 1,
      -1, 2, 2, 1, -1, 0, 0, -1, 0, 1, 0, 1, 0, 0, -1, 2, 1, 0
    ]

    args_lunar_anom = [
      1, -1, 0, 2, 0, 0, -2, -1, 1, 0, -1, 0, 1, 0, 1, 1, -1, 3, -2,
      -1, 0, -1, 0, 1, 2, 0, -3, -2, -1, -2, 1, 0, 2, 0, -1, 1, 0,
      -1, 2, -1, 1, -2, -1, -1, -2, 0, 1, 4, 0, -2, 0, 2, 1, -2, -3,
      2, 1, -1, 3
    ]

    args_moon_node = [
      0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, -2, 2, -2, 0, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, -2, 2, 0, 2, 0, 0, 0, 0,
      0, 0, -2, 0, 0, 0, 0, -2, -2, 0, 0, 0, 0, 0, 0, 0
    ]

    sine_coeff = [
      6288774, 1274027, 658314, 213618, -185116, -114332,
      58793, 57066, 53322, 45758, -40923, -34720, -30383,
      15327, -12528, 10980, 10675, 10034, 8548, -7888,
      -6766, -5163, 4987, 4036, 3994, 3861, 3665, -2689,
      -2602, 2390, -2348, 2236, -2120, -2069, 2048, -1773,
      -1595, 1215, -1110, -892, -810, 759, -713, -700, 691,
      596, 549, 537, 520, -487, -399, -381, 351, -340, 330,
      327, -323, 299, 294
    ]

    correction = deg(1 / 1000000) * sigma(
        [sine_coeff, args_lunar_elong, args_solar_anom, args_lunar_anom, args_moon_node],
        fn [v,w,x,y,z] ->
            v * :math.pow(e, abs(x)) * sin(w * d + x * m + y * m_prime + z * f)
        end
    )
    venus =
      deg(3958 / 1000000) *
      sin(deg(119.75) + c * deg(131.849))

    jupiter =
      deg(318 / 1000000) *
      sin(deg(53.09) + c * deg(479_264.29))

    flat_earth =
      deg(1962 / 1000000) *
      sin(l - f)

    mod(l + correction + venus + jupiter + flat_earth + nutation(c), 360)
  end

  @doc since: "0.6.0"
  @spec lunar_latitude(Time.moment()) :: Astro.angle()

  def lunar_latitude(t) do
    c = julian_centuries_from_moment(t)
    l = mean_lunar_longitude(c)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    lunar_elongation = [
      0,0,0,2,2,2,2,0,2,0,2,2,2,2,2,2,2,0,4,0,0,0,
      1,0,0,0,1,0,4,4,0,4,2,2,2,2,0,2,2,2,2,4,2,2,
      0,2,1,1,0,2,1,2,0,4,4,1,4,1,4,2
    ]

    solar_anomaly = [
      0,0,0,0,0,0,0,0,0,0,-1,0,0,1,-1,-1,-1,1,0,1,
      0,1,0,1,1,1,0,0,0,0,0,0,0,0,-1,0,0,0,0,1,1,
      0,-1,-2,0,1,1,1,1,1,0,-1,1,0,-1,0,0,0,-1,-2]

    lunar_anomaly = [
      0,1,1,0,-1,-1,0,2,1,2,0,-2,1,0,-1,0,-1,-1,-1,
      0,0,-1,0,1,1,0,0,3,0,-1,1,-2,0,2,1,-2,3,2,-3,
      -1,0,0,1,0,1,1,0,0,-2,-1,1,-2,2,-2,-1,1,1,-2,
      0,0
    ]

    moon_node = [
      1,1,-1,-1,1,-1,1,1,-1,-1,-1,-1,1,-1,1,1,-1,-1,
      -1,1,3,1,1,1,-1,-1,-1,1,-1,1,-3,1,-3,-1,-1,1,
      -1,1,-1,1,1,1,1,-1,3,-1,-1,1,-1,-1,1,-1,1,-1,
      -1,-1,-1,-1,-1,1
    ]

    sine_coeff = [
      5128122, 280602, 277693, 173237, 55413, 46271, 32573,
      17198, 9266, 8822, 8216, 4324, 4200, -3359, 2463, 2211,
      2065, -1870, 1828, -1794, -1749, -1565, -1491, -1475,
      -1410, -1344, -1335, 1107, 1021, 833, 777, 671, 607,
      596, 491, -451, 439, 422, 421, -366, -351, 331, 315,
      302, -283, -229, 223, 223, -220, -220, -185, 181,
      -177, 176, 166, -164, 132, -119, 115, 107
    ]

    beta = deg(1.0 / 1000000.0) * sigma(
        [sine_coeff, lunar_elongation, solar_anomaly, lunar_anomaly, moon_node],
        fn [v, w, x, y, z] ->
            v * :math.pow(e, abs(x)) * sin(w*d + x*m + y*m_prime + z*f)
        end
    )

    venus =
      deg(175.0 / 1000000.0) *
      sin(deg(119.75) + c * deg(131.849) + f) *
      sin(deg(119.75) + c * deg(131.849) - f)

    flat_earth =
      deg(-2235.0 / 1000000.0) * sin(l) +
      deg(127.0 / 1000000.0) * sin(l - m_prime) +
      deg(-115.0 / 1000000.0) * sin(l + m_prime)

    extra = deg(382.0 / 1000000.0) * sin(deg(313.45) + (c * deg(481266.484)))

    beta + venus + flat_earth + extra
  end

  @doc since: "0.4.0"
  @spec lunar_altitude(Time.moment(), Geo.PointZ.t()) :: Astro.angle()

  def lunar_altitude(t, %Geo.PointZ{coordinates: {psi, phi, _alt}}) do
    lambda = lunar_longitude(t)
    beta = lunar_latitude(t)
    alpha = Astro.right_ascension(t, beta, lambda)
    delta = Astro.declination(t, beta, lambda)
    theta = Time.sidereal_from_moment(t)
    h = mod(theta + psi - alpha, 360.0)
    altitude = asin(sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h))
    mod(altitude + deg(180.0), 360.0) - deg(180.0)
  end

  @doc since: "0.6.0"
  @spec lunar_distance(Time.moment()) :: Astro.meters()

  def lunar_distance(t) do
    c = Time.julian_centuries_from_moment(t)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    lunar_elongation = [
      0,2,2,0,0,0,2,2,2,2,0,1,0,2,0,0,4,0,4,2,2,1,
      1,2,2,4,2,0,2,2,1,2,0,0,2,2,2,4,0,3,2,4,0,2,
      2,2,4,0,4,1,2,0,1,3,4,2,0,1,2,2
    ]

    solar_anomaly = [
      0,0,0,0,1,0,0,-1,0,-1,1,0,1,0,0,0,0,0,0,1,1,
      0,1,-1,0,0,0,1,0,-1,0,-2,1,2,-2,0,0,-1,0,0,1,
      -1,2,2,1,-1,0,0,-1,0,1,0,1,0,0,-1,2,1,0,0
    ]

    lunar_anomaly = [
      1,-1,0,2,0,0,-2,-1,1,0,-1,0,1,0,1,1,-1,3,-2,
      -1,0,-1,0,1,2,0,-3,-2,-1,-2,1,0,2,0,-1,1,0,
      -1,2,-1,1,-2,-1,-1,-2,0,1,4,0,-2,0,2,1,-2,-3,
      2,1,-1,3,-1
    ]

    moon_node = [
      0,0,0,0,0,2,0,0,0,0,0,0,0,-2,2,-2,0,0,0,0,0,
      0,0,0,0,0,0,0,2,0,0,0,0,0,0,-2,2,0,2,0,0,0,0,
      0,0,-2,0,0,0,0,-2,-2,0,0,0,0,0,0,0,-2
    ]

    cos_coeff = [
      -20905355,-3699111,-2955968,-569925,48888,-3149,
      246158,-152138,-170733,-204586,-129620,108743,
      104755,10321,0,79661,-34782,-23210,-21636,24208,
      30824,-8379,-16675,-12831,-10445,-11650,14403,
      -7003,0,10056,6322,-9884,5751,0,-4950,4130,0,
      -3958,0,3258,2616,-1897,-2117,2354,0,0,-1423,
      -1117,-1571,-1739,0,-4421,0,0,0,0,1165,0,0,
      8752
    ]

    correction = sigma(
      [cos_coeff, lunar_elongation, solar_anomaly, lunar_anomaly, moon_node],
      fn [v, w, x, y, z] ->
          v * :math.pow(e, abs(x)) * cos((w * d) + (x * m) + (y * m_prime) + (z * f))
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
      j2000() + poly(c, [
        5.09766, mean_synodic_month() * 1236.85, 0.0001437, -0.000000150, 0.00000000073
      ])

    e = poly(c, [
      1, -0.002516, -0.0000074
    ])

    solar_anomaly = poly(c, [
      2.5534, 1236.85 * 29.10535669, -0.0000014, -0.00000011
    ])

    lunar_anomaly = poly(c, [
      201.5643, 385.81693528 * 1236.85,
      0.0107582, 0.00001238, -0.000000058
    ])

    moon_argument = poly(c, [
      160.7108, 390.67050284 * 1236.85,
      -0.0016118, -0.00000227, 0.000000011
    ])

    omega = poly(c, [
      124.7746, -1.56375588 * 1236.85,
      0.0020672, 0.00000215
    ])

    e_factor = [
      0, 1, 0, 0, 1, 1, 2, 0, 0, 1, 0, 1, 1, 1, 0, 0, 0, 0,
      0, 0, 0, 0, 0, 0
    ]

    solar_coeff = [
      0, 1, 0, 0, -1, 1, 2, 0, 0, 1, 0, 1, 1, -1, 2,
      0, 3, 1, 0, 1, -1, -1, 1, 0
    ]

    lunar_coeff = [
      1, 0, 2, 0, 1, 1, 0, 1, 1, 2, 3, 0, 0, 2, 1, 2,
      0, 1, 2, 1, 1, 1, 3, 4
    ]

    moon_coeff = [
      0, 0, 0, 2, 0, 0, 0, -2, 2, 0, 0, 2, -2, 0, 0,
      -2, 0, -2, 2, 2, 2, -2, 0, 0
    ]

    sine_coeff = [
      -0.40720, 0.17241, 0.01608,
      0.01039,  0.00739, -0.00514,
      0.00208, -0.00111, -0.00057,
      0.00056, -0.00042, 0.00042,
      0.00038, -0.00024, -0.00007,
      0.00004, 0.00004, 0.00003,
      0.00003, -0.00003, 0.00003,
      -0.00002, -0.00002, 0.00002
    ]

    correction =
      deg(-0.00017) * sin(omega) +
      sigma(
        [sine_coeff, e_factor, solar_coeff, lunar_coeff, moon_coeff],
        fn [v,w,x,y,z] ->
          v * :math.pow(e, w) *
          sin((x * solar_anomaly) + (y * lunar_anomaly) + (z * moon_argument))
        end
      )

    extra =
      deg(0.000325) *
      sin(poly(c, [299.77, 132.8475848, -0.009173]))

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

  def lunar_parallax(t, location) do
    geo = lunar_altitude(t, location)
    delta = lunar_distance(t)
    alt = mt(6_378_140) / delta
    arg = alt * cos(geo)
    asin(arg)
  end

  def topocentric_lunar_altitude(t, location) do
    lunar_altitude(t, location) - lunar_parallax(t, location)
  end

  @doc false
  def mean_lunar_longitude(c) do
    c
    |> poly([218.3164477, 481267.88123421, -0.0015786, 1 / 538841.0, -1 /65194000.0])
    |> degrees()
  end

  @doc false
  def lunar_elongation(c) do
    c
    |> poly([297.8501921, 445267.1114034, -0.0018819, 1/545868, -1 / 113065000.0])
    |> degrees()
  end

  @doc false
  def solar_anomaly(c) do
    c
    |> poly([357.5291092, 35999.0502909, -0.0001536, 1 / 24490000.0])
    |> degrees()
  end

  @doc false
  def lunar_anomaly(c) do
    c
    |> poly([134.9633964, 477198.8675055, 0.0087414, 1 / 69699.0, -1 / 14712000.0])
    |> degrees()
  end

  defp solar_longitude(t) do
    c = julian_centuries_from_moment(t)
    Astro.Solar.sun_apparent_longitude_alt(c)
  end

  @doc false
  def lunar_node(t) do
    c = julian_centuries_from_moment(t)

    moon_node(c + deg(90.0))
    |> mod(180.0)
    |> Kernel.-(90.0)
  end

  @doc false
  def moon_node(c) do
    c
    |> poly([93.2720950, 483202.0175233, -0.0036539, -1 / 3526000.0, 1 / 863310000.0])
    |> degrees()
  end

end
