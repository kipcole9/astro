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

  The altitude function is:

      f(et) = apparent_topocentric_altitude(et) + semi_diameter(et)

  where `apparent_topocentric_altitude` includes atmospheric refraction via
  the Bennett (1982) formula. The event occurs at the zero-crossing of `f`:
  positive → negative for a set, negative → positive for a rise.

  Using the Bennett formula rather than Meeus's fixed 34 arcmin removes an
  additional ~1 arcmin (~1 min of time) systematic bias.

  ## Accuracy

  Expected agreement with timeanddate.com (which uses the same methodology):
  < 1 minute for locations with a flat mathematical horizon and a standard
  atmosphere. The dominant residual is the refraction model, which varies
  by up to ~2 arcmin (≈ 4 min) with real weather conditions.

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

  # Bisection precision target (seconds).
  @bisect_tol_s 1.0

  # Maximum bisection iterations (safety cap; 60 iterations spans 10^18 s).
  @bisect_max 60

  # ── Public API ───────────────────────────────────────────────────────────────

  @spec moonrise(Spk.Kernel.t(), Astro.location(), Date.t() | DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def moonrise(kernel, location, date, options \\ []) do
    moon_event(kernel, location, to_date(date), :rise, options)
  end

  @spec moonset(Spk.Kernel.t(), Astro.location(), Date.t() | DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def moonset(kernel, location, date, options \\ []) do
    moon_event(kernel, location, to_date(date), :set, options)
  end

  # ── Core ─────────────────────────────────────────────────────────────────────

  defp moon_event(kernel, location, date, event, options) do
    %Geo.PointZ{coordinates: {lng, lat, elev_m}} = Astro.Location.normalize_location(location)

    {rho_sin_phi, rho_cos_phi} = geocentric_observer(lat, elev_m)

    # TDB epoch range covering one complete local day.
    local_midnight_utc = local_midnight(date, lng)
    et_start = Coordinates.utc_to_et(local_midnight_utc)
    et_end   = et_start + 86_400.0

    # Evaluate f at each scan point.
    scan_pairs =
      Stream.iterate(et_start, &(&1 + @scan_step_s))
      |> Stream.take_while(&(&1 <= et_end))
      |> Enum.map(fn et ->
        {et, topocentric_f(kernel, et, lat, lng, rho_sin_phi, rho_cos_phi)}
      end)

    # Find the first bracket with the correct sign change polarity.
    bracket =
      scan_pairs
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(fn [{_et1, f1}, {_et2, f2}] ->
        case event do
          :rise -> f1 < 0.0 and f2 >= 0.0
          :set  -> f1 > 0.0 and f2 <= 0.0
        end
      end)

    case bracket do
      nil ->
        {:error, :no_time}

      [{et_lo, f_lo}, {et_hi, f_hi}] ->
        et_event = bisect(kernel, et_lo, f_lo, et_hi, f_hi,
                          lat, lng, rho_sin_phi, rho_cos_phi, @bisect_max)
        utc_dt = Coordinates.et_to_utc(et_event)
        apply_time_zone(utc_dt, location, options)
    end
  end

  # ── Altitude function ────────────────────────────────────────────────────────

  # f(et) = apparent_topocentric_altitude(et) + semi_diameter(et)
  #
  # The event (rise/set) occurs when f = 0, i.e. when the apparent altitude
  # of the Moon's centre equals −semi_diameter (upper limb on apparent horizon).
  #
  # Positive f: Moon is above the horizon.
  # Negative f: Moon is below the horizon.
  defp topocentric_f(kernel, et, lat, lng, rho_sin_phi, rho_cos_phi) do
    {:ok, {ra_geo, dec_geo, dist_km}} = Ephemeris.moon_position_et(kernel, et)

    semi_diam = :math.asin(@moon_radius_km / dist_km) * 180.0 / :math.pi()

    parallax = Ephemeris.equatorial_horizontal_parallax(dist_km)
    sin_pi   = :math.sin(to_rad(parallax))

    gast  = Coordinates.gast(et)
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

    h_topo = h_geo - (delta_alpha_rad * 180.0 / :math.pi())

    sin_alt =
      sin_d(lat) * :math.sin(dec_topo_rad) +
      cos_d(lat) * :math.cos(dec_topo_rad) * cos_d(h_topo)

    alt_geom = :math.asin(sin_alt) * 180.0 / :math.pi()

    # Refraction is defined as a function of APPARENT altitude, not geometric.
    # We solve the implicit equation:
    #   apparent_alt = geometric_alt + R(apparent_alt)
    # by a short fixed-point iteration (converges in 3–4 steps to < 0.001').
    alt_app = apparent_altitude(alt_geom)

    alt_app + semi_diam
  end

  # Solves apparent_alt = geometric_alt + R(apparent_alt) by fixed-point iteration.
  # Starting from the geometric altitude, convergence is rapid because R changes
  # slowly: each step corrects the refraction estimate by ~15%, converging to
  # better than 0.001 arcmin within 4 iterations.
  defp apparent_altitude(alt_geom) do
    # Initial estimate: use geometric alt as the refraction argument.
    apparent_altitude(alt_geom, alt_geom + refraction(alt_geom), 6)
  end

  defp apparent_altitude(_alt_geom, alt_app, 0), do: alt_app

  defp apparent_altitude(alt_geom, alt_app_prev, iters) do
    alt_app = alt_geom + refraction(alt_app_prev)
    if abs(alt_app - alt_app_prev) < 1.0e-6 do
      alt_app
    else
      apparent_altitude(alt_geom, alt_app, iters - 1)
    end
  end

  # ── Bisection ────────────────────────────────────────────────────────────────

  defp bisect(_kernel, et_lo, _f_lo, et_hi, _f_hi,
              _lat, _lng, _rsp, _rcp, 0),
    do: (et_lo + et_hi) / 2.0

  defp bisect(kernel, et_lo, f_lo, et_hi, f_hi,
              lat, lng, rho_sin_phi, rho_cos_phi, iters) do
    if et_hi - et_lo <= @bisect_tol_s do
      (et_lo + et_hi) / 2.0
    else
      et_mid = (et_lo + et_hi) / 2.0
      f_mid  = topocentric_f(kernel, et_mid, lat, lng, rho_sin_phi, rho_cos_phi)

      if f_lo * f_mid <= 0.0 do
        bisect(kernel, et_lo, f_lo, et_mid, f_mid,
               lat, lng, rho_sin_phi, rho_cos_phi, iters - 1)
      else
        bisect(kernel, et_mid, f_mid, et_hi, f_hi,
               lat, lng, rho_sin_phi, rho_cos_phi, iters - 1)
      end
    end
  end

  # ── Atmospheric refraction (Bennett 1982) ────────────────────────────────────

  # Returns atmospheric refraction in degrees for geometric altitude alt_deg.
  # Valid for alt > −5°. At the horizon this gives ~34.5 arcmin, consistent
  # with most professional implementations. Meeus's fixed 34' underestimates
  # by ~0.5 arcmin, causing a ~1 min systematic bias.
  defp refraction(alt_deg) when alt_deg >= 85.0, do: 0.0

  defp refraction(alt_deg) do
    r_arcmin = 1.0 / :math.tan(to_rad(alt_deg + 7.31 / (alt_deg + 4.4)))
    r_arcmin / 60.0
  end

  # ── Observer geocentric factors (Meeus Ch.11) ────────────────────────────────

  defp geocentric_observer(lat_deg, elev_m) do
    elev_km = elev_m / 1000.0
    u = :math.atan(@geodetic_factor * :math.tan(to_rad(lat_deg)))

    rho_sin_phi =
      @geodetic_factor * :math.sin(u) +
        (elev_km / @earth_equatorial_radius_km) * sin_d(lat_deg)

    rho_cos_phi =
      :math.cos(u) +
        (elev_km / @earth_equatorial_radius_km) * cos_d(lat_deg)

    {rho_sin_phi, rho_cos_phi}
  end

  # ── Time helpers ─────────────────────────────────────────────────────────────

  defp local_midnight(date, lng_deg) do
    {:ok, utc_midnight} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    offset_s = round(lng_deg / 360.0 * 86_400.0)
    DateTime.add(utc_midnight, -offset_s, :second)
  end

  # ── Time zone helpers ────────────────────────────────────────────────────────

  defp apply_time_zone(utc_dt, location, options) do
    tz_name = Keyword.get(options, :time_zone, :default)
    tz_db   = Keyword.get(options, :time_zone_database, :configured)

    tz_result =
      case tz_name do
        :utc     -> {:ok, "Etc/UTC"}
        :default -> resolve_time_zone(location, options)
        tz       -> {:ok, tz}
      end

    case tz_result do
      {:ok, tz} -> shift_zone(utc_dt, tz, tz_db)
      error     -> error
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
  defp shift_zone(utc_dt, tz, tz_db),       do: DateTime.shift_zone(utc_dt, tz, tz_db)

  # ── Math helpers ─────────────────────────────────────────────────────────────

  defp sin_d(deg),  do: :math.sin(to_rad(deg))
  defp cos_d(deg),  do: :math.cos(to_rad(deg))
  defp to_rad(deg), do: deg * :math.pi() / 180.0

  defp fmod(x, m) when x >= 0, do: :math.fmod(x, m)
  defp fmod(x, m),              do: :math.fmod(x, m) + m

  defp to_date(%Date{} = d),            do: d
  defp to_date(%DateTime{} = dt),       do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
end
