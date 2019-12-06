defmodule Astro.Test.Solstice do
  use ExUnit.Case

  for [year, month, day, [hour, minute]] <- Astro.TestData.solstice() do
    test "Solstice for #{String.capitalize(Atom.to_string(month))}, #{year}" do
      {:ok, solstice} = Astro.solstice(unquote(year), unquote(month))
      assert solstice.day == unquote(day)
      assert solstice.hour == unquote(hour)
      assert_in_delta solstice.minute, unquote(minute), 2
    end
  end

end