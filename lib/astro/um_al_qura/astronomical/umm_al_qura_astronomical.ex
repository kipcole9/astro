defmodule Astro.UmmAlQura.Astronomical do
  @moduledoc """
  Implements the Umm al-Qura calendar rule for determining the first day of each
  Hijri month.

  ### Rule (valid from 1 Muharram 1423 AH / 15 March 2002 CE onward)

  On the **29th day** of the current Hijri month, if **both** of the following
  conditions hold as observed from Mecca (21.4225° N, 39.8262° E), then the
  following day is the **1st day of the new Hijri month**:

    1. The geocentric conjunction (astronomical new moon) occurs **before** sunset
       in Mecca.
    2. Moonset in Mecca occurs **after** sunset in Mecca.

  If either condition fails, the current month is extended to 30 days.

  ### Reference

  - R.H. van Gent, "The Umm al-Qura Calendar of Saudi Arabia",
    https://webspace.science.uu.nl/~gent0113/islam/ummalqura_rules.htm
  - Wikipedia, "Islamic calendar"
  - Dershowitz & Reingold, *Calendrical Calculations* (4th ed.), Chapter 6

  """

  # Geographic constants – Great Mosque of Mecca (al-Masjid al-Ḥarām)
  @mecca_longitude 39.8262
  @mecca_latitude  21.4225
  @mecca_elevation 277.0

  @mecca_location {@mecca_longitude, @mecca_latitude, @mecca_elevation}

  # Hijri epoch seed for the mean-synodic-month approximation chain.
  #
  # This is NOT the classical tabular Hijri epoch (JDN 1_948_438 per
  # Dershowitz & Reingold), which counts whole days from 1 Muharram 1 AH.
  # Rather, it is a calibrated seed such that:
  #
  #     EPOCH + round(months_since_epoch × mean_synodic) + 28
  #
  # yields a JDN within ±1 day of the actual 29th day of each Hijri month,
  # as verified against the KACST reference dataset for 1423–1448 AH.
  #
  # Calibration basis: 1 Muharram 1423 AH = 2002-03-15 (Gregorian).
  @hijri_epoch_jdn 1_948_410

  # Mean length of a synodic month in days (used for seed estimates)
  @mean_synodic_month 29.530588853

  @doc """
  Calculates the Gregorian date of the 1st day of the Hijri month identified by
  `hijri_year` and `hijri_month` (1-based, 1 = Muharram … 12 = Dhū al-Ḥijja).

  Returns `{:ok, %Date{}}` on success, or `{:error, reason}` if any astronomical
  computation fails.

  ### Example

      iex> Astro.Lunar.UmmAlQura.first_day_of_month(1446, 9)
      {:ok, ~D[2025-03-01]}   # 1 Ramaḍān 1446 AH

  """
  @spec first_day_of_month(pos_integer(), 1..12) ::
          {:ok, Date.t()} | {:error, term()}
  def first_day_of_month(hijri_year, hijri_month)
      when is_integer(hijri_year) and hijri_year >= 1423
      and is_integer(hijri_month) and hijri_month in 1..12 do
    # Estimate the approximate Gregorian date of the 29th day of the given
    # Hijri month, then check the Umm al-Qura conditions.
    with {:ok, candidate_29} <- approximate_29th(hijri_year, hijri_month),
         {:ok, result}       <- apply_umm_al_qura_rule(candidate_29) do
      {:ok, result}
    end
  end

  def first_day_of_month(_year, _month),
    do: {:error, :rule_only_valid_from_1423_ah}

  @doc """
  Returns a map with the detailed astronomical data used in evaluating the
  Umm al-Qura rule for the given Gregorian date (which should be the 29th day
  of the current Hijri month).

  Returned map keys:
    - `:date`               – the candidate 29th Gregorian date
    - `:conjunction_utc`    – `DateTime` of geocentric conjunction (new moon)
    - `:sunset_mecca`       – `DateTime` of sunset in Mecca (UTC)
    - `:moonset_mecca`      – `DateTime` of moonset in Mecca (UTC), or `:no_time`
    - `:conjunction_before_sunset` – boolean
    - `:moonset_after_sunset`      – boolean
    - `:new_month_starts_next_day` – boolean (true iff both conditions are met)
  """
  @spec evaluate_conditions(Date.t()) :: {:ok, map()} | {:error, term()}
  def evaluate_conditions(%Date{} = date) do
    with {:ok, conjunction} <- Astro.date_time_new_moon_at_or_after(Date.add(date, -2)),
         {:ok, sunset_at_mecca} <- sunset_utc_at_mecca(date) do
      moonset_at_mecca =
        moonset_utc_at_mecca(date)

      conjunction_before_sunset? =
        DateTime.compare(conjunction, sunset_at_mecca) == :lt

      moonset_after_sunset? =
        case moonset_at_mecca do
          {:ok, moonset} ->
            DateTime.compare(moonset, sunset_at_mecca) == :gt
            && DateTime.to_date(moonset) == date
          {:error, :no_time} -> false
          _other -> false
        end

      moonset_value =
        case moonset_at_mecca do
          {:ok, ms} -> ms
          _         -> :no_time
        end

      result = %{
        date: date,
        conjunction_utc: conjunction,
        sunset_mecca: sunset_at_mecca,
        moonset_mecca: moonset_value,
        conjunction_before_sunset?: conjunction_before_sunset?,
        moonset_after_sunset?: moonset_after_sunset?,
        new_month_starts_next_day?: conjunction_before_sunset? and moonset_after_sunset?
      }

      {:ok, result}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Find the Gregorian date on which the Umm al-Qura rule must be evaluated for
  # the given Hijri month — i.e., the 29th day of the *previous* Hijri month,
  # which is the day the astronomical new moon occurs (in Mecca local time).
  #
  # Strategy: compute a rough JDN that lands within ±1 day of the target, then
  # anchor to the *actual* geocentric conjunction using
  # `Astro.date_time_new_moon_nearest/1`.  Converting the conjunction instant
  # to Mecca local time (permanently UTC+3) gives the exact Gregorian date on
  # which the rule is evaluated, with no dependence on `round/1` rounding.
  defp approximate_29th(hijri_year, hijri_month) do
    # 0-based count of months elapsed since 1 Muharram 1 AH.
    months_since_epoch =
      (hijri_year - 1) * 12 + (hijri_month - 1)

    # Rough JDN near the 29th of the previous Hijri month.  The ±1-day
    # rounding error from `round/1` is harmless — we use it only as a seed
    # for the conjunction search below.
    rough_jdn =
      @hijri_epoch_jdn + round(months_since_epoch * @mean_synodic_month) + 28

    with {:ok, rough_date} <- jdn_to_date(rough_jdn),
         # Use at_or_after(rough_date - 1) instead of date_time_new_moon_nearest.
         # Rationale: date_time_new_moon_nearest has a bug where both branches
         # call at_or_before, so it never looks forward.  By starting the search
         # one day before rough_date we reliably capture the conjunction even when
         # rough_jdn is ±1 day off (the rounding error we are trying to escape).
         {:ok, conjunction} <- Astro.date_time_new_moon_at_or_after(Date.add(rough_date, -2)) do
      # Convert the conjunction UTC instant to Mecca local time (UTC+3,
      # permanent — Mecca observes no DST).  The Mecca-local calendar date
      # of the conjunction is the 29th day of the old Hijri month, which is
      # precisely when the rule is applied.
      DateTime.shift_zone(conjunction, "Asia/Ryadh")
      #mecca_unix = DateTime.to_unix(conjunction) + 3 * 3600
      #{:ok, mecca_unix |> DateTime.from_unix!() |> DateTime.to_date()}
    end
  end

  # Apply the Umm al-Qura rule starting at the candidate 29th day.
  # If conditions are not met on day 29, the month has 30 days, so the new
  # month starts on day 31 (i.e. candidate + 2).
  defp apply_umm_al_qura_rule(candidate_29) do
    with {:ok, eval} <- evaluate_conditions(candidate_29) do
      first_day =
        if eval.new_month_starts_next_day? do
          Date.add(candidate_29, 1)
        else
          # Conditions not met — month is 30 days; new month starts on day 31.
          Date.add(candidate_29, 2)
        end

      {:ok, first_day}
    end
  end

  # Returns the UTC DateTime of sunset in Mecca on `date`.
  defp sunset_utc_at_mecca(date) do
    case Astro.sunset(@mecca_location, date) do
      {:ok, sunset_local} ->
        {:ok, DateTime.shift_zone!(sunset_local, "Etc/UTC")}

      error ->
        error
    end
  end

  # Returns the UTC DateTime of moonset in Mecca on `date`.
  defp moonset_utc_at_mecca(date) do
    case Astro.moonset(@mecca_location, date) do
      {:ok, moonset_local} ->
        {:ok, DateTime.shift_zone!(moonset_local, "Etc/UTC")}

      {:error, :no_time} = err ->
        err

      error ->
        error
    end
  end

  # Converts a Julian Day Number (integer) to a proleptic Gregorian Date.
  # Algorithm: Richards (2013), via Dershowitz & Reingold Appendix C.
  defp jdn_to_date(jdn) when is_integer(jdn) do
    f = jdn + 1_401 + div((div(4 * jdn + 274_277, 146_097) * 3), 4) - 38
    e = 4 * f + 3
    g = rem(e, 1_461) |> div(4)
    h = 5 * g + 2

    day   = rem(h, 153) |> div(5) |> Kernel.+(1)
    month = rem(div(h, 153) + 2, 12) + 1
    year  = div(e, 1_461) - 4_716 + div(14 - month, 12)

    Date.new(year, month, day)
  end
end