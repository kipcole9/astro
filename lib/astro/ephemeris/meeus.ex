defmodule Astro.Ephemeris.Meeus do
  @moduledoc """
  Computes the apparent geocentric positions of the Sun and the Moon from
  analytical series, for moments the loaded JPL ephemeris does not cover.

  `Astro.Ephemeris` answers from the JPL kernel where it can and from this
  module where it cannot, so its callers receive a position for any date.
  The positions are in the frame `Astro.Ephemeris` uses: the true equator
  and equinox of date, with distances in kilometres.

  ## The Sun

  The apparent ecliptic longitude is the 49-term periodic series of
  Bretagnon and Simon, as given in *Calendrical Calculations*, corrected
  for aberration and for the nutation in longitude of
  `Astro.Earth.nutation/1`. Against the JPL DE440s ephemeris over
  1900–2100 it agrees to about 1″ RMS, and to 3.3″ at most. The latitude
  is taken as zero (the Sun's is under 1.2″) and the distance comes from
  the Keplerian ellipse of Meeus, *Astronomical Algorithms*, chapter 25.

  ## Accuracy far from the present

  The series are fitted to modern observations. They stay well behaved
  for thousands of years either side of J2000, but their error grows with
  distance from it, and ΔT, whose uncertainty reaches hours by −2000, then
  dominates the time of any event computed from them.

  """

  alias Astro.{Earth, Math, Time}

  # Periodic terms of the Sun's longitude (Bretagnon and Simon, via
  # Calendrical Calculations). Each row: coefficient, addend (degrees),
  # multiplier (degrees per Julian century).
  @sun_longitude_terms """
                       403406  270.54861      0.9287892
                       195207  340.19128  35999.1376958
                       119433   63.91854  35999.4089666
                       112392  331.26220  35998.7287385
                       3891  317.843    71998.20261
                       2819   86.631    71998.4403
                       1721  240.052    36000.35726
                       660  310.26     71997.4812
                       350  247.23     32964.4678
                       334  260.87       -19.4410
                       314  297.82    445267.1117
                       268  343.14     45036.8840
                       242  166.79         3.1008
                       234   81.53     22518.4434
                       158    3.50       -19.9739
                       132  132.75     65928.9345
                       129  182.95      9038.0293
                       114  162.03      3034.7684
                       99   29.8      33718.148
                       93  266.4       3034.448
                       86  249.2      -2280.773
                       78  157.6      29929.992
                       72  257.8      31556.493
                       68  185.1        149.588
                       64   69.9       9037.750
                       46    8.0     107997.405
                       38  197.1      -4444.176
                       37  250.4        151.771
                       32   65.3      67555.316
                       29  162.7      31556.080
                       28  341.5      -4561.540
                       27  291.6     107996.706
                       27   98.5       1221.655
                       25  146.7      62894.167
                       24  110.0      31437.369
                       21    5.2      14578.298
                       21  342.6     -31931.757
                       20  230.9      34777.243
                       18  256.1       1221.999
                       17   45.3      62894.511
                       14  242.9      -4442.039
                       13  115.2     107997.909
                       13  151.8        119.066
                       13  285.3      16859.071
                       12   53.3         -4.578
                       10  126.6      26895.292
                       10  205.7        -39.127
                       10   85.9      12297.536
                       10  146.1      90073.778
                       """
                       |> String.split("\n", trim: true)
                       |> Enum.map(fn line ->
                         [coefficient, addend, multiplier] =
                           line
                           |> String.split()
                           |> Enum.map(fn field ->
                             {value, ""} = Float.parse(field)
                             value
                           end)

                         {coefficient, addend, multiplier}
                       end)

  @radians_per_degree :math.pi() / 180.0

  @doc """
  Returns the Sun's apparent geocentric ecliptic position for a dynamical
  time.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{:ok, {longitude, latitude, distance}}` where `longitude` is in
    degrees in the range 0 to 360, `latitude` is `0.0` and `distance` is
    in kilometres.

  ### Examples

      iex> {:ok, {longitude, latitude, distance}} = Astro.Ephemeris.Meeus.sun_ecliptic_position_dt(0.0)
      iex> {Float.round(longitude, 4), latitude, round(distance)}
      {280.3683, 0.0, 147100848}

  """
  @doc since: "2.10.0"
  @spec sun_ecliptic_position_dt(float()) :: {:ok, {float(), float(), float()}}
  def sun_ecliptic_position_dt(dynamical_time) do
    {longitude, distance, _true_obliquity} = sun_apparent(dynamical_time)
    {:ok, {longitude, 0.0, distance}}
  end

  @doc """
  Returns the Sun's apparent geocentric equatorial position for a dynamical
  time.

  ### Arguments

  * `dynamical_time` is TDB seconds past J2000.0.

  ### Returns

  * `{:ok, {right_ascension, declination, distance}}` where
    `right_ascension` is in degrees in the range 0 to 360, `declination`
    is in degrees and `distance` is in kilometres.

  ### Examples

      iex> {:ok, {right_ascension, declination, distance}} = Astro.Ephemeris.Meeus.sun_position_dt(0.0)
      iex> {Float.round(right_ascension, 4), Float.round(declination, 4), round(distance)}
      {281.2777, -23.0327, 147100848}

  """
  @doc since: "2.10.0"
  @spec sun_position_dt(float()) :: {:ok, {float(), float(), float()}}
  def sun_position_dt(dynamical_time) do
    {longitude, distance, true_obliquity} = sun_apparent(dynamical_time)
    {right_ascension, declination} = ecliptic_to_equatorial(longitude, 0.0, true_obliquity)
    {:ok, {right_ascension, declination, distance}}
  end

  # The Sun's apparent longitude in degrees, its distance in kilometres and
  # the true obliquity of the ecliptic in radians, sharing one evaluation of
  # the nutation.
  defp sun_apparent(dynamical_time) do
    julian_centuries = Time.julian_centuries_from_dynamical_time(dynamical_time)
    {delta_psi, delta_epsilon, mean_obliquity} = Earth.nutation(julian_centuries)

    apparent_longitude =
      sun_geometric_longitude(julian_centuries) + sun_aberration(julian_centuries) +
        delta_psi / @radians_per_degree

    longitude = Math.mod(apparent_longitude, 360.0)
    {longitude, sun_distance(julian_centuries), mean_obliquity + delta_epsilon}
  end

  # Meeus, Astronomical Algorithms, equations 13.3 and 13.4, with the
  # longitude and latitude in degrees and the obliquity in radians.
  defp ecliptic_to_equatorial(longitude, latitude, obliquity) do
    lambda = longitude * @radians_per_degree
    beta = latitude * @radians_per_degree

    right_ascension =
      :math.atan2(
        :math.sin(lambda) * :math.cos(obliquity) - :math.tan(beta) * :math.sin(obliquity),
        :math.cos(lambda)
      ) / @radians_per_degree

    declination =
      :math.asin(
        :math.sin(beta) * :math.cos(obliquity) +
          :math.cos(beta) * :math.sin(obliquity) * :math.sin(lambda)
      ) / @radians_per_degree

    {Math.mod(right_ascension, 360.0), declination}
  end

  # The Sun's true geometric longitude referred to the mean equinox of date.
  defp sun_geometric_longitude(julian_centuries) do
    periodic =
      Enum.reduce(@sun_longitude_terms, 0.0, fn {coefficient, addend, multiplier}, sum ->
        sum +
          coefficient * :math.sin((addend + multiplier * julian_centuries) * @radians_per_degree)
      end)

    282.7771834 + 36_000.76953744 * julian_centuries + 0.000005729577951308232 * periodic
  end

  defp sun_aberration(julian_centuries) do
    0.0000974 * :math.cos((177.63 + 35_999.01848 * julian_centuries) * @radians_per_degree) -
      0.005575
  end

  # Meeus, Astronomical Algorithms, equations 25.2 to 25.5: the radius vector
  # of the Keplerian ellipse, in kilometres.
  defp sun_distance(julian_centuries) do
    mean_anomaly =
      (357.52911 + julian_centuries * (35_999.05029 - 0.0001537 * julian_centuries)) *
        @radians_per_degree

    eccentricity =
      0.016708634 - julian_centuries * (0.000042037 + 0.0000001267 * julian_centuries)

    centre =
      (:math.sin(mean_anomaly) *
         (1.914602 - julian_centuries * (0.004817 + 0.000014 * julian_centuries)) +
         :math.sin(2 * mean_anomaly) * (0.019993 - 0.000101 * julian_centuries) +
         :math.sin(3 * mean_anomaly) * 0.000289) * @radians_per_degree

    true_anomaly = mean_anomaly + centre

    radius =
      1.000001018 * (1.0 - eccentricity * eccentricity) /
        (1.0 + eccentricity * :math.cos(true_anomaly))

    Math.au_to_km(radius)
  end
end
