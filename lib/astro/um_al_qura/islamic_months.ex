defmodule Astro.UmmAlQura.MonthNames do
  @doc """
  Returns the name of the Hijri month for the given 1-based month number.
  """
  @spec month_name(1..12) :: String.t()
  def month_name(1),  do: "Muharram"
  def month_name(2),  do: "Safar"
  def month_name(3),  do: "Rabī' al-Awwal"
  def month_name(4),  do: "Rabī' al-Thānī"
  def month_name(5),  do: "Jumādā al-Ūlā"
  def month_name(6),  do: "Jumādā al-Ākhirah"
  def month_name(7),  do: "Rajab"
  def month_name(8),  do: "Sha'bān"
  def month_name(9),  do: "Ramaḍān"
  def month_name(10), do: "Shawwāl"
  def month_name(11), do: "Dhū al-Qa'dah"
  def month_name(12), do: "Dhū al-Ḥijjah"
end