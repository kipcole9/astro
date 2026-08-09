defmodule Mix.Tasks.Astro.BuildEphemeris do
  @shortdoc "Builds a compact ephemeris by extracting only the segments Astro uses"

  @moduledoc """
  Builds a compact ephemeris kernel from JPL's `de440s.bsp`.

  The full DE440s kernel is ~31 MB because it carries every planetary
  barycenter over 1849–2150. `Astro` uses only the Sun, Moon and Earth,
  so this task extracts those segments over a chosen span of years and
  writes a much smaller DAF/SPK file. Over the default 1900–2100 window
  the result is about 8.4 MB.

  Extraction is lossless: the original Chebyshev coefficients are copied
  verbatim, so results computed from the compact file are identical to
  those computed from the full kernel for any date it covers.

  This task generates the ephemeris that ships with the library. Run it
  to regenerate that file, or to build one covering a different span.

  ## Usage

      $ mix astro.build_ephemeris

  The full kernel is downloaded to a temporary file, subset, and then
  discarded. To subset a copy you already have, avoiding the download:

      $ mix astro.build_ephemeris --source priv/de440s.bsp

  To cover a different span of years:

      $ mix astro.build_ephemeris --from 1900 --to 2200

  Cost is roughly 42 KB per year of coverage. The window is widened to
  the enclosing Chebyshev record boundary, so the requested span is
  always fully covered.

  ## Options

    * `--source` — path to an existing full kernel. Downloads one to a
      temporary file if omitted.

    * `--dest` — output path. Defaults to `priv/de440s-astro.bsp`.

    * `--from` — first year to cover. Defaults to `1950`.

    * `--to` — last year to cover. Defaults to `2100`.

    * `--keep-earth` — retain the Earth→EMB segment rather than
      reconstructing it at runtime. Roughly doubles the output size.
      See `Astro.Ephemeris.Subset` for why it is redundant.

    * `--force` — overwrite the output file without prompting.

  """

  use Mix.Task

  alias Astro.Ephemeris.{Downloader, Subset}

  @default_dest "priv/de440s-astro.bsp"
  @default_from 1900
  @default_to 2100

  @switches [
    source: :string,
    dest: :string,
    from: :integer,
    to: :integer,
    keep_earth: :boolean,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {options, _, _} = OptionParser.parse(args, strict: @switches)

    dest = Keyword.get(options, :dest, @default_dest)
    from = Keyword.get(options, :from, @default_from)
    to = Keyword.get(options, :to, @default_to)

    if to < from do
      Mix.raise("--to (#{to}) must not be earlier than --from (#{from})")
    end

    confirm_overwrite!(dest, Keyword.get(options, :force, false))

    bodies =
      if Keyword.get(options, :keep_earth, false) do
        Subset.default_bodies() ++ [{399, 3}]
      else
        Subset.default_bodies()
      end

    {source, temporary?} = source_kernel(Keyword.get(options, :source))

    try do
      Mix.shell().info("Extracting #{from}-#{to} from #{source} ...")

      case Subset.extract(source, dest, bodies: bodies, from: from, to: to) do
        {:ok, report} ->
          report(report, source)

        {:error, reason} ->
          Mix.raise("Could not build ephemeris: #{inspect(reason)}")
      end
    after
      if temporary?, do: File.rm(source)
    end
  end

  defp confirm_overwrite!(dest, force?) do
    if File.exists?(dest) and not force? do
      Mix.shell().info("#{dest} already exists.")

      unless Mix.shell().yes?("Overwrite?") do
        Mix.shell().info("Build cancelled.")
        exit(:normal)
      end
    end
  end

  defp source_kernel(nil) do
    path = Path.join(System.tmp_dir!(), "astro-de440s-#{System.unique_integer([:positive])}.bsp")

    Mix.shell().info("Downloading the full DE440s kernel (~31 MB) ...")

    case Downloader.download(path) do
      {:ok, ^path} ->
        {path, true}

      {:error, reason} ->
        Mix.raise("Could not download the source kernel: #{inspect(reason)}")
    end
  end

  defp source_kernel(path) do
    unless File.exists?(path) do
      Mix.raise("Source kernel does not exist: #{path}")
    end

    {path, false}
  end

  defp report(report, source) do
    {first, last} = report.coverage
    source_mb = megabytes(File.stat!(source).size)
    dest_mb = megabytes(report.bytes)

    Mix.shell().info("""

    Wrote #{report.path}
      size      #{dest_mb} MB (from #{source_mb} MB)
      covers    #{first}-#{last}
      segments  #{Enum.map_join(report.segments, ", ", fn {t, c} -> "#{t}->#{c}" end)}
    """)
  end

  defp megabytes(bytes) do
    Float.round(bytes / (1024 * 1024), 2)
  end
end
