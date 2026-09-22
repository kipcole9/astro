defmodule Astro.GuidesTest do
  use ExUnit.Case, async: true

  # The guides are doctested so their examples cannot drift from the
  # library the way untested documentation does.
  doctest_file("README.md")
  doctest_file("guides/getting_started.md")
  doctest_file("guides/solar.md")
  doctest_file("guides/lunar.md")
end
