defmodule Astro.Solar.SunRiseSet do
  @moduledoc """
  Computes sunrise and sunset times using the JPL DE440s ephemeris and a
  scan-and-bisect algorithm, replacing `Astro.sunrise/3` and `Astro.sunset/3`.

  ## Algorithm

  The same coarse-scan / binary-search framework used by `MoonRiseSet2` is
  applied to the Sun. Because the Sun's equatorial horizontal parallax is only
  ~8.7 arcseconds (≈ 0.002°), no topocentric correction is required; the
  geocentric position is used directly.

  The event condition matches the USNO / timeanddate.com standard:

      geometric_alt_centre = −50′/60°

  where 50′ = 34′ (standard refraction) + 16′ (solar semi-diameter). This
  fixed `h0` is the same constant used by virtually every published sunrise/
  sunset table and is independent of the actual solar distance on the day.

  ## Accuracy

  Expected agreement with `Astro.sunrise/3` and timeanddate.com to within
  1 minute for all latitudes where sunrise and sunset occur. The Sun's
  parallax and semi-diameter are both negligible for this purpose, and the
  dominant error source is real-atmosphere refraction variation.

  ## Required setup

      {:ok, kernel} = Spk.Kernel.load("priv/de440s.bsp")
      {:ok, dt} = SunRiseSet.sunrise(kernel, {151.2093, -33.8688}, ~D[2026-03-08])
      {:ok, dt} = SunRiseSet.sunset(kernel,  {151.2093, -33.8688}, ~D[2026-03-08])

  `de440s.bsp` (~32 MB):
  https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp

  ## Options

    * `:time_zone`          — tz name string, `:utc`, or `:default` (resolve from location)
    * `:time_zone_database` — tz database module or `:configured`
    * `:time_zone_resolver` — 1-arity fn `(%Geo.Point{}) → {:ok, String.t()}`
  """

  alias Astro.{Ephemeris, Coordinates}

  # Coarse scan step (seconds). The Sun is always visible for at least a few
  # minutes when it rises, so 24-minute steps bracket the event reliably.
  @scan_step_s 1_440

  # Bisection precision target (seconds).
  @bisect_tol_s 1.0

  # Maximum bisection iterations (safety cap).
  @bisect_max 60

  # USNO / timeanddate.com event condition for sunrise/sunset:
  # geometric zenith distance of the Sun's centre = 90° + 50′
  # ↔ geometric altitude = −50′/60°
  # where 50′ = 34′ (standard refraction) + 16′ (solar semi-diameter).
  # The solar semi-diameter is nearly constant (≈15.8′–16.3′); the
  # traditional round value of 16′ is used by USNO and timeanddate.com.
  @h0_deg -(50.0 / 60.0)

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Returns the sunrise time for `location` on `date`.

  Mirrors `Astro.sunrise/3` in signature and return value, but derives
  the solar position from the JPL DE440s ephemeris rather than the
  Chapront truncated series.
  """
  @spec sunrise(Astro.location(), Date.t() | DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def sunrise(location, date, options \\ []) do
    sun_event(location, to_date(date), :rise, options)
  end

  @doc """
  Returns the sunset time for `location` on `date`.

  Mirrors `Astro.sunset/3` in signature and return value, but derives
  the solar position from the JPL DE440s ephemeris.
  """
  @spec sunset(Astro.location(), Date.t() | DateTime.t(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def sunset(location, date, options \\ []) do
    sun_event(location, to_date(date), :set, options)
  end

  # ── Core ─────────────────────────────────────────────────────────────────────

  defp sun_event(location, date, event, options) do
    %Geo.PointZ{coordinates: {lng, lat, _elev_m}} =
      Astro.Location.normalize_location(location)

    local_midnight_utc = local_midnight(date, lng)
    et_start = Coordinates.utc_to_et(local_midnight_utc)
    et_end   = et_start + 86_400.0

    scan_pairs =
      Stream.iterate(et_start, &(&1 + @scan_step_s))
      |> Stream.take_while(&(&1 <= et_end))
      |> Enum.map(fn et -> {et, altitude_f(et, lat, lng)} end)

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
        et_event = bisect(et_lo, f_lo, et_hi, f_hi, lat, lng, @bisect_max)
        utc_dt   = Coordinates.et_to_utc(et_event)
        apply_time_zone(utc_dt, location, options)
    end
  end

  # ── Altitude function ────────────────────────────────────────────────────────

  # f(et) = geometric_alt_centre(et) − h0
  #
  # Event occurs at f = 0, i.e. when the Sun's geometric altitude equals h0.
  # Positive f: Sun above the event threshold.
  # Negative f: Sun below the event threshold.
  defp altitude_f(et, lat, lng) do
    {:ok, {ra, dec, _dist}} = Ephemeris.sun_position_et(et)

    gast = Coordinates.gast(et)
    h    = fmod(gast + lng - ra, 360.0)
    h    = if h > 180.0, do: h - 360.0, else: h

    sin_alt =
      sin_d(lat) * sin_d(dec) +
      cos_d(lat) * cos_d(dec) * cos_d(h)

    alt = :math.asin(sin_alt) * 180.0 / :math.pi()
    alt - @h0_deg
  end

  # ── Bisection ────────────────────────────────────────────────────────────────

  defp bisect(et_lo, _f_lo, et_hi, _f_hi, _lat, _lng, 0),
    do: (et_lo + et_hi) / 2.0

  defp bisect(et_lo, f_lo, et_hi, f_hi, lat, lng, iters) do
    if et_hi - et_lo <= @bisect_tol_s do
      (et_lo + et_hi) / 2.0
    else
      et_mid = (et_lo + et_hi) / 2.0
      f_mid  = altitude_f(et_mid, lat, lng)

      if f_lo * f_mid <= 0.0 do
        bisect(et_lo, f_lo, et_mid, f_mid, lat, lng, iters - 1)
      else
        bisect(et_mid, f_mid, et_hi, f_hi, lat, lng, iters - 1)
      end
    end
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
