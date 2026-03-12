defmodule Astro.Solar.SunRiseSet do
  @moduledoc """
  Computes sunrise and sunset times using the JPL DE440s ephemeris and a
  scan-and-bisect algorithm, as an alternative to`Astro.sunrise/3` and
  `Astro.sunset/3`.

  ## Algorithm

  The same coarse-scan / binary-search framework used by `Astro.Lunar.MoonRiseSet` is
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

  * Download https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
    to the priv directory.

  ## Options

    * `:time_zone`          — tz name string, `:utc`, or `:default` (resolve from location)
    * `:time_zone_database` — tz database module or `:configured`
    * `:time_zone_resolver` — 1-arity fn `(%Geo.Point{}) → {:ok, String.t()}`

  """

  alias Astro.{Ephemeris, Coordinates}

  # Coarse scan step (seconds). The Sun is always visible for at least a few
  # minutes when it rises, so 24-minute steps bracket the event reliably.
  @scan_step_s 1_440

  # See Astro.Lunar.MoonRiseSet for the rationale.  The same solar-midnight defect applies
  # here: −14 h / +38 h relative to UTC midnight covers every civil timezone.
  # The Sun rises at most once per 24 h so at most three events appear in the
  # 52-hour window; the correct one is selected by filtering on local date.
  @scan_pre_window_s 14 * 3_600
  @scan_window_s 52 * 3_600

  # Bisection precision target (seconds).
  @bisect_tol_s 0.01

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

  ## Options

    * `:solar_elevation` — the type of sunrise to compute:
      * `:geometric` (default) — upper limb on the horizon (zenith 90°50′)
      * `:civil` — centre of Sun 6° below the horizon (civil twilight)
      * `:nautical` — centre of Sun 12° below the horizon
      * `:astronomical` — centre of Sun 18° below the horizon
      * a number — custom zenith angle in degrees (90 = geometric horizon)
    * `:time_zone`, `:time_zone_database`, `:time_zone_resolver` — as for `Astro.sunrise/3`
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

  Accepts the same options as `sunrise/3`.
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

    h0 = h0_from_options(options)

    {:ok, utc_midnight} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    et_start = Coordinates.utc_to_et(utc_midnight) - @scan_pre_window_s
    et_end = et_start + @scan_window_s

    scan_pairs =
      Stream.iterate(et_start, &(&1 + @scan_step_s))
      |> Stream.take_while(&(&1 <= et_end))
      |> Enum.map(fn et -> {et, altitude_f(et, lat, lng, h0)} end)

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
        et_event = bisect(et_lo, f_lo, et_hi, f_hi, lat, lng, h0, @bisect_max)
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

  # Convert the :solar_elevation option to an altitude threshold in degrees.
  #
  # The solar_elevation values follow the convention from `Astro.sunrise/3`:
  #   :geometric (90°)      → h0 = −50′/60° (refraction 34′ + semi-diameter 16′)
  #   :civil (96°)           → h0 = −6°
  #   :nautical (102°)       → h0 = −12°
  #   :astronomical (108°)   → h0 = −18°
  #   custom number N        → h0 = −(N − 90°)
  defp h0_from_options(options) do
    case Keyword.get(options, :solar_elevation, :geometric) do
      :geometric -> @h0_deg
      :civil -> -6.0
      :nautical -> -12.0
      :astronomical -> -18.0
      n when is_number(n) -> -(n - 90.0)
    end
  end

  # ── Altitude function ────────────────────────────────────────────────────────

  # f(et) = geometric_alt_centre(et) − h0
  #
  # Event occurs at f = 0, i.e. when the Sun's geometric altitude equals h0.
  # Positive f: Sun above the event threshold.
  # Negative f: Sun below the event threshold.
  defp altitude_f(et, lat, lng, h0) do
    {:ok, {ra, dec, _dist}} = Ephemeris.sun_position_et(et)

    gast = Coordinates.gast(et)
    h = fmod(gast + lng - ra, 360.0)
    h = if h > 180.0, do: h - 360.0, else: h

    sin_alt =
      sin_d(lat) * sin_d(dec) +
        cos_d(lat) * cos_d(dec) * cos_d(h)

    alt = :math.asin(sin_alt) * 180.0 / :math.pi()
    alt - h0
  end

  # ── Bisection ────────────────────────────────────────────────────────────────

  defp bisect(et_lo, _f_lo, et_hi, _f_hi, _lat, _lng, _h0, 0),
    do: (et_lo + et_hi) / 2.0

  defp bisect(et_lo, f_lo, et_hi, f_hi, lat, lng, h0, iters) do
    if et_hi - et_lo <= @bisect_tol_s do
      (et_lo + et_hi) / 2.0
    else
      et_mid = (et_lo + et_hi) / 2.0
      f_mid = altitude_f(et_mid, lat, lng, h0)

      if f_lo * f_mid <= 0.0 do
        bisect(et_lo, f_lo, et_mid, f_mid, lat, lng, h0, iters - 1)
      else
        bisect(et_mid, f_mid, et_hi, f_hi, lat, lng, h0, iters - 1)
      end
    end
  end

  # ── Time helpers ─────────────────────────────────────────────────────────────

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
