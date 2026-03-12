defmodule Astro.Lunar.MoonRiseSet do
  @moduledoc """
  Computes moonrise and moonset times using the JPL DE440s ephemeris and a
  fully topocentric bisection algorithm.

  ## Algorithm

  The Meeus Ch.15 three-point geocentric iteration — used by `MoonRiseSet`
  — handles parallax-in-altitude via the `h0 = 0.7275π − 0.5667°` formula
  but ignores the RA component of lunar parallax (~47 arcmin at the horizon
  for mid-latitudes). This produces a systematic 2–3 minute error because
  the apparent moon is displaced in RA from the geocentric position by the
  observer's parallax.

  This module removes that error entirely by abandoning the interpolation
  framework. Instead:

  1. **Coarse scan** — the local day is sampled at `@scan_step_s`-second
     intervals. At each sample the instantaneous topocentric apparent altitude
     is evaluated directly from the ephemeris. Adjacent samples with opposite
     sign identify a rise or set event bracketed to within one scan step.

  2. **Binary search** — the bracket is bisected until its width falls below
     `@bisect_tol_s` seconds (default: 1 s). Each probe evaluates one
     ephemeris position, one Ch.40 topocentric correction, and one refraction
     call — no derivatives, no interpolation error.

  where the event is defined to match the USNO / timeanddate.com standard:
  the topocentric geometric altitude of the Moon's centre equals
  `−(34'/60° + semi_diameter)`, where 34' is a fixed standard-atmosphere
  refraction constant. This is equivalent to the USNO's published condition
  `zd_centre = 90.5666° + angular_radius − horizontal_parallax`, once the
  horizontal parallax is absorbed by computing the topocentric position directly.

  ## Accuracy

  Expected agreement with timeanddate.com to within their 1-minute display
  resolution for locations with a flat mathematical horizon. The dominant
  residual is real-atmosphere refraction variation (~±2 arcmin, ≈ ±10 s),
  which neither this implementation nor timeanddate.com models.

  ## Required setup

      {:ok, kernel} = Spk.Kernel.load("priv/de440s.bsp")
      {:ok, dt} = MoonRiseSet2.moonrise(kernel, {151.2093, -33.8688}, ~D[2026-03-08])

  `de440s.bsp` (~32 MB):
  https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp

  ## Options

    * `:time_zone`          — tz name string, `:utc`, or `:default` (resolve from location)
    * `:time_zone_database` — tz database module or `:configured`
    * `:time_zone_resolver` — 1-arity fn `(%Geo.Point{}) → {:ok, String.t()}`
  """

  alias Astro.{Ephemeris, Coordinates}

  # WGS-84 geodetic → geocentric latitude conversion factor.
  @geodetic_factor 0.99664719

  # WGS-84 equatorial radius (km).
  @earth_equatorial_radius_km 6378.137

  # Moon mean radius (IAU 2015), km.
  @moon_radius_km 1737.4

  # Coarse scan step (seconds). Must be shorter than the minimum possible
  # duration of any lunar appearance above the horizon (always ≥ 6 h).
  @scan_step_s 1_440

  # Event condition matching the USNO / timeanddate.com standard
  # (see [RST_defs](https://aa.usno.navy.mil/faq/docs/RST_defs.php)):
  #   geometric zenith distance of centre = 90° + refraction + semi_diam − h_parallax
  # In topocentric geometric altitude this reduces to:
  #   alt_geom = −(refraction + semi_diam)
  # where the horizontal parallax has already been absorbed by computing the
  # topocentric position directly via Ch.40.
  #
  # Standard atmospheric refraction at the horizon (USNO convention: 34').
  @std_refraction_deg 34.0 / 60.0

  # The scan window is anchored to UTC midnight of the requested date rather
  # than to the observer's solar midnight (lng/360 × 86400 s).  The solar
  # midnight approach fails whenever the civil timezone diverges from the
  # observer's solar longitude — which includes DST transitions, politically
  # offset timezones (Spain, western China), and any location not near its
  # timezone's nominal meridian.  A window of −14 h to +38 h relative to UTC
  # midnight covers every civil day in every timezone (offsets range −12 to
  # +14).  The 52-hour span can contain at most three lunar rise or set events
  # (~24.8 h period); the correct one is identified by filtering on local date.
  # seconds before UTC midnight
  @scan_pre_window_s 14 * 3_600
  # total scan duration
  @scan_window_s 52 * 3_600

  # Bisection precision target (seconds).
  @bisect_tol_s 1.0

  # Maximum bisection iterations (safety cap; 60 iterations spans 10^18 s).
  @bisect_max 60

  # ── Public API ───────────────────────────────────────────────────────────────

  @spec moonrise(Astro.location(), Date.t() | DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def moonrise(location, date, options \\ []) do
    moon_event(location, to_date(date), :rise, options)
  end

  @spec moonset(Astro.location(), Date.t() | DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def moonset(location, date, options \\ []) do
    moon_event(location, to_date(date), :set, options)
  end

  # ── Core ─────────────────────────────────────────────────────────────────────

  defp moon_event(location, date, event, options) do
    %Geo.PointZ{coordinates: {lng, lat, elev_m}} = Astro.Location.normalize_location(location)

    {rho_sin_phi, rho_cos_phi} = geocentric_observer(lat, elev_m)

    # Build the altitude function. When :interpolation is :lagrange, we use
    # three-point Lagrange quadratic interpolation of the Moon's geocentric
    # position (sampled at 0h TT for T-1, T, T+1) to approximate RA, Dec,
    # and distance at intermediate times. This reproduces the Meeus Ch.15
    # approach used by the USNO.
    interpolation = Keyword.get(options, :interpolation, :direct)

    # Always use direct ephemeris for the coarse scan
    direct_fn = fn et -> topocentric_f(et, lat, lng, rho_sin_phi, rho_cos_phi) end

    {:ok, utc_midnight} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    et_start = Coordinates.utc_to_et(utc_midnight) - @scan_pre_window_s
    et_end = et_start + @scan_window_s

    # Evaluate f at each scan point.
    scan_pairs =
      Stream.iterate(et_start, &(&1 + @scan_step_s))
      |> Stream.take_while(&(&1 <= et_end))
      |> Enum.map(fn et -> {et, direct_fn.(et)} end)

    # Collect every bracket with the correct sign-change polarity.
    brackets =
      scan_pairs
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [{_et1, f1}, {_et2, f2}] ->
        case event do
          :rise -> f1 < 0.0 and f2 >= 0.0
          :set -> f1 > 0.0 and f2 <= 0.0
        end
      end)

    result =
      Enum.find_value(brackets, fn [{et_lo, f_lo}, {et_hi, f_hi}] ->
        # For Lagrange mode, build an interpolator centred on the bracket
        # midpoint and use it for bisection refinement.
        alt_fn =
          case interpolation do
            :lagrange ->
              et_mid = (et_lo + et_hi) / 2.0
              interp = build_lagrange_interpolator(date, et_mid)
              fn et -> lagrange_topocentric_f(et, interp, lat, lng, rho_sin_phi, rho_cos_phi) end

            :direct ->
              direct_fn
          end

        # Re-evaluate bracket endpoints with the chosen function
        f_lo_b = alt_fn.(et_lo)
        f_hi_b = alt_fn.(et_hi)

        et_event = bisect_with_fn(et_lo, f_lo_b, et_hi, f_hi_b, alt_fn, @bisect_max)

        utc_dt = Coordinates.et_to_utc(et_event)

        case apply_time_zone(utc_dt, location, options) do
          {:ok, local_dt}
          when local_dt.year == date.year and
                 local_dt.month == date.month and
                 local_dt.day == date.day ->
            {:ok, local_dt}

          {:ok, _} ->
            nil

          error ->
            error
        end
      end)

    result || {:error, :no_time}
  end

  # ── Altitude function ────────────────────────────────────────────────────────

  # f(et) = apparent_topocentric_altitude(et) + semi_diameter(et)
  #
  # The event (rise/set) occurs when f = 0, i.e. when the apparent altitude
  # of the Moon's centre equals −semi_diameter (upper limb on apparent horizon).
  #
  # Positive f: Moon is above the horizon.
  # Negative f: Moon is below the horizon.
  defp topocentric_f(et, lat, lng, rho_sin_phi, rho_cos_phi) do
    {:ok, {ra_geo, dec_geo, dist_km}} = Ephemeris.moon_position_et(et)

    semi_diam = :math.asin(@moon_radius_km / dist_km) * 180.0 / :math.pi()

    parallax = Ephemeris.equatorial_horizontal_parallax(dist_km)
    sin_pi = :math.sin(to_rad(parallax))

    gast = Coordinates.gast(et)
    h_geo = fmod(gast + lng - ra_geo, 360.0)
    h_geo = if h_geo > 180.0, do: h_geo - 360.0, else: h_geo

    # Δα (Meeus eq. 40.2)
    delta_alpha_rad =
      :math.atan2(
        -rho_cos_phi * sin_pi * sin_d(h_geo),
        cos_d(dec_geo) - rho_cos_phi * sin_pi * cos_d(h_geo)
      )

    # δ' (Meeus eq. 40.3)
    dec_topo_rad =
      :math.atan2(
        (sin_d(dec_geo) - rho_sin_phi * sin_pi) * :math.cos(delta_alpha_rad),
        cos_d(dec_geo) - rho_cos_phi * sin_pi * cos_d(h_geo)
      )

    h_topo = h_geo - delta_alpha_rad * 180.0 / :math.pi()

    sin_alt =
      sin_d(lat) * :math.sin(dec_topo_rad) +
        cos_d(lat) * :math.cos(dec_topo_rad) * cos_d(h_topo)

    alt_geom = :math.asin(sin_alt) * 180.0 / :math.pi()

    alt_geom + semi_diam + @std_refraction_deg
  end

  # ── Lagrange interpolation ───────────────────────────────────────────────────

  # Lagrange interpolation interval (seconds).
  # Using 2-hour intervals for the three-point quadratic gives much tighter
  # approximation than the classical Meeus Ch.15 daily tabulation.
  @lagrange_interval_s 7_200

  # Build a Lagrange interpolator from 3 tabular positions.
  # The tabular points are spaced by @lagrange_interval_s seconds, centred
  # on the midpoint of the given bracket [et_lo, et_hi].
  defp build_lagrange_interpolator(_date, et_center \\ nil) do
    # Default: centre on 12h UTC of the date
    et_center = et_center || raise("must provide et_center")
    et0 = et_center - @lagrange_interval_s
    et2 = et_center + @lagrange_interval_s

    {:ok, {ra0, dec0, dist0}} = Ephemeris.moon_position_et(et0)
    {:ok, {ra1, dec1, dist1}} = Ephemeris.moon_position_et(et_center)
    {:ok, {ra2, dec2, dist2}} = Ephemeris.moon_position_et(et2)

    # Fix RA discontinuities near 0/360 boundary
    {ra0, ra1, ra2} = fix_ra_wrap(ra0, ra1, ra2)

    %{
      et_center: et_center,
      interval: @lagrange_interval_s * 1.0,
      ra: {ra0, ra1, ra2},
      dec: {dec0, dec1, dec2},
      dist: {dist0, dist1, dist2}
    }
  end

  defp fix_ra_wrap(ra0, ra1, ra2) do
    ra0 = if ra1 - ra0 > 180.0, do: ra0 + 360.0, else: ra0
    ra0 = if ra0 - ra1 > 180.0, do: ra0 - 360.0, else: ra0
    ra2 = if ra1 - ra2 > 180.0, do: ra2 + 360.0, else: ra2
    ra2 = if ra2 - ra1 > 180.0, do: ra2 - 360.0, else: ra2
    {ra0, ra1, ra2}
  end

  # Three-point Lagrange quadratic interpolation.
  # n is the interpolation parameter: n=0 at et_center, n=±1 at the
  # adjacent tabular points. Meeus eq 3.3.
  defp lagrange_3pt(n, {y1, y2, y3}) do
    a = y2 - y1
    b = y3 - y2
    c = b - a
    y2 + n / 2.0 * (a + b + n * c)
  end

  # Altitude function using Lagrange-interpolated Moon position.
  # This mimics the Meeus Ch.15 approach where the Moon's geocentric
  # RA, Dec, and distance are interpolated from 3 daily tabular points.
  defp lagrange_topocentric_f(et, interp, lat, lng, rho_sin_phi, rho_cos_phi) do
    n = (et - interp.et_center) / interp.interval

    ra_geo = lagrange_3pt(n, interp.ra)
    dec_geo = lagrange_3pt(n, interp.dec)
    dist_km = lagrange_3pt(n, interp.dist)

    # Normalize RA to [0, 360)
    ra_geo = :math.fmod(ra_geo, 360.0)
    ra_geo = if ra_geo < 0, do: ra_geo + 360.0, else: ra_geo

    semi_diam = :math.asin(@moon_radius_km / dist_km) * 180.0 / :math.pi()
    parallax = Ephemeris.equatorial_horizontal_parallax(dist_km)
    sin_pi = :math.sin(to_rad(parallax))

    gast = Coordinates.gast(et)
    h_geo = fmod(gast + lng - ra_geo, 360.0)
    h_geo = if h_geo > 180.0, do: h_geo - 360.0, else: h_geo

    # Meeus Ch.40 topocentric correction
    delta_alpha_rad =
      :math.atan2(
        -rho_cos_phi * sin_pi * sin_d(h_geo),
        cos_d(dec_geo) - rho_cos_phi * sin_pi * cos_d(h_geo)
      )

    dec_topo_rad =
      :math.atan2(
        (sin_d(dec_geo) - rho_sin_phi * sin_pi) * :math.cos(delta_alpha_rad),
        cos_d(dec_geo) - rho_cos_phi * sin_pi * cos_d(h_geo)
      )

    h_topo = h_geo - delta_alpha_rad * 180.0 / :math.pi()

    sin_alt =
      sin_d(lat) * :math.sin(dec_topo_rad) +
        cos_d(lat) * :math.cos(dec_topo_rad) * cos_d(h_topo)

    alt_geom = :math.asin(sin_alt) * 180.0 / :math.pi()

    alt_geom + semi_diam + @std_refraction_deg
  end

  # ── Bisection ────────────────────────────────────────────────────────────────

  # Bisection using a generic altitude function (for :lagrange and :direct modes)
  defp bisect_with_fn(et_lo, _f_lo, et_hi, _f_hi, _f, 0),
    do: (et_lo + et_hi) / 2.0

  defp bisect_with_fn(et_lo, f_lo, et_hi, f_hi, f, iters) do
    if et_hi - et_lo <= @bisect_tol_s do
      (et_lo + et_hi) / 2.0
    else
      et_mid = (et_lo + et_hi) / 2.0
      f_mid = f.(et_mid)

      if f_lo * f_mid <= 0.0 do
        bisect_with_fn(et_lo, f_lo, et_mid, f_mid, f, iters - 1)
      else
        bisect_with_fn(et_mid, f_mid, et_hi, f_hi, f, iters - 1)
      end
    end
  end

  # ── Standard refraction constant (USNO / timeanddate.com) ───────────────────

  # Fixed 34-arcminute standard-atmosphere refraction, expressed in degrees.
  # The USNO defines moonrise/moonset using this constant (RST_defs page):
  #   zd_centre = 90° + 34' + angular_radius − horizontal_parallax
  # timeanddate.com follows the same convention. Using 34' here rather than
  # a formula (e.g. Bennett's ~38' at −0.26° apparent altitude) ensures our
  # results agree with both references to within their 1-minute display precision.

  # ── Observer geocentric factors (Meeus Ch.11) ────────────────────────────────

  defp geocentric_observer(lat_deg, elev_m) do
    elev_km = elev_m / 1000.0
    u = :math.atan(@geodetic_factor * :math.tan(to_rad(lat_deg)))

    rho_sin_phi =
      @geodetic_factor * :math.sin(u) +
        elev_km / @earth_equatorial_radius_km * sin_d(lat_deg)

    rho_cos_phi =
      :math.cos(u) +
        elev_km / @earth_equatorial_radius_km * cos_d(lat_deg)

    {rho_sin_phi, rho_cos_phi}
  end

  # ── Time zone helpers ────────────────────────────────────────────────────────

  defp apply_time_zone(utc_dt, location, options) do
    tz_name = Keyword.get(options, :time_zone, :default)
    tz_db = Keyword.get(options, :time_zone_database, :configured)

    tz_result =
      case tz_name do
        :utc -> {:ok, "Etc/UTC"}
        :default -> resolve_time_zone(location, options)
        tz -> {:ok, tz}
      end

    case tz_result do
      {:ok, tz} -> shift_zone(utc_dt, tz, tz_db)
      error -> error
    end
  end

  defp resolve_time_zone(location, options) do
    resolver = Keyword.get(options, :time_zone_resolver, &default_resolver/1)
    %Geo.PointZ{coordinates: {lng, lat, _}} = Astro.Location.normalize_location(location)
    resolver.(%Geo.Point{coordinates: {lng, lat}})
  end

  defp default_resolver(point) do
    if Code.ensure_loaded?(TzWorld),
      do: TzWorld.timezone_at(point),
      else: {:error, :time_zone_not_resolved}
  end

  defp shift_zone(utc_dt, tz, :configured), do: DateTime.shift_zone(utc_dt, tz)
  defp shift_zone(utc_dt, tz, tz_db), do: DateTime.shift_zone(utc_dt, tz, tz_db)

  # ── Math helpers ─────────────────────────────────────────────────────────────

  defp sin_d(deg), do: :math.sin(to_rad(deg))
  defp cos_d(deg), do: :math.cos(to_rad(deg))
  defp to_rad(deg), do: deg * :math.pi() / 180.0

  defp fmod(x, m) when x >= 0, do: :math.fmod(x, m)
  defp fmod(x, m), do: :math.fmod(x, m) + m

  defp to_date(%Date{} = d), do: d
  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
end
