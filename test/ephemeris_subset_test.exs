defmodule Astro.Ephemeris.SubsetTest do
  use ExUnit.Case, async: false

  alias Astro.Ephemeris.{Kernel, Subset}

  doctest Astro.Ephemeris.Subset

  # The bundled ephemeris is present in every checkout and every hex install,
  # so it serves as the source kernel for these tests. Subsetting a subset
  # exercises the same code path as subsetting the full JPL file.
  setup_all do
    source = Path.join(to_string(:code.priv_dir(:astro)), "de440s-astro.bsp")

    unless File.exists?(source) do
      raise "expected #{source}; run `mix astro.build_ephemeris` to generate it"
    end

    {:ok, kernel} = Kernel.load(source)
    %{source: source, kernel: kernel}
  end

  setup do
    saved = :persistent_term.get(Kernel.ephemeris_key(), nil)

    on_exit(fn ->
      if saved, do: :persistent_term.put(Kernel.ephemeris_key(), saved)
    end)

    :ok
  end

  defp unique_dest do
    Path.join(System.tmp_dir!(), "astro-subset-#{System.unique_integer([:positive])}.bsp")
  end

  describe "default_bodies/0" do
    test "omits Earth->EMB, which is reconstructed at runtime" do
      refute {399, 3} in Subset.default_bodies()
      assert {301, 3} in Subset.default_bodies()
    end
  end

  describe "extract/3" do
    test "writes a file the kernel parser can load", %{source: source} do
      dest = unique_dest()

      assert {:ok, report} = Subset.extract(source, dest, from: 2000, to: 2020)
      assert report.path == dest
      assert File.exists?(dest)

      assert {:ok, kernel} = Kernel.load(dest)
      assert length(kernel.segments) == length(Subset.default_bodies())

      File.rm(dest)
    end

    test "produces a smaller file than its source", %{source: source} do
      dest = unique_dest()

      assert {:ok, report} = Subset.extract(source, dest, from: 2000, to: 2020)
      assert report.bytes < File.stat!(source).size

      File.rm(dest)
    end

    test "covers at least the requested window", %{source: source} do
      dest = unique_dest()

      assert {:ok, report} = Subset.extract(source, dest, from: 1990, to: 2010)
      {first, last} = report.coverage

      # The window is widened to the enclosing record boundary, never narrowed.
      assert first <= 1990
      assert last >= 2010

      File.rm(dest)
    end

    test "copies coefficients verbatim, giving identical positions", %{
      source: source,
      kernel: full
    } do
      dest = unique_dest()
      assert {:ok, _report} = Subset.extract(source, dest, from: 2000, to: 2020)
      {:ok, subset} = Kernel.load(dest)

      # 2000-01-01 through 2020, sampled every ~2 years.
      times = for years <- 0..20//2, do: years * 3.15576e7

      for {target, centre} <- Subset.default_bodies(), time <- times do
        :persistent_term.put(Kernel.ephemeris_key(), full)
        {:ok, from_full} = Kernel.find_segment(target, centre, time)
        expected = Kernel.position(from_full, time)

        :persistent_term.put(Kernel.ephemeris_key(), subset)
        {:ok, from_subset} = Kernel.find_segment(target, centre, time)
        actual = Kernel.position(from_subset, time)

        assert actual == expected,
               "#{target}->#{centre} at #{time} differs: #{inspect(actual)} vs #{inspect(expected)}"
      end

      File.rm(dest)
    end

    test "returns an error for a body pair the source does not carry", %{source: source} do
      dest = unique_dest()

      assert {:error, {:segment_not_found, {599, 0}}} =
               Subset.extract(source, dest, bodies: [{599, 0}])

      refute File.exists?(dest)
    end

    test "returns an error when the window lies after the source coverage", %{source: source} do
      dest = unique_dest()

      assert {:error, {:empty_window, _bodies}} =
               Subset.extract(source, dest, from: 2500, to: 2600)

      refute File.exists?(dest)
    end

    test "returns an error when the window lies before the source coverage", %{source: source} do
      dest = unique_dest()

      assert {:error, {:empty_window, _bodies}} =
               Subset.extract(source, dest, from: 1600, to: 1700)

      refute File.exists?(dest)
    end

    test "returns an error when the source is not a DAF/SPK file" do
      source = unique_dest()
      File.write!(source, "definitely not an ephemeris")

      assert {:error, :not_daf_spk} = Subset.extract(source, unique_dest())

      File.rm(source)
    end
  end

  describe "Earth->EMB reconstruction" do
    test "is derived when the segment is absent", %{kernel: kernel} do
      :persistent_term.put(Kernel.ephemeris_key(), kernel)

      refute Enum.any?(kernel.segments, &(&1.target == 399 and &1.centre == 3))
      assert {:ok, segment} = Kernel.find_segment(399, 3)
      assert Map.has_key?(segment, :scale)
    end

    test "is the exact scalar multiple of Moon->EMB required by the barycenter",
         %{kernel: kernel} do
      :persistent_term.put(Kernel.ephemeris_key(), kernel)

      # Earth→EMB = -(1 / EMRAT) x Moon→EMB, EMRAT = 81.3005682214972154 for DE440.
      emrat = 81.3005682214972154

      {:ok, moon} = Kernel.find_segment(301, 3)
      {:ok, earth} = Kernel.find_segment(399, 3)

      for years <- 0..20//5 do
        time = years * 3.15576e7
        {mx, my, mz} = Kernel.position(moon, time)
        {ex, ey, ez} = Kernel.position(earth, time)

        assert_in_delta ex, -mx / emrat, abs(mx) * 1.0e-12
        assert_in_delta ey, -my / emrat, abs(my) * 1.0e-12
        assert_in_delta ez, -mz / emrat, abs(mz) * 1.0e-12
      end
    end

    test "respects the time span of the segment it is derived from", %{kernel: kernel} do
      :persistent_term.put(Kernel.ephemeris_key(), kernel)

      # Well outside the bundled 1900-2100 coverage.
      assert {:error, :not_found} = Kernel.find_segment(399, 3, 1.0e10)
    end

    test "is not applied to bodies other than Earth->EMB", %{kernel: kernel} do
      :persistent_term.put(Kernel.ephemeris_key(), kernel)

      assert {:error, :not_found} = Kernel.find_segment(599, 0)
      assert {:error, :not_found} = Kernel.find_segment(399, 0)
    end
  end
end
