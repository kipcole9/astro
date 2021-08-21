defmodule Astro.Lunar do
  alias Astro.{Math, Time}

  import Astro.Math, only: [
    deg: 1, sin: 1, cos: 1, sigma: 2, mod: 2, degrees: 1,
    poly: 2, asin: 1, atan: 2, tan: 1,
    mt: 1, secs: 1, invert_angular: 4, angle: 3
  ]

  import Astro.Time, only: [
    j2000: 0, julian_centuries_from_moment: 1, sidereal_from_moment: 1
  ]

  @mean_synodic_month 29.530588861
  @months_epoch_to_j2000 24_724

  @type angle() :: number()
  @type meters() :: number()
  @type phase() :: angle()
  @type location() ::
    %{latitude: angle(), longitude: angle(), elevation: meters(), zone: Time.hours()}

  def lunar_phase(%{year: _year, month: _month, day: _day, calendar: _calendar} = date) do
    date
    |> Date.convert!(Cldr.Calendar.Gregorian)
    |> Cldr.Calendar.date_to_iso_days()
    |> lunar_phase()
  end

  def lunar_phase(t) when is_number(t) do
    phi = mod(lunar_longitude(t) - solar_longitude(t), 360)
    t0 = nth_new_moon(0)
    n = round((t - t0) / mean_synodic_month())
    phi_prime = deg(360) * mod((t - nth_new_moon(n)) / mean_synodic_month(), 1)

    if abs(phi - phi_prime) > deg(180) do
      phi_prime
    else
      phi
    end
  end

  @spec lunar_phase_at_or_before(phase(), Time.moment()) :: Time.moment()
  def lunar_phase_at_or_before(phi, t) do
    tau = t - mean_synodic_month() * (1 / deg(360.0)) * mod(lunar_phase(t) - phi, 360.0)
    a = tau - 2
    b = min(t, tau + 2)
    invert_angular(&lunar_phase/1, phi, a, b)
  end

  def lunar_phase_at_or_after(phi, t) do
    tau = t + mean_synodic_month() * (1 / deg(360.0)) * mod(phi - lunar_phase(t), 360.0)
    a = max(t, tau - 2)
    b = tau + 2
    invert_angular(&lunar_phase/1, phi, a, b)
  end

  def new() do
    deg(0)
  end

  def full() do
    deg(180)
  end

  def first_quarter() do
    deg(90)
  end

  def last_quarter() do
    deg(270)
  end

  def mean_synodic_month do
    @mean_synodic_month
  end

  @spec nth_new_moon(integer()) :: Time.moment()
  def nth_new_moon(n) do
    k = n - @months_epoch_to_j2000 # months since j2000
    c = k / 1_236.85

    approx =
      j2000() +
      poly(c, [5.09766, mean_synodic_month() * 1236.85, 0.0001437, -0.000000150, 0.00000000073])

    e =
      poly(c, [1, -0.002516, -0.0000074])

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
      0, 1, 0, 0, 1, 1, 2, 0, 0, 1, 0, 1,
      1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ]

    solar_coeff = [
      0, 1, 0, 0, -1, 1, 2, 0, 0, 1, 0, 1,
      1, -1, 2, 0, 3, 1, 0, 1, -1, -1, 1, 0
    ]

    lunar_coeff = [
      1, 0, 2, 0, 1, 1, 0, 1, 1, 2, 3, 0,
      0, 2, 1, 2, 0, 1, 2, 1, 1, 1, 3, 4
    ]

    moon_coeff = [
      0, 0, 0, 2, 0, 0, 0, -2, 2, 0, 0, 2,
      -2, 0, 0, -2, 0, -2, 2, 2, 2, -2, 0, 0
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

  def new_moon_before(t) do
    t0 = nth_new_moon(0)
    phi = lunar_phase(t)
    n = round((t-t0) / mean_synodic_month() - phi/deg(360))
    nth_new_moon(Math.final(1-n, fn k -> nth_new_moon(k) < t end))
  end

  def new_moon_at_or_after(t) do
    t0 = nth_new_moon(0)
    phi = lunar_phase(t)
    n = round((t-t0) / mean_synodic_month() - phi/deg(360))
    nth_new_moon(Math.next(n, fn k -> nth_new_moon(k) >= t end))
  end

  @spec lunar_phase(Time.moment()) :: phase()
  def lunar_longitude(t) do
    c = julian_centuries_from_moment(t)
    l = mean_lunar_longitude(c)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1, -0.002516, -0.0000074])

    args_lunar_elong = [
      0,2,2,0,0,0,2,2,2,2,0,1,0,2,0,0,4,0,4,2,2,1,
      1,2,2,4,2,0,2,2,1,2,0,0,2,2,2,4,0,3,2,4,0,2,
      2,2,4,0,4,1,2,0,1,3,4,2,0,1,2
    ]

    args_solar_anom = [
      0,0,0,0,1,0,0,-1,0,-1,1,0,1,0,0,0,0,0,0,1,1,
      0,1,-1,0,0,0,1,0,-1,0,-2,1,2,-2,0,0,-1,0,0,1,
      -1,2,2,1,-1,0,0,-1,0,1,0,1,0,0,-1,2,1,0
    ]

    args_lunar_anom = [
      1,-1,0,2,0,0,-2,-1,1,0,-1,0,1,0,1,1,-1,3,-2,
      -1,0,-1,0,1,2,0,-3,-2,-1,-2,1,0,2,0,-1,1,0,
      -1,2,-1,1,-2,-1,-1,-2,0,1,4,0,-2,0,2,1,-2,-3,
      2,1,-1,3
    ]

    args_moon_node = [
      0,0,0,0,0,2,0,0,0,0,0,0,0,-2,2,-2,0,0,0,0,0,
      0,0,0,0,0,0,0,2,0,0,0,0,0,0,-2,2,0,2,0,0,0,0,
      0,0,-2,0,0,0,0,-2,-2,0,0,0,0,0,0,0
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

  def mean_lunar_longitude(c) do
    degrees(poly(c,
      Enum.map([218.3164477, 481267.88123421, -0.0015786, 1/538841, -1/65194000], &deg/1)
    ))
  end

  def lunar_elongation(c) do
    degrees(poly(c,
      Enum.map([297.8501921, 445267.1114034, -0.0018819, 1/545868, -1/113065000], &deg/1)
    ))
  end

  def solar_anomaly(c) do
    degrees(poly(c,
      Enum.map([357.5291092, 35999.0502909, -0.0001536, 1/24490000], &deg/1)
    ))
  end

  def lunar_anomaly(c) do
    degrees(poly(c,
      Enum.map([134.9633964, 477198.8675055, 0.0087414, 1/69699, -1/14712000], &deg/1)
    ))
  end

  def moon_node(x) do
    degrees(poly(x,
      Enum.map([93.2720950, 483202.0175233, -0.0036539, -1 / 3526000.0, 1 / 863310000.0], &deg/1)
    ))
  end

  def lunar_node(d) do
    mod(moon_node(julian_centuries_from_moment(d)) + deg(90.0), deg(180.0)) + deg(90.0)
  end

  def sidereal_lunar_longitude(t) do
    mod(lunar_longitude(t) - precession(t) + sidereal_start(), 360.0)
  end

  @spec lunar_latitude(Time.moment()) :: angle()
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
      0,-1,-2,0,1,1,1,1,1,0,-1,1,0,-1,0,0,0,-1,-2
    ]

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

    beta =
      1.0 / 1000000.0 *
      sigma(
        [sine_coeff, lunar_elongation, solar_anomaly, lunar_anomaly, moon_node],
        fn [v,w,x,y,z] -> v * :math.pow(e, abs(x)) * sin(w * d + x * m + y * m_prime + z * f) end
      )

    venus =
      deg(175.0 / 1000000.0) *
      sin(deg(119.75) + c*deg(131.849) + f) *
      sin(deg(119.75) + c*deg(131.849) - f)

    flat_earth =
      deg(-2235.0 / 1000000.0) * sin(l) +
      deg(127.0 / 10000000.0) * sin(l - m_prime) +
      deg(-115.0 / 1000000.0) * sin(l + m_prime)

    extra =
      deg(382.0 / 1000000.0) *
      sin(deg(313.45) +
      c * deg(481266.484))

    beta + venus + flat_earth + extra
  end

  @spec lunar_altitude(Time.moment(), location()) :: angle()
  def lunar_altitude(t, %{latitude: phi, longitude: psi}) do
    lambda = lunar_longitude(t)
    beta = lunar_latitude(t)
    alpha = right_ascension(t, beta, lambda)
    delta = declination(t, beta, lambda)
    theta = sidereal_from_moment(t)
    h = mod(theta + psi - alpha, 360)
    altitude = asin(sin(phi) * sin(delta) + cos(phi) * cos(delta) * cos(h))
    mod(altitude + deg(180), 360) - deg(180)
  end

  @spec lunar_distance(Time.moment()) :: meters()
  def lunar_distance(t) do
    c = julian_centuries_from_moment(t)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1, -0.002516, -0.0000074])

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

    correction =
      sigma(
        [cos_coeff, lunar_elongation, solar_anomaly, lunar_anomaly, moon_node],
        fn [v,w,x,y,z] -> v * :math.pow(e, abs(x)) * cos(w*d + x*m + y*m_prime + z*f) end
      )

    mt(385_000_560) + correction
  end

  def lunar_parallax(t, locale) do
    geo = lunar_altitude(t, locale)
    delta = lunar_distance(t)
    alt = mt(6738140)/delta
    arg = alt * cos(geo)
    asin(arg)
  end

  def topocentric_lunar_altitude(t, locale) do
    lunar_altitude(t, locale) - lunar_parallax(t, locale)
  end

  @spec nutation(Time.moment()) :: angle()
  def nutation(t) do
    c = julian_centuries_from_moment(t)
    a = poly(c, Enum.map([124.90, -1934.134, 0.002063], &deg/1))
    b = poly(c, Enum.map([201.11, 72001.5377, 0.00057], &deg/1))
    deg(-0.004778) * sin(a) + deg(-0.0003667) * sin(b)
  end

  def precession(t) do
    c = julian_centuries_from_moment(t)
    eta = mod(poly(c, [secs(47.0029), secs(-0.03302), secs(0.000060)]), 360)
    p1 = mod(poly(c, [deg(174.876384), secs(-869.8089), secs(0.03536)]), 360)
    p2 = mod(poly(c, [secs(5029.0966), secs(1.11113), secs(0.000006)]), 360)
    a = cos(eta) * sin(p1)
    b = cos(p1)
    arg = atan(a, b)
    mod(p2+ p1 - arg, 360)
  end

  def sidereal_start() do
    deg(156.13605090692624)
  end

  # This should be replacable with the functions in Astro.Solar but
  # need to work out which one is is: mean, apparent or true
  @spec solar_longitude(Time.moment()) :: Time.season()
  def solar_longitude(t) do
    c = julian_centuries_from_moment(t)

    coefficients = [
      403406, 195207, 119433, 112392, 3891, 2819, 1721,
      660, 350, 334, 314, 268, 242, 234, 158, 132, 129, 114,
      99, 93, 86, 78, 72, 68, 64, 46, 38, 37, 32, 29, 28, 27, 27,
      25, 24, 21, 21, 20, 18, 17, 14, 13, 13, 13, 12, 10, 10, 10,
      10
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

    mod(lambda + aberration(t) + nutation(t), 360)
  end

  @spec aberration(Time.moment()) :: angle()
  def aberration(t) do
    c = julian_centuries_from_moment(t)
    deg(0.0000974) * cos(deg(177.63) + deg(35999.01848) * c) - deg(0.005575)
  end

  @spec declination(Time.moment(), angle(), angle()) :: angle()
  def declination(t, beta, lambda) do
    epsilon = obliquity(t)
    asin(sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda))
  end

  def obliquity(t) do
    c = julian_centuries_from_moment(t)

    angle(23, 26, 21.448) +
    poly(c, [
      angle(0,0,-46.8150),
      angle(0,0,-0.00059),
      angle(0,0,0.001813)
    ])
  end

  @spec right_ascension(Time.moment(), angle(), angle()) :: angle()
  def right_ascension(t, beta, lambda) do
    epsilon = obliquity(t)
    atan(
      sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon),
      cos(lambda)
    )
  end

end
