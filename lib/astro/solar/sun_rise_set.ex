defmodule Astro.Solar.SunRiseSet do
  @moduledoc """
  Computes sunrise and sunset times using the JPL DE440s ephemeris and a
  scan-and-bisect algorithm.

  This module is the implementation behind `Astro.sunrise/3` and
  `Astro.sunset/3`.

  ## Algorithm

  The same coarse-scan / binary-search framework used by `Astro.Lunar.MoonRiseSet` is
  applied to the Sun. Because the Sun's equatorial horizontal parallax is only
  ~8.7 arcseconds (≈ 0.002°), no topocentric correction is required; the
  geocentric position is used directly.

  The event condition matches the USNO / timeanddate.com standard:

      geometric_alt_centre = −50′/60°

  where 50′ = 34′ (standard refraction) + 16′ (solar semi-diameter). This
  fixed threshold is the same constant used by virtually every published sunrise/
  sunset table and is independent of the actual solar distance on the day.

  ## Accuracy

  ### Comparison with timeanddate.com

  Expected agreement with [timeanddate.com](https://www.timeanddate.com) to
  within their 1-minute display resolution for all latitudes where sunrise and
  sunset occur and where the location has a flat mathematical horizon. The test
  suite validates 343 cases across five cities (Sydney, Moscow, New York,
  Beijing, São Paulo) against reference data with a ±1 minute tolerance.

  ### Comparison with Skyfield

  [Skyfield](https://rhodesmill.org/skyfield/) is a high-accuracy Python
  astronomy library that also uses JPL ephemerides (DE421/DE440) for solar
  position and a numerical root-finding approach. The two implementations
  share the same underlying positional data source and a similar solver
  strategy (coarse scan then bisection), so they are expected to agree to
  within a few seconds for standard (geometric) sunrise/sunset. Residual
  differences arise from:

  * Skyfield uses the IERS-based precession-nutation model (IAU 2000A/2006),
    while this module uses IAU 1976 precession and IAU 1980 nutation. The
    difference in apparent solar RA is below 0.01 s of time for modern dates.
  * Skyfield's refraction model optionally accounts for observer elevation
    and temperature/pressure, whereas this module uses the fixed 34′ standard
    atmosphere constant.

  ### Comparison with NOAA Solar Calculator

  The [NOAA Solar Calculator](https://gml.noaa.gov/grad/solcalc/) uses the
  Meeus analytical polynomial series for solar position and an iterative
  formula for the rise/set time. `Astro.Solar` (`lib/astro/solar.ex`)
  implements this same NOAA/Meeus algorithm. Differences between this module
  and the NOAA approach are typically under 30 seconds and arise from:

  * This module evaluates solar positions from the JPL DE440s numerical
    ephemeris (Chebyshev polynomials fitted to a full n-body integration),
    while the NOAA algorithm uses truncated analytical series from Meeus.
  * This module applies a variable ΔT correction based on IERS observations
    (1972–2025) and Meeus polynomial approximations for historical dates,
    while the NOAA calculator uses a simpler ΔT model.
  * This module uses a scan-and-bisect solver with 0.01 s tolerance,
    while the NOAA algorithm uses an iterative analytical formula.

  For all three references the dominant error source is real-atmosphere
  refraction variation (±2 arcmin ≈ ±10 s at the horizon), which none
  of these implementations model.

  ## Solar elevation options

  The `:solar_elevation` option controls which event is computed. The
  terminology can be confusing because different references use
  "solar elevation", "solar zenith angle", and "solar depression" to
  describe overlapping concepts.

  | Term | Definition | Relationship |
  |---|---|---|
  | **Geometric altitude** | Angle of the Sun's centre above the geometric (airless) horizon, measured from 0° (horizon) to +90° (zenith). | — |
  | **Solar zenith angle** | Complement of altitude: 90° − altitude. 0° at the zenith, 90° at the horizon. | zenith = 90° − altitude |
  | **Solar depression** | Angle below the horizon, i.e. the negation of a negative altitude. Used for twilight thresholds. | depression = −altitude (when Sun is below horizon) |

  Sunrise and sunset occur when the Sun's geometric altitude crosses a
  threshold that accounts for atmospheric refraction (34′) and the Sun's
  angular semi-diameter (16′). The named `:solar_elevation` values and
  their corresponding thresholds are:

  | Option | Zenith angle | Altitude threshold | Description |
  |---|---|---|---|
  | `:geometric` | 90°50′ | −0.8333° | **Standard sunrise/sunset.** Upper limb of the Sun appears to touch the horizon after accounting for standard atmospheric refraction. |
  | `:civil` | 96° | −6° | **Civil twilight.** Enough light for outdoor activities without artificial lighting. The horizon is clearly visible. |
  | `:nautical` | 102° | −12° | **Nautical twilight.** The horizon is faintly visible at sea. Bright stars are visible for celestial navigation. |
  | `:astronomical` | 108° | −18° | **Astronomical twilight.** The sky is dark enough for astronomical observations of faint objects. |
  | Custom number N | N° | −(N − 90)° | A custom zenith angle in degrees, converted to an altitude threshold. |

  Note: the `:geometric` option name is historical. Despite its name, the
  `:geometric` threshold does include standard atmospheric refraction (34′)
  and solar semi-diameter (16′). A truly geometric (airless, centre-of-disk)
  event would use a custom value of 90.0.

  ## Required setup

  The JPL DE440s ephemeris file must be present:

  * Download `de440s.bsp` from
    https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
    to the `priv` directory.

  """

  alias Astro.{Ephemeris, Coordinates, Time}

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
  Returns the sunrise time for a given location and date.

  Computes the moment when the upper limb of the Sun appears to cross the
  horizon (or the configured `:solar_elevation` threshold) using solar
  positions derived from the JPL DE440s ephemeris.

  ### Arguments

  * `location` is a `{longitude, latitude}` tuple, a `t:Geo.Point.t/0`,
    or a `t:Geo.PointZ.t/0`. Longitude and latitude are in degrees
    (west/south negative).

  * `moment` is a moment (float Gregorian days since 0000-01-01)
    representing UTC midnight of the requested date. Use
    `Astro.Time.date_time_to_moment/1` to convert from a `Date` or
    `DateTime`.

  * `options` is a keyword list of options.

  ### Options

  * `:solar_elevation` — the type of sunrise to compute:
    * `:geometric` (default) — standard sunrise where the upper limb of
      the Sun appears to touch the horizon (zenith 90°50′, accounting for
      34′ standard refraction + 16′ solar semi-diameter)
    * `:civil` — centre of Sun 6° below the horizon (civil twilight
      boundary)
    * `:nautical` — centre of Sun 12° below the horizon (nautical
      twilight boundary)
    * `:astronomical` — centre of Sun 18° below the horizon
      (astronomical twilight boundary)
    * a number — custom zenith angle in degrees (90 = geometric
      horizon with no refraction or semi-diameter correction)

  * `:time_zone` — the time zone for the returned `DateTime`. The
    default is `:default` which resolves the time zone from the
    location. `:utc` returns UTC, or pass a time zone name string
    (e.g. `"America/New_York"`).

  * `:time_zone_database` — the module implementing the
    `Calendar.TimeZoneDatabase` behaviour. The default is `:configured`
    which uses the application's configured time zone database.

  * `:time_zone_resolver` — a 1-arity function that receives a
    `%Geo.Point{}` and returns `{:ok, time_zone_name}` or
    `{:error, reason}`. The default uses `TzWorld.timezone_at/1`
    if `:tz_world` is configured.

  ### Returns

  * `{:ok, datetime}` where `datetime` is a `t:DateTime.t/0` in the
    requested time zone.

  * `{:error, :no_time}` if there is no sunrise on the requested date
    at the given location (e.g. polar night or midnight sun).

  * `{:error, :time_zone_not_found}` if the requested time zone is
    unknown.

  * `{:error, :time_zone_not_resolved}` if the time zone cannot be
    resolved from the location.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~D[2019-12-04])
      iex> {:ok, sunrise} = Astro.Solar.SunRiseSet.sunrise({151.20666584, -33.8559799094}, moment, time_zone: :utc)
      iex> sunrise.hour
      18
      iex> sunrise.minute
      37

  """
  @spec sunrise(Astro.location(), number(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def sunrise(location, moment, options \\ []) when is_number(moment) do
    sun_event(location, moment, :rise, options)
  end

  @doc """
  Returns the sunset time for a given location and date.

  Computes the moment when the upper limb of the Sun appears to cross below
  the horizon (or the configured `:solar_elevation` threshold) using solar
  positions derived from the JPL DE440s ephemeris.

  ### Arguments

  * `location` is a `{longitude, latitude}` tuple, a `t:Geo.Point.t/0`,
    or a `t:Geo.PointZ.t/0`. Longitude and latitude are in degrees
    (west/south negative).

  * `moment` is a moment (float Gregorian days since 0000-01-01)
    representing UTC midnight of the requested date. Use
    `Astro.Time.date_time_to_moment/1` to convert from a `Date` or
    `DateTime`.

  * `options` is a keyword list of options.

  ### Options

  Accepts the same options as `sunrise/3`:

  * `:solar_elevation` — event threshold (default `:geometric`)
  * `:time_zone` — time zone for the result (default `:default`)
  * `:time_zone_database` — time zone database module (default `:configured`)
  * `:time_zone_resolver` — custom location-to-timezone resolver function

  ### Returns

  * `{:ok, datetime}` where `datetime` is a `t:DateTime.t/0` in the
    requested time zone.

  * `{:error, :no_time}` if there is no sunset on the requested date
    at the given location (e.g. polar night or midnight sun).

  * `{:error, :time_zone_not_found}` if the requested time zone is
    unknown.

  * `{:error, :time_zone_not_resolved}` if the time zone cannot be
    resolved from the location.

  ### Examples

      iex> moment = Astro.Time.date_time_to_moment(~D[2019-12-04])
      iex> {:ok, sunset} = Astro.Solar.SunRiseSet.sunset({151.20666584, -33.8559799094}, moment, time_zone: :utc)
      iex> sunset.hour
      8
      iex> sunset.minute
      53

  """
  @spec sunset(Astro.location(), number(), keyword()) ::
          {:ok, DateTime.t()} | {:error, atom()}
  def sunset(location, moment, options \\ []) when is_number(moment) do
    sun_event(location, moment, :set, options)
  end

  # ── Core ─────────────────────────────────────────────────────────────────────

  defp sun_event(location, moment, event, options) do
    %Geo.PointZ{coordinates: {lng, lat, _elev_m}} =
      Astro.Location.normalize_location(location)

    date = Date.from_gregorian_days(trunc(moment))
    h0 = h0_from_options(options)

    dt_midnight = Time.dynamical_time_from_moment(moment)
    dt_start = dt_midnight - @scan_pre_window_s
    dt_end = dt_start + @scan_window_s

    scan_pairs =
      Stream.iterate(dt_start, &(&1 + @scan_step_s))
      |> Stream.take_while(&(&1 <= dt_end))
      |> Enum.map(fn dynamical_time ->
        {dynamical_time, altitude_f(dynamical_time, lat, lng, h0)}
      end)

    brackets =
      scan_pairs
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.filter(fn [{_dt1, f1}, {_dt2, f2}] ->
        case event do
          :rise -> f1 < 0.0 and f2 >= 0.0
          :set -> f1 > 0.0 and f2 <= 0.0
        end
      end)

    result =
      Enum.find_value(brackets, fn [{dt_lo, f_lo}, {dt_hi, f_hi}] ->
        dt_event = bisect(dt_lo, f_lo, dt_hi, f_hi, lat, lng, h0, @bisect_max)
        {:ok, utc_dt} = Time.date_time_from_moment(Time.dynamical_time_to_moment(dt_event))

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

  # f(dynamical_time) = geometric_alt_centre(dynamical_time) − h0
  #
  # Event occurs at f = 0, i.e. when the Sun's geometric altitude equals h0.
  # Positive f: Sun above the event threshold.
  # Negative f: Sun below the event threshold.
  defp altitude_f(dynamical_time, lat, lng, h0) do
    {:ok, {ra, dec, _dist}} = Ephemeris.sun_position_dt(dynamical_time)

    gast = Coordinates.gast(dynamical_time)
    h = fmod(gast + lng - ra, 360.0)
    h = if h > 180.0, do: h - 360.0, else: h

    sin_alt =
      sin_d(lat) * sin_d(dec) +
        cos_d(lat) * cos_d(dec) * cos_d(h)

    alt = :math.asin(sin_alt) * 180.0 / :math.pi()
    alt - h0
  end

  # ── Bisection ────────────────────────────────────────────────────────────────

  defp bisect(dt_lo, _f_lo, dt_hi, _f_hi, _lat, _lng, _h0, 0),
    do: (dt_lo + dt_hi) / 2.0

  defp bisect(dt_lo, f_lo, dt_hi, f_hi, lat, lng, h0, iters) do
    if dt_hi - dt_lo <= @bisect_tol_s do
      (dt_lo + dt_hi) / 2.0
    else
      dt_mid = (dt_lo + dt_hi) / 2.0
      f_mid = altitude_f(dt_mid, lat, lng, h0)

      if f_lo * f_mid <= 0.0 do
        bisect(dt_lo, f_lo, dt_mid, f_mid, lat, lng, h0, iters - 1)
      else
        bisect(dt_mid, f_mid, dt_hi, f_hi, lat, lng, h0, iters - 1)
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
end
