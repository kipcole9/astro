defmodule Astro.FirstVisibleCrescentTest do
  use ExUnit.Case, async: true

  @mecca {39.8262, 21.4225}
  @cairo {31.3, 30.1}

  defp visible?(location, date, method, options \\ []) do
    case Astro.new_visible_crescent(location, date, method, options) do
      {:ok, category} -> category in [:A, :B, :C]
      {:error, :no_sunset} -> false
    end
  end

  describe "first_visible_crescent_on_or_before/4 and first_visible_crescent_on_or_after/4" do
    test "find an evening the crescent is seen, after an evening it is not" do
      for method <- [:odeh, :yallop, :schaefer], location <- [@mecca, @cairo] do
        for date <- [~D[2024-03-15], ~D[2024-07-01], ~D[2024-12-20]] do
          {:ok, before} = Astro.first_visible_crescent_on_or_before(location, date, method)
          {:ok, later} = Astro.first_visible_crescent_on_or_after(location, date, method)

          assert Date.compare(before, date) in [:lt, :eq]
          assert Date.compare(later, date) in [:gt, :eq]
          assert visible?(location, before, method)
          refute visible?(location, Date.add(before, -1), method)
          assert visible?(location, later, method)
          refute visible?(location, Date.add(later, -1), method)
          assert Date.diff(later, before) in [0, 29, 30]
        end
      end
    end

    test "agree with each other on the evening of a first sighting" do
      {:ok, evening} = Astro.first_visible_crescent_on_or_before(@mecca, ~D[2024-12-20])

      assert Astro.first_visible_crescent_on_or_before(@mecca, evening) == {:ok, evening}
      assert Astro.first_visible_crescent_on_or_after(@mecca, evening) == {:ok, evening}

      assert {:ok, previous} =
               Astro.first_visible_crescent_on_or_before(@mecca, Date.add(evening, -1))

      assert Date.diff(evening, previous) in 29..30
    end

    test "count only the categories asked for" do
      {:ok, any} =
        Astro.first_visible_crescent_on_or_after(@mecca, ~D[2024-12-20], :odeh,
          visible: [:A, :B, :C]
        )

      {:ok, naked_eye} =
        Astro.first_visible_crescent_on_or_after(@mecca, ~D[2024-12-20], :odeh, visible: [:A])

      assert Date.compare(naked_eye, any) in [:gt, :eq]
    end

    test "take the evening of the local day with :utc_offset" do
      la = {-118.2437, 34.0522}

      {:ok, evening} =
        Astro.first_visible_crescent_on_or_after(la, ~D[2024-12-20], :odeh, utc_offset: -8 * 3600)

      {:ok, category} = Astro.new_visible_crescent(la, evening, :odeh, utc_offset: -8 * 3600)
      assert category in [:A, :B, :C]
    end

    test "answer outside the JPL ephemeris" do
      assert {:ok, %Date{year: 1000}} =
               Astro.first_visible_crescent_on_or_after(@cairo, ~D[1000-06-01])
    end

    test "return errors for invalid arguments" do
      assert Astro.first_visible_crescent_on_or_before(nil, ~D[2024-12-20]) ==
               {:error, :invalid_location}

      assert Astro.first_visible_crescent_on_or_before(@mecca, nil) == {:error, :invalid_date}

      assert Astro.first_visible_crescent_on_or_before(@mecca, ~D[2024-12-20], :odeh_2006) ==
               {:error, :invalid_method}

      assert Astro.first_visible_crescent_on_or_after(@mecca, ~D[2024-12-20], :odeh, nil) ==
               {:error, :invalid_options}

      assert Astro.first_visible_crescent_on_or_after(@mecca, ~D[2024-12-20], :odeh,
               visible: [:F]
             ) == {:error, :invalid_visible}

      assert Astro.first_visible_crescent_on_or_after(@mecca, ~D[2024-12-20], :odeh, visible: []) ==
               {:error, :invalid_visible}

      assert Astro.first_visible_crescent_on_or_after(@mecca, ~D[2024-12-20], :odeh,
               utc_offset: 99 * 3600
             ) == {:error, :invalid_utc_offset}

      {:ok, far} = Date.new(60_000, 1, 1)
      assert Astro.first_visible_crescent_on_or_after(@mecca, far) == {:error, :year_out_of_range}
    end
  end
end
