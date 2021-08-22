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

  @type angle() :: number()
  @type meters() :: number()
  @type phase() :: angle()
  @type location() ::
    %{latitude: angle(), longitude: angle(), elevation: meters(), zone: Time.hours()}

  @mean_synodic_month 29.530588861
  @months_epoch_to_j2000 24_724.0
  @average_distance_earth_to_moon 385_000_560.0

  def new_moon_before(%{year: _year, month: _month, day: _day, calendar: calendar} = date) do
    date
    |> Cldr.Calendar.date_to_iso_days()
    |> new_moon_before()
    |> datetime_from_iso_days()
    |> DateTime.convert!(calendar)
  end

  def new_moon_before(t) when is_number(t) do
    t0 = nth_new_moon(0.0)
    phi = lunar_phase(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360.0))
    nth_new_moon(Math.final(1.0 - n, &(nth_new_moon(&1) < t)))
  end

  def new_moon_at_or_after(%{year: _year, month: _month, day: _day, calendar: calendar} = date) do
    date
    |> Cldr.Calendar.date_to_iso_days()
    |> new_moon_at_or_after()
    |> datetime_from_iso_days()
    |> DateTime.convert!(calendar)
  end

  def new_moon_at_or_after(t) when is_number(t) do
    t0 = nth_new_moon(0.0)
    phi = lunar_phase(t)
    n = round((t - t0) / mean_synodic_month() - phi / deg(360.0))
    nth_new_moon(Math.next(n, &(nth_new_moon(&1) >= t)))
  end

  def datetime_from_iso_days(t) do
    days = trunc(t)
    fraction = Float.ratio(t - days)

    {year, month, day, hour, minute, second, fraction} =
      Cldr.Calendar.Gregorian.naive_datetime_from_iso_days({days, fraction})

    {:ok, date} = Elixir.Date.new(year, month, day)
    {:ok, time} = Elixir.Time.new(hour, minute, second, fraction)
    DateTime.new!(date, time)
  end

  @doc """
  Returns the lunar phase for a date in
  degrees between `0.0` and `360.0`.

  """
  def lunar_phase(%{year: _year, month: _month, day: _day, calendar: _calendar} = date) do
    date
    |> Cldr.Calendar.date_to_iso_days()
    |> lunar_phase()
  end

  def lunar_phase(t) when is_number(t) do
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

  @spec lunar_phase_at_or_before(phase(), Time.moment()) :: Time.moment()
  def lunar_phase_at_or_before(phi, t) do
    tau = t - mean_synodic_month() * (1.0 / deg(360.0)) * mod(lunar_phase(t) - phi, 360.0)
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
    deg(0.0)
  end

  def full() do
    deg(180.0)
  end

  def first_quarter() do
    deg(90.0)
  end

  def last_quarter() do
    deg(270.0)
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

  @spec lunar_phase(Time.moment()) :: phase()
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
      Enum.map([357.5291092, 35999.0502909, -0.0001536, 1.0 / 24490000.0], &deg/1)
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
      0.0,0.0,0.0,2.0,2.0,2.0,2.0,0.0,2.0,0.0,2.0,2.0,2.0,2.0,2.0,2.0,2.0,0.0,4.0,0.0,0.0,0.0,
      1.0,0.0,0.0,0.0,1.0,0.0,4.0,4.0,0.0,4.0,2.0,2.0,2.0,2.0,0.0,2.0,2.0,2.0,2.0,4.0,2.0,2.0,
      0.0,2.0,1.0,1.0,0.0,2.0,1.0,2.0,0.0,4.0,4.0,1.0,4.0,1.0,4.0,2.0
    ]

    solar_anomaly = [
      0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-1.0,0.0,0.0,1.0,-1.0,-1.0,-1.0,1.0,0.0,1.0,
      0.0,1.0,0.0,1.0,1.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-1.0,0.0,0.0,0.0,0.0,1.0,1.0,
      0.0,-1.0,-2.0,0.0,1.0,1.0,1.0,1.0,1.0,0.0,-1.0,1.0,0.0,-1.0,0.0,0.0,0.0,-1.0,-2.0
    ]

    lunar_anomaly = [
      0.0,1.0,1.0,0.0,-1.0,-1.0,0.0,2.0,1.0,2.0,0.0,-2.0,1.0,0.0,-1.0,0.0,-1.0,-1.0,-1.0,
      0.0,0.0,-1.0,0.0,1.0,1.0,0.0,0.0,3.0,0.0,-1.0,1.0,-2.0,0.0,2.0,1.0,-2.0,3.0,2.0,-3.0,
      -1.0,0.0,0.0,1.0,0.0,1.0,1.0,0.0,0.0,-2.0,-1.0,1.0,-2.0,2.0,-2.0,-1.0,1.0,1.0,-2.0,
      0.0,0.0
    ]

    moon_node = [
      1.0,1.0,-1.0,-1.0,1.0,-1.0,1.0,1.0,-1.0,-1.0,-1.0,-1.0,1.0,-1.0,1.0,1.0,-1.0,-1.0,
      -1.0,1.0,3.0,1.0,1.0,1.0,-1.0,-1.0,-1.0,1.0,-1.0,1.0,-3.0,1.0,-3.0,-1.0,-1.0,1.0,
      -1.0,1.0,-1.0,1.0,1.0,1.0,1.0,-1.0,3.0,-1.0,-1.0,1.0,-1.0,-1.0,1.0,-1.0,1.0,-1.0,
      -1.0,-1.0,-1.0,-1.0,-1.0,1.0
    ]

    sine_coeff = [
      5128122.0, 280602.0, 277693.0, 173237.0, 55413.0, 46271.0, 32573.0,
      17198.0, 9266.0, 8822.0, 8216.0, 4324.0, 4200.0, -3359.0, 2463.0, 2211.0,
      2065.0, -1870.0, 1828.0, -1794.0, -1749.0, -1565.0, -1491.0, -1475.0,
      -1410.0, -1344.0, -1335.0, 1107.0, 1021.0, 833.0, 777.0, 671.0, 607.0,
      596.0, 491.0, -451.0, 439.0, 422.0, 421.0, -366.0, -351.0, 331.0, 315.0,
      302.0, -283.0, -229.0, 223.0, 223.0, -220.0, -220.0, -185.0, 181.0,
      -177.0, 176.0, 166.0, -164.0, 132.0, -119.0, 115.0, 107.0
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
    mod(altitude + deg(180.0), 360.0) - deg(180.0)
  end

  @spec lunar_distance(Time.moment()) :: meters()
  def lunar_distance(t) do
    c = julian_centuries_from_moment(t)
    d = lunar_elongation(c)
    m = solar_anomaly(c)
    m_prime = lunar_anomaly(c)
    f = moon_node(c)
    e = poly(c, [1.0, -0.002516, -0.0000074])

    lunar_elongation = [
      0.0,2.0,2.0,0.0,0.0,0.0,2.0,2.0,2.0,2.0,0.0,1.0,0.0,2.0,0.0,0.0,4.0,0.0,4.0,2.0,2.0,1.0,
      1.0,2.0,2.0,4.0,2.0,0.0,2.0,2.0,1.0,2.0,0.0,0.0,2.0,2.0,2.0,4.0,0.0,3.0,2.0,4.0,0.0,2.0,
      2.0,2.0,4.0,0.0,4.0,1.0,2.0,0.0,1.0,3.0,4.0,2.0,0.0,1.0,2.0,2.0
    ]

    solar_anomaly = [
      0.0,0.0,0.0,0.0,1.0,0.0,0.0,-1.0,0.0,-1.0,1.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,1.0,
      0.0,1.0,-1.0,0.0,0.0,0.0,1.0,0.0,-1.0,0.0,-2.0,1.0,2.0,-2.0,0.0,0.0,-1.0,0.0,0.0,1.0,
      -1.0,2.0,2.0,1.0,-1.0,0.0,0.0,-1.0,0.0,1.0,0.0,1.0,0.0,0.0,-1.0,2.0,1.0,0.0,0.0
    ]

    lunar_anomaly = [
      1.0,-1.0,0.0,2.0,0.0,0.0,-2.0,-1.0,1.0,0.0,-1.0,0.0,1.0,0.0,1.0,1.0,-1.0,3.0,-2.0,
      -1.0,0.0,-1.0,0.0,1.0,2.0,0.0,-3.0,-2.0,-1.0,-2.0,1.0,0.0,2.0,0.0,-1.0,1.0,0.0,
      -1.0,2.0,-1.0,1.0,-2.0,-1.0,-1.0,-2.0,0.0,1.0,4.0,0.0,-2.0,0.0,2.0,1.0,-2.0,-3.0,
      2.0,1.0,-1.0,3.0,-1.0
    ]

    moon_node = [
      0.0,0.0,0.0,0.0,0.0,2.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-2.0,2.0,-2.0,0.0,0.0,0.0,0.0,0.0,
      0.0,0.0,0.0,0.0,0.0,0.0,0.0,2.0,0.0,0.0,0.0,0.0,0.0,0.0,-2.0,2.0,0.0,2.0,0.0,0.0,0.0,0.0,
      0.0,0.0,-2.0,0.0,0.0,0.0,0.0,-2.0,-2.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,-2.0
    ]

    cos_coeff = [
      -20905355.0,-3699111.0,-2955968.0,-569925.0,48888.0,-3149.0,
      246158.0,-152138.0,-170733.0,-204586.0,-129620.0,108743.0,
      104755.0,10321.0,0.0,79661.0,-34782.0,-23210.0,-21636.0,24208.0,
      30824.0,-8379.0,-16675.0,-12831.0,-10445.0,-11650.0,14403.0,
      -7003.0,0.0,10056.0,6322.0,-9884.0,5751.0,0.0,-4950.0,4130.0,0.0,
      -3958.0,0.0,3258.0,2616.0,-1897.0,-2117.0,2354.0,0.0,0.0,-1423.0,
      -1117.0,-1571.0,-1739.0,0.0,-4421.0,0.0,0.0,0.0,0.0,1165.0,0.0,0.0,
      8752.0
    ]

    correction =
      sigma(
        [cos_coeff, lunar_elongation, solar_anomaly, lunar_anomaly, moon_node],
        fn [v,w,x,y,z] -> v * :math.pow(e, abs(x)) * cos(w * d + x * m + y * m_prime + z * f) end
      )

    mt(@average_distance_earth_to_moon) + correction
  end

  def lunar_parallax(t, locale) do
    geo = lunar_altitude(t, locale)
    delta = lunar_distance(t)
    alt = mt(6738140.0) / delta
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
    eta = mod(poly(c, [secs(47.0029), secs(-0.03302), secs(0.000060)]), 360.0)
    p1 = mod(poly(c, [deg(174.876384), secs(-869.8089), secs(0.03536)]), 360.0)
    p2 = mod(poly(c, [secs(5029.0966), secs(1.11113), secs(0.000006)]), 360.0)
    a = cos(eta) * sin(p1)
    b = cos(p1)
    arg = atan(a, b)
    mod(p2 + p1 - arg, 360.0)
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
