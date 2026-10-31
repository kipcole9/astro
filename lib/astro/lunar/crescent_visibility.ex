defmodule Astro.Lunar.CrescentVisibility do
  @moduledoc """
  Implements three criteria for predicting the visibility of the new
  crescent moon: Yallop (1997), Odeh (2004), and Schaefer (1988/2000).

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

  ## Odeh (2004)

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

  alias Astro.{Lunar, Solar, Time}

  import Astro.Math,
    only: [
      sin: 1,
      cos: 1,
      mod: 2,
      to_degrees: 1
    ]

  @type visibility :: :A | :B | :C | :D | :E

  # The categories that count as a sighting, and how many evenings after a
  # new moon a first sighting is looked for.
  @visible_categories [:A, :B, :C]
  @first_sighting_evenings 30

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

  @half_pi :math.pi() / 2.0

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

  * `{:error, :no_sunset}` if no sunset occurs on the given date at
    the given location.

  ### Examples

      iex> mecca = %Geo.PointZ{coordinates: {39.8579, 21.3891, 0.0}}
      iex> Astro.Lunar.CrescentVisibility.yallop_new_visible_crescent(mecca, Astro.Time.date_time_to_moment(~D[2024-12-02]))
      {:ok, :A}
      iex> Astro.Lunar.CrescentVisibility.yallop_new_visible_crescent(mecca, Astro.Time.date_time_to_moment(~D[2024-11-01]))
      {:ok, :E}

  """
  @spec yallop_new_visible_crescent(Geo.PointZ.t(), Time.moment(), keyword()) ::
          {:ok, visibility()} | {:error, atom()}

  def yallop_new_visible_crescent(location, moment, options \\ []) do
    with_best_time(location, moment, options, fn best_time ->
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
  # Odeh (2004)
  # ════════════════════════════════════════════════════════════════════════════════

  @doc """
  Computes the Odeh (2004) visibility criterion for the new crescent moon.

  Uses topocentric ARCV, the same polynomial family as Yallop with an
  updated intercept (7.1651), and enforces a Danjon limit of 6.4°.

  ### Arguments

  * `location` is a `t:Geo.PointZ.t/0` struct (already normalized).

  * `moment` is a `t:Astro.Time.moment/0` representing the date.

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of `:A`, `:B`, `:C`, `:D`, or `:E`.

  * `{:error, :no_sunset}` if no sunset occurs on the given date at
    the given location.

  ### Examples

      iex> mecca = %Geo.PointZ{coordinates: {39.8579, 21.3891, 0.0}}
      iex> Astro.Lunar.CrescentVisibility.odeh_new_visible_crescent(mecca, Astro.Time.date_time_to_moment(~D[2024-12-02]))
      {:ok, :A}
      iex> Astro.Lunar.CrescentVisibility.odeh_new_visible_crescent(mecca, Astro.Time.date_time_to_moment(~D[2024-11-01]))
      {:ok, :E}

  """
  @spec odeh_new_visible_crescent(Geo.PointZ.t(), Time.moment(), keyword()) ::
          {:ok, visibility()} | {:error, atom()}

  def odeh_new_visible_crescent(location, moment, options \\ []) do
    with_best_time(location, moment, options, fn best_time ->
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

  * `options` is a keyword list of options.

  ### Options

  * `:extinction` is the V-band zenith extinction coefficient. The
    default is `0.172`, a clean sea-level site. Typical values are
    `0.12` on a high mountain, `0.17` at sea level and `0.25` in hazy
    conditions.

  ### Returns

  * `{:ok, visibility}` where `visibility` is one of `:A`, `:B`, `:C`, `:D`, or `:E`.

  * `{:error, :no_sunset}` if no sunset occurs on the given date at
    the given location.

  ### Examples

      iex> mecca = %Geo.PointZ{coordinates: {39.8579, 21.3891, 0.0}}
      iex> moment = Astro.Time.date_time_to_moment(~D[2024-12-02])
      iex> Astro.Lunar.CrescentVisibility.schaefer_new_visible_crescent(mecca, moment, extinction: 0.25)
      {:ok, :A}

  """
  @spec schaefer_new_visible_crescent(Geo.PointZ.t(), Time.moment(), keyword()) ::
          {:ok, visibility()} | {:error, atom()}

  def schaefer_new_visible_crescent(location, moment, options \\ []) do
    k = Keyword.get(options, :extinction, @default_extinction)

    sunset_result = Solar.SunRiseSet.sunset(location, moment, rise_set_options(options))
    moonset_result = Lunar.MoonRiseSet.moonset(location, moment, rise_set_options(options))

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

      {{:error, :no_time}, _} ->
        {:error, :no_sunset}

      {{:error, _reason} = error, _moonset} ->
        error
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
    # It applies from the horizon down: at sunset the sun's centre is already
    # about 0.8° below it, and leaving out the twilight there modelled the
    # brightest sky of the evening as a dark one.
    b_twilight_nl =
      if depression > 0.0 and depression < 20.0 do
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
  # ════════════════════════════════════════════════════════════════════════════════
  # First visibility
  # ════════════════════════════════════════════════════════════════════════════════

  @doc """
  Returns the evening of the last first sighting of a new crescent on
  or before an evening.

  A lunation's crescent is first seen on the first evening, from the
  evening before the day of its new moon, on which `method` classes it
  visible. This is the latest such evening on or before `day`: the
  evening a lunar month that begins at first sighting began on.

  ### Arguments

  * `location` is a `t:Geo.PointZ.t/0` struct (already normalized).

  * `day` is the evening as an integer number of days since
    `0000-01-01`.

  * `method` is `:odeh`, `:yallop` or `:schaefer`.

  * `options` is a keyword list of options.

  ### Options

  * `:visible` is the list of categories that count as a sighting. The
    default is `[:A, :B, :C]`.

  * `:utc_offset` and `:extinction` are as for the criteria.

  ### Returns

  * `{:ok, day}`, the evening as an integer number of days since
    `0000-01-01`.

  * `{:error, :no_visible_crescent}` if a lunation's crescent is not
    seen within 30 evenings of its new moon, as at high latitudes.

  Raises `ArgumentError` for a day more than 50,000 years from J2000.

  ### Examples

      iex> mecca = %Geo.PointZ{coordinates: {39.8262, 21.4225, 277.0}}
      iex> day = Date.to_gregorian_days(~D[2024-12-20])
      iex> {:ok, evening} = Astro.Lunar.CrescentVisibility.first_visible_crescent_on_or_before(mecca, day, :odeh)
      iex> Date.from_gregorian_days(evening)
      ~D[2024-12-02]

  """
  @doc since: "2.10.0"
  @spec first_visible_crescent_on_or_before(Geo.PointZ.t(), integer(), atom(), keyword()) ::
          {:ok, integer()} | {:error, atom()}
  def first_visible_crescent_on_or_before(location, day, method, options \\ []) do
    new_moon = Lunar.date_time_new_moon_before(end_of_evening(day, options))

    with {:ok, evening} <- first_visible_evening(location, new_moon, method, options) do
      if evening <= day do
        {:ok, evening}
      else
        first_visible_evening(
          location,
          Lunar.date_time_new_moon_before(new_moon),
          method,
          options
        )
      end
    end
  end

  @doc """
  Returns the evening of the next first sighting of a new crescent on
  or after an evening.

  See `first_visible_crescent_on_or_before/4` for the first sighting.

  ### Arguments

  * `location` is a `t:Geo.PointZ.t/0` struct (already normalized).

  * `day` is the evening as an integer number of days since
    `0000-01-01`.

  * `method` is `:odeh`, `:yallop` or `:schaefer`.

  * `options` is a keyword list of options, as for
    `first_visible_crescent_on_or_before/4`.

  ### Returns

  * `{:ok, day}`, the evening as an integer number of days since
    `0000-01-01`.

  * `{:error, :no_visible_crescent}` if a lunation's crescent is not
    seen within 30 evenings of its new moon.

  Raises `ArgumentError` for a day more than 50,000 years from J2000.

  ### Examples

      iex> mecca = %Geo.PointZ{coordinates: {39.8262, 21.4225, 277.0}}
      iex> day = Date.to_gregorian_days(~D[2024-12-20])
      iex> {:ok, evening} = Astro.Lunar.CrescentVisibility.first_visible_crescent_on_or_after(mecca, day, :odeh)
      iex> Date.from_gregorian_days(evening)
      ~D[2025-01-01]

  """
  @doc since: "2.10.0"
  @spec first_visible_crescent_on_or_after(Geo.PointZ.t(), integer(), atom(), keyword()) ::
          {:ok, integer()} | {:error, atom()}
  def first_visible_crescent_on_or_after(location, day, method, options \\ []) do
    new_moon = Lunar.date_time_new_moon_before(end_of_evening(day, options))

    with {:ok, evening} <- first_visible_evening(location, new_moon, method, options) do
      if evening >= day do
        {:ok, evening}
      else
        next_new_moon = Lunar.date_time_new_moon_at_or_after(new_moon + 1.0)
        first_visible_evening(location, next_new_moon, method, options)
      end
    end
  end

  # The moment the local day of `day`'s evening ends: a new moon after it
  # cannot be seen that evening.
  defp end_of_evening(day, options) do
    day + 1 - Keyword.get(options, :utc_offset, 0) / 86_400
  end

  # The first evening, from the evening before the local day of the new
  # moon, on which the crescent is classed visible.
  defp first_visible_evening(location, new_moon, method, options) do
    first = floor(new_moon + Keyword.get(options, :utc_offset, 0) / 86_400) - 1
    find_visible_evening(location, first, first + @first_sighting_evenings, method, options)
  end

  defp find_visible_evening(_location, day, last, _method, _options) when day > last do
    {:error, :no_visible_crescent}
  end

  defp find_visible_evening(location, day, last, method, options) do
    case sighting(location, day, method, options) do
      {:ok, true} -> {:ok, day}
      {:ok, false} -> find_visible_evening(location, day + 1, last, method, options)
      {:error, _reason} = error -> error
    end
  end

  # Whether the crescent is classed visible on `day`'s evening. An evening
  # with no sunset has no sighting.
  defp sighting(location, day, method, options) do
    visible = Keyword.get(options, :visible, @visible_categories)

    case classify(location, day, method, options) do
      {:ok, category} -> {:ok, category in visible}
      {:error, :no_sunset} -> {:ok, false}
      {:error, _reason} = error -> error
    end
  end

  defp classify(location, day, :odeh, options) do
    odeh_new_visible_crescent(location, day, options)
  end

  defp classify(location, day, :yallop, options) do
    yallop_new_visible_crescent(location, day, options)
  end

  defp classify(location, day, :schaefer, options) do
    schaefer_new_visible_crescent(location, day, options)
  end

  defp with_best_time(location, moment, options, fun) do
    sunset_result = Solar.SunRiseSet.sunset(location, moment, rise_set_options(options))
    moonset_result = Lunar.MoonRiseSet.moonset(location, moment, rise_set_options(options))

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

      {{:error, :no_time}, _} ->
        {:error, :no_sunset}

      {{:error, _reason} = error, _moonset} ->
        error
    end
  end

  # Sunset and moonset in UTC, on the evening of the date at `:utc_offset`
  # when it is given and of the UTC date otherwise.
  defp rise_set_options(options) do
    case Keyword.get(options, :utc_offset) do
      nil -> [time_zone: :utc]
      utc_offset -> [time_zone: :utc, utc_offset: utc_offset]
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
