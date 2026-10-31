defmodule Astro.Saros do
  @moduledoc """
  The Saros series of an eclipse, numbered as NASA's eclipse catalogues
  number them.

  Eclipses recur after a *saros* of 223 lunations, 18 years 11 days and
  about 8 hours: the Sun, the Moon and the Moon's node return to nearly
  the same arrangement, so an eclipse is followed by a similar one 223
  lunations later. The eclipses a saros apart form a *Saros series*,
  which begins with small partial eclipses near one pole, runs through
  central eclipses that move across the Earth and ends with partial
  eclipses near the other pole: 69 to 87 eclipses over 1,226 to 1,550
  years.

  An *inex* of 358 lunations, about 29 years, links neighbouring
  series: the eclipse an inex after an eclipse of series `s` belongs to
  series `s + 1`. So every eclipse of series `s` falls at a lunation `n`
  (`Astro.Lunar.lunation_at/1`) with `n ≡ 358 s + c (mod 223)` for a
  constant `c`, one for solar eclipses and another for lunar, and the
  series follows from the lunation to within a multiple of 223:
  `s ≡ 38 (n − c) (mod 223)`, 38 being the inverse of 358 modulo 223.

  The series in progress at a time form a band about 50 numbers wide,
  which moves on by about one number every 30 years, so the multiple of
  223 is the one that puts the series nearest a straight-line estimate
  of the band from the lunation. The numbering is G. van den Bergh's,
  from his Saros–Inex panorama, as NASA's catalogues use it. The
  constants and the band are fitted to the catalogues and reproduce
  the series of every eclipse in six of their centuries between −999
  and 3000; far beyond them the numbering continues by the same rule.

  ### Reference

  * G. van den Bergh, *Periodicity and Variation of Solar (and Lunar)
    Eclipses* (1955).

  * Fred Espenak, [Eclipses and the Saros](https://eclipse.gsfc.nasa.gov/SEsaros/SEsaros.html),
    NASA Goddard Space Flight Center.

  """

  # A saros and an inex in lunations, and the inverse of an inex modulo
  # a saros: 358 × 38 = 13,604 = 61 × 223 + 1.
  @saros_lunations 223
  @inex_inverse 38

  @doc """
  Returns the Saros series of the eclipse of a lunation.

  ### Arguments

  * `lunation` is the lunation of the eclipse, as
    `Astro.Lunar.lunation_at/1` numbers it: for a solar eclipse the
    lunation that begins with its new moon, and for a lunar eclipse the
    lunation in which its full moon falls.

  * `kind` is `:solar` or `:lunar`.

  ### Returns

  * The Saros series number, an integer.

  ### Examples

  The total solar eclipse of 8 April 2024 is in lunation 300 and the
  total lunar eclipse of 14 March 2025 in lunation 311:

      iex> Astro.Saros.series(300, :solar)
      139

      iex> Astro.Saros.series(311, :lunar)
      123

  """
  @spec series(integer(), :solar | :lunar) :: integer()
  def series(lunation, kind) do
    {residue, slope, intercept} = band(kind)
    remainder = Integer.mod(residue + @inex_inverse * lunation, @saros_lunations)
    estimate = slope * lunation + intercept

    remainder + @saros_lunations * round((estimate - remainder) / @saros_lunations)
  end

  # The residue of the series modulo a saros at lunation 0, and the
  # straight line through the band of series in progress, fitted to
  # NASA's catalogues.
  defp band(:solar) do
    {112, 0.00259060, 136.394}
  end

  defp band(:lunar) do
    {124, 0.00264567, 128.939}
  end
end
