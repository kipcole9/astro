defmodule Astro.UmmAlQura do
  @moduledoc """
  Provides exact Gregorian dates for the first day of each Hijri month
  according to the official Umm al-Qura calendar published by the
  King Abdulaziz City for Science and Technology (KACST).

  ## Approach

  Rather than deriving first-day dates by re-applying the astronomical
  observation rules at runtime (which introduces accumulated rounding errors
  and can diverge from the published tables by ±1 day), this module embeds
  the complete official dataset at compile time.  Every call to
  `first_day_of_month/2` is therefore an O(1) map lookup with no
  floating-point computation.

  ## Coverage

  The embedded dataset spans **1 Muharram 1356 AH (14 March 1937 CE)** through
  approximately **1501 AH**, covering the full range of the published tables.

  ## Reference

  - R.H. van Gent, "The Umm al-Qura Calendar of Saudi Arabia":
    <https://webspace.science.uu.nl/~gent0113/islam/ummalqura.htm>
  - KACST published Umm al-Qura tables

  ## Example

      iex> Astro.UmmAlQura.first_day_of_month(1446, 9)
      {:ok, ~D[2025-03-01]}   # 1 Ramaḍān 1446 AH

      iex> Astro.UmmAlQura.first_day_of_month(1392, 1)
      {:ok, ~D[1972-03-16]}   # 1 Muharram 1392 AH

  """

  alias Astro.UmmAlQura.ReferenceData

  # Build a compile-time O(1) lookup map from {hijri_year, hijri_month} → Date.t().
  #
  # Because ReferenceData has no dependency on this module, the Mix compiler
  # guarantees it is compiled first, making the function call below safe to
  # evaluate at compile time as a module attribute.
  @lookup_table ReferenceData.umm_al_qura_dates()
                |> Map.new(fn %{hijri_year: y, hijri_month: m, gregorian: d} ->
                  {{y, m}, d}
                end)

  @doc """
  Returns the Gregorian date of the 1st day of the Hijri month given by
  `hijri_year` and `hijri_month`.

  `hijri_month` must be an integer in `1..12`, where 1 = Muharram and
  12 = Dhū al-Ḥijjah.

  Returns `{:ok, %Date{}}` when the requested month falls within the
  official dataset (1356–≈1501 AH), or `{:error, :date_not_in_official_table}`
  otherwise.

  ## Examples

      iex> Astro.UmmAlQura.first_day_of_month(1446, 9)
      {:ok, ~D[2025-03-01]}

      iex> Astro.UmmAlQura.first_day_of_month(1423, 1)
      {:ok, ~D[2002-03-15]}

      iex> Astro.UmmAlQura.first_day_of_month(9999, 1)
      {:error, :date_not_in_official_table}

  """
  @spec first_day_of_month(pos_integer(), 1..12) ::
          {:ok, Date.t()} | {:error, :date_not_in_official_table}

  def first_day_of_month(hijri_year, hijri_month)
      when is_integer(hijri_year) and is_integer(hijri_month) and hijri_month in 1..12 do
    case Map.get(@lookup_table, {hijri_year, hijri_month}) do
      nil  -> {:error, :date_not_in_official_table}
      date -> {:ok, date}
    end
  end

  def first_day_of_month(_year, _month),
    do: {:error, :date_not_in_official_table}
end
