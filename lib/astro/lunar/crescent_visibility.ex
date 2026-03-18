defmodule Astro.Lunar.CrescentVisibility do
  @moduledoc """
  Implements three criteria for predicting the visibility of the new
  crescent moon: Yallop (1997), Odeh (2006), and Schaefer (1988/2000).

  All three functions accept a normalized location and a moment (midnight
  UTC for the date of interest) and return `{:ok, visibility}` where
  `visibility` is one of `:A`, `:B`, `:C`, `:D`, or `:E`.

  ## Yallop (1997)

  An empirical single-parameter criterion based on the **geocentric**
  arc of vision (ARCV) and crescent width (W). The q-value is the
  scaled residual between the observed ARCV and a cubic polynomial
  fit to Bruin's (1977) visibility curves:

      ARCV' = 11.8371 − 6.3226·W + 0.7319·W² − 0.1018·W³
      q = (ARCV − ARCV') / 10

  ## Odeh (2006)

  An updated empirical criterion using the same polynomial family as
  Yallop but fitted to 737 observations (vs Yallop's 295). Uses
  **topocentric** ARCV and a different intercept:

      ARCV' = 7.1651 − 6.3226·W + 0.7319·W² − 0.1018·W³
      V = ARCV − ARCV'

  Odeh also enforces a Danjon limit of 6.4° (ARCL < 6.4° → not visible).

  ## Schaefer (1988/2000)

  A physics-based model that computes the contrast between the crescent
  moon's brightness and the twilight sky brightness, then compares
  against the human contrast detection threshold (Blackwell 1946). The
  best observation time is found by scanning from sunset to moonset.

  The visibility parameter is:

      Rs = log₁₀(contrast / threshold)

  where Rs > 0 means the crescent is detectable. This implementation
  uses the V-band sky brightness model from Schaefer (1993) with
  default atmospheric parameters suitable for a sea-level site with
  clean air.

  ## Visibility categories

  | Code | Meaning                           |
  |------|-----------------------------------|
  | `:A` | Visible to the naked eye          |
  | `:B` | Visible with optical aid          |
  | `:C` | May need optical aid              |
  | `:D` | Not visible with optical aid      |
  | `:E` | Not visible                       |

  ## References

  * Yallop, B. D. (1997). *A Method for Predicting the First Sighting
    of the New Crescent Moon*. NAO Technical Note No. 69.

  * Odeh, M. Sh. (2004). *New Criterion for Lunar Crescent Visibility*.
    Experimental Astronomy, 18, 39–64.

  * Schaefer, B. E. (1993). *Astronomy and the Limits of Vision*.
    Vistas in Astronomy, 36, 311–361.

  * Schaefer, B. E. (2000). *New Methods and Techniques for Historical
    Astronomy and Archaeoastronomy*. Archaeoastronomy, XV, 121–136.

  """

  alias Astro.{Time, Lunar, Solar}

  import Astro.Math,
    only: [
      sin: 1,
      cos: 1,
      mod: 2,
      to_degrees: 1
    ]

  @type visibility :: :A | :B | :C | :D | :E

  # ── Shared constants ──────────────────────────────────────────────────────────

  # Polynomial coefficients shared by Yallop and Odeh (W in arcminutes)
  @w1 -6.3226
  @w2 0.7319
  @w3 -0.1018

  # ── Yallop constants ──────────────────────────────────────────────────────────

  @yallop_constant 11.8371
  @yallop_q_a 0.216
  @yallop_q_b -0.014
  @yallop_q_c -0.160
  @yallop_q_d -0.232

  # ── Odeh constants ────────────────────────────────────────────────────────────

  @odeh_constant 7.1651
  @odeh_v_a 5.65
  @odeh_v_b 2.0
  @odeh_v_c 0.0
  @odeh_danjon_limit 6.4

  # ── Schaefer constants (V-band) ───────────────────────────────────────────────

  # Default V-band zenith extinction coefficient (clean sea-level site)
  @default_extinction 0.172

  # Solar V-band magnitude and reference zero-point
  @ms_v -26.74
  @m0_v -11.05

  # Twilight zero-point constant
  @twilight_zp 32.5

  # Nanolambert conversion factor (erg/s/cm^2/sr/Hz per nanolambert)
  @nl_factor 1.11e-15

  # Dark sky baseline brightness (V-band, erg/s/cm^2/sr/Hz)
  @dark_sky_b0 1.0e-13

  # Schaefer Rs thresholds for mapping to visibility categories
  @schaefer_rs_a 0.5
  @schaefer_rs_b 0.25
  @schaefer_rs_c 0.0
  @schaefer_rs_d -0.5

  # Scan interval for Schaefer best-time search (fraction of day ≈ 3 minutes)
  @scan_step 3.0 / 1440.0

  # ════════════════════════════════════════════════════════════════════════════════
  # Yallop (1997)
  # ════════════════════════════════════════════════════════════════════════════════

  @doc """
  Computes the Yallop (1997) visibility criterion for the new crescent moon.

  Uses geocentric ARCV and the polynomial fit to Bruin's visibility curves.

  ### Arguments

  * `location` is a `t:Geo.PointZ.t/0` struct (already normalized).

  * `moment` is a `t:Astro.Time.moment/0` representing the date.

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of `:A`, `:B`, `:C`, `:D`, or `:E`.

  * `{:error, :no_sunset}` if sunset cannot be computed.

  """
  @spec yallop_new_visible_crescent(Geo.PointZ.t(), Time.moment()) ::
          {:ok, visibility()} | {:error, atom()}

  def yallop_new_visible_crescent(location, moment) do
    with_best_time(location, moment, fn best_time ->
      {sun_alt, moon_alt, _arcl, w} = geocentric_parameters(best_time, location)

      arcv = moon_alt - sun_alt
      arcv_prime = @yallop_constant + @w1 * w + @w2 * w * w + @w3 * w * w * w
      q = (arcv - arcv_prime) / 10.0

      {:ok, classify_yallop(q)}
    end)
  end

  defp classify_yallop(q) when q >= @yallop_q_a, do: :A
  defp classify_yallop(q) when q >= @yallop_q_b, do: :B
  defp classify_yallop(q) when q >= @yallop_q_c, do: :C
  defp classify_yallop(q) when q >= @yallop_q_d, do: :D
  defp classify_yallop(_q), do: :E

  # ════════════════════════════════════════════════════════════════════════════════
  # Odeh (2006)
  # ════════════════════════════════════════════════════════════════════════════════

  @doc """
  Computes the Odeh (2006) visibility criterion for the new crescent moon.

  Uses topocentric ARCV, the same polynomial family as Yallop with an
  updated intercept (7.1651), and enforces a Danjon limit of 6.4°.

  ### Arguments

  * `location` is a `t:Geo.PointZ.t/0` struct (already normalized).

  * `moment` is a `t:Astro.Time.moment/0` representing the date.

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of `:A`, `:B`, `:C`, `:D`, or `:E`.

  * `{:error, :no_sunset}` if sunset cannot be computed.

  """
  @spec odeh_new_visible_crescent(Geo.PointZ.t(), Time.moment()) ::
          {:ok, visibility()} | {:error, atom()}

  def odeh_new_visible_crescent(location, moment) do
    with_best_time(location, moment, fn best_time ->
      {sun_alt, _moon_alt_geo, arcl, w} = geocentric_parameters(best_time, location)

      # Odeh uses topocentric moon altitude
      moon_alt_topo = Lunar.topocentric_lunar_altitude(best_time, location)
      arcv = moon_alt_topo - sun_alt

      if arcl < @odeh_danjon_limit do
        {:ok, :E}
      else
        arcv_prime = @odeh_constant + @w1 * w + @w2 * w * w + @w3 * w * w * w
        v = arcv - arcv_prime
        {:ok, classify_odeh(v)}
      end
    end)
  end

  defp classify_odeh(v) when v >= @odeh_v_a, do: :A
  defp classify_odeh(v) when v >= @odeh_v_b, do: :B
  defp classify_odeh(v) when v >= @odeh_v_c, do: :C
  defp classify_odeh(_v), do: :D

  # ════════════════════════════════════════════════════════════════════════════════
  # Schaefer (1988/2000)
  # ════════════════════════════════════════════════════════════════════════════════

  @doc """
  Computes the Schaefer (1988/2000) visibility criterion for the new
  crescent moon.

  This physics-based model computes the contrast between the crescent
  moon's brightness and the twilight sky brightness, comparing against
  the human contrast detection threshold. The best observation time is
  found by scanning from sunset to moonset.

  ### Arguments

  * `location` is a `t:Geo.PointZ.t/0` struct (already normalized).

  * `moment` is a `t:Astro.Time.moment/0` representing the date.

  * `options` is a keyword list of optional atmospheric parameters:

    * `:extinction` — V-band zenith extinction coefficient. Default `0.172`
      (clean sea-level site). Typical values: 0.12 (high mountain),
      0.17 (sea level), 0.25 (hazy).

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of `:A`, `:B`, `:C`, `:D`, or `:E`.

  * `{:error, :no_sunset}` if sunset cannot be computed.

  """
  @spec schaefer_new_visible_crescent(Geo.PointZ.t(), Time.moment(), keyword()) ::
          {:ok, visibility()} | {:error, atom()}

  def schaefer_new_visible_crescent(location, moment, options \\ []) do
    k = Keyword.get(options, :extinction, @default_extinction)

    sunset_result = Solar.SunRiseSet.sunset(location, moment, time_zone: :utc)
    moonset_result = Lunar.MoonRiseSet.moonset(location, moment, time_zone: :utc)

    case {sunset_result, moonset_result} do
      {{:ok, sunset_dt}, {:ok, moonset_dt}} ->
        sunset_moment = Time.date_time_to_moment(sunset_dt)
        moonset_moment = Time.date_time_to_moment(moonset_dt)

        if moonset_moment <= sunset_moment do
          {:ok, :E}
        else
          rs = scan_best_rs(sunset_moment, moonset_moment, location, k)
          {:ok, classify_schaefer(rs)}
        end

      {{:ok, sunset_dt}, {:error, _}} ->
        sunset_moment = Time.date_time_to_moment(sunset_dt)
        end_moment = sunset_moment + 90.0 / 1440.0
        rs = scan_best_rs(sunset_moment, end_moment, location, k)
        {:ok, classify_schaefer(rs)}

      {{:error, _}, _} ->
        {:error, :no_sunset}
    end
  end

  # Scan from sunset to moonset in steps, finding the maximum Rs.
  defp scan_best_rs(start_moment, end_moment, location, k) do
    Stream.iterate(start_moment, &(&1 + @scan_step))
    |> Enum.take_while(&(&1 <= end_moment))
    |> Enum.reduce(-99.0, fn t, best_rs ->
      rs = compute_rs(t, location, k)
      max(rs, best_rs)
    end)
  end

  # Compute the Schaefer visibility parameter Rs at a given moment.
  #
  # Rs = (limiting_magnitude - apparent_magnitude) / 2.5
  # Rs > 0 means the crescent is detectable.
  defp compute_rs(moment, location, k) do
    {sun_ra, sun_dec, _} = Solar.solar_position(moment)
    {moon_ra, moon_dec, _} = Lunar.lunar_position(moment)

    {_sun_az, sun_alt} = azimuth_altitude(sun_ra, sun_dec, moment, location)
    {_moon_az, moon_alt} = azimuth_altitude(moon_ra, moon_dec, moment, location)

    # Moon must be above horizon, sun must be below
    if moon_alt <= 0.0 or sun_alt >= 0.0 do
      -99.0
    else
      # Geocentric elongation (ARCL)
      cos_arcl =
        sin(sun_dec) * sin(moon_dec) +
          cos(sun_dec) * cos(moon_dec) * cos(sun_ra - moon_ra)

      arcl = :math.acos(clamp(cos_arcl, -1.0, 1.0)) |> to_degrees()

      # Phase angle (supplement of elongation for waxing crescent)
      phase_angle = 180.0 - arcl

      # Moon zenith distance and air mass
      z_moon = 90.0 - moon_alt
      z_moon_rad = z_moon * :math.pi() / 180.0
      x_moon = air_mass(z_moon_rad)

      # ── Moon apparent V-band magnitude ─────────────────────────────────
      # Schaefer (1988) formula for total lunar apparent magnitude
      m_moon = -12.73 + 0.026 * abs(phase_angle) + 4.0e-9 * :math.pow(phase_angle, 4)
      dm = k * x_moon
      m_apparent = m_moon + dm

      # ── Sky brightness at moon position (nanolamberts) ─────────────────
      b_nl = twilight_brightness_nl(sun_alt, z_moon, z_moon_rad, x_moon, k)

      # ── Limiting magnitude from Blackwell threshold ────────────────────
      m_limit = limiting_magnitude(b_nl, dm)

      # ── Visibility parameter ───────────────────────────────────────────
      (m_limit - m_apparent) / 2.5
    end
  end

  # Twilight sky brightness in nanolamberts at a point with the given
  # zenith distance, when the sun is at altitude sun_alt (negative).
  #
  # Based on Schaefer (1993) V-band twilight model.
  defp twilight_brightness_nl(sun_alt, z_moon, z_moon_rad, x_moon, k) do
    # Sun depression (positive value, degrees below horizon)
    depression = -sun_alt

    # Dark night sky component (nanolamberts)
    van_rhijn =
      0.4 +
        0.6 / :math.sqrt(max(1.0 - 0.96 * :math.pow(:math.sin(z_moon_rad), 2), 0.01))

    b_dark_nl = @dark_sky_b0 * van_rhijn * :math.pow(10, -0.4 * k * x_moon) / @nl_factor

    # Twilight component
    # The formula uses sun_alt directly (negative when below horizon).
    # 32.5 - sun_alt = 32.5 + depression, giving dimmer sky for deeper sun.
    b_twilight_nl =
      if depression > 1.0 and depression < 20.0 do
        log_bt = -0.4 * (@ms_v - @m0_v + @twilight_zp - sun_alt - z_moon / (360.0 * k))
        bt = :math.pow(10, log_bt) / @nl_factor
        # Scale by atmospheric absorption along line of sight
        bt * (1.0 - :math.pow(10, -0.4 * k * x_moon))
      else
        0.0
      end

    max(b_dark_nl + b_twilight_nl, 1.0)
  end

  # Limiting visual magnitude given sky brightness in nanolamberts
  # and atmospheric extinction in magnitudes.
  #
  # Based on Schaefer (1990) using Blackwell (1946) contrast data.
  defp limiting_magnitude(b_nl, dm) do
    {c1, c2} =
      if b_nl < 1500.0 do
        {:math.pow(10, -9.8), :math.pow(10, -1.9)}
      else
        {:math.pow(10, -8.35), :math.pow(10, -5.9)}
      end

    # Threshold illuminance (foot-candles)
    th = c1 * :math.pow(1.0 + :math.sqrt(c2 * b_nl), 2)

    # Snellen ratio 1.0 (normal 20/20 vision)
    -16.57 - 2.5 * :math.log10(max(th, 1.0e-30)) - dm
  end

  # Air mass using Kasten & Young approximation.
  # z is zenith distance in radians.
  @half_pi :math.pi() / 2.0

  defp air_mass(z) when z < @half_pi do
    cos_z = :math.cos(z)
    1.0 / (cos_z + 0.025 * :math.exp(-11.0 * cos_z))
  end

  defp air_mass(_z), do: 40.0

  defp classify_schaefer(rs) when rs >= @schaefer_rs_a, do: :A
  defp classify_schaefer(rs) when rs >= @schaefer_rs_b, do: :B
  defp classify_schaefer(rs) when rs >= @schaefer_rs_c, do: :C
  defp classify_schaefer(rs) when rs >= @schaefer_rs_d, do: :D
  defp classify_schaefer(_rs), do: :E

  # ════════════════════════════════════════════════════════════════════════════════
  # Shared helpers
  # ════════════════════════════════════════════════════════════════════════════════

  # Compute best time and evaluate a visibility function.
  # Best time = sunset + 4/9 * (moonset - sunset) [Yallop / Odeh].
  defp with_best_time(location, moment, fun) do
    sunset_result = Solar.SunRiseSet.sunset(location, moment, time_zone: :utc)
    moonset_result = Lunar.MoonRiseSet.moonset(location, moment, time_zone: :utc)

    case {sunset_result, moonset_result} do
      {{:ok, sunset_dt}, {:ok, moonset_dt}} ->
        sunset_moment = Time.date_time_to_moment(sunset_dt)
        moonset_moment = Time.date_time_to_moment(moonset_dt)

        if moonset_moment <= sunset_moment do
          {:ok, :E}
        else
          lag = moonset_moment - sunset_moment
          best_time = sunset_moment + 4.0 / 9.0 * lag
          fun.(best_time)
        end

      {{:ok, sunset_dt}, {:error, _}} ->
        sunset_moment = Time.date_time_to_moment(sunset_dt)
        best_time = sunset_moment + 40.0 / 1440.0
        fun.(best_time)

      {{:error, _}, _} ->
        {:error, :no_sunset}
    end
  end

  # Compute geocentric parameters at a given moment: sun altitude, moon
  # altitude, elongation (ARCL), and crescent width (W) in arcminutes.
  defp geocentric_parameters(best_time, location) do
    {sun_ra, sun_dec, _} = Solar.solar_position(best_time)
    {moon_ra, moon_dec, _} = Lunar.lunar_position(best_time)

    {_sun_az, sun_alt} = azimuth_altitude(sun_ra, sun_dec, best_time, location)
    {_moon_az, moon_alt} = azimuth_altitude(moon_ra, moon_dec, best_time, location)

    cos_arcl =
      sin(sun_dec) * sin(moon_dec) +
        cos(sun_dec) * cos(moon_dec) * cos(sun_ra - moon_ra)

    arcl = :math.acos(clamp(cos_arcl, -1.0, 1.0)) |> to_degrees()

    sd_arcmin = Lunar.angular_semi_diameter(best_time) * 60.0
    w = sd_arcmin * (1.0 - cos(arcl))

    {sun_alt, moon_alt, arcl, w}
  end

  # Geocentric altitude and azimuth from equatorial coordinates.
  defp azimuth_altitude(ra, dec, moment, %Geo.PointZ{coordinates: {longitude, latitude, _alt}}) do
    theta = Time.mean_sidereal_from_moment(moment)
    hour_angle = mod(theta + longitude - ra, 360.0)

    altitude =
      :math.asin(
        clamp(
          sin(dec) * sin(latitude) + cos(dec) * cos(latitude) * cos(hour_angle),
          -1.0,
          1.0
        )
      )
      |> to_degrees()

    cos_a =
      clamp(
        (sin(dec) - sin(altitude) * sin(latitude)) / (cos(altitude) * cos(latitude)),
        -1.0,
        1.0
      )

    a = :math.acos(cos_a) |> to_degrees()

    azimuth = if sin(hour_angle) < 0.0, do: a, else: 360.0 - a

    {azimuth, altitude}
  end

  defp clamp(value, min_val, max_val) do
    value |> max(min_val) |> min(max_val)
  end
end
