defmodule Mix.Tasks.Astro.DownloadEphemeris do
  @shortdoc "Downloads the JPL DE440s ephemeris file to the application priv directory"

  @moduledoc """
  Downloads the JPL DE440s ephemeris file (`de440s.bsp`) from NASA's
  NAIF server and places it in the application's `priv` directory.

  The file is approximately 32 MB and contains Chebyshev polynomial
  segments for the Sun, Moon, Earth and Earth-Moon Barycenter used
  by the scan-and-bisect rise/set algorithms.

  ## Usage

      $ mix astro.download_ephemeris

  If the file already exists, you will be prompted before overwriting.
  Use the `--force` flag to skip the prompt:

      $ mix astro.download_ephemeris --force

  To download to a custom location instead of the default `priv` directory:

      $ mix astro.download_ephemeris --dest /path/to/de440s.bsp

  When using `--dest`, the target directory must already exist. You will
  also need to configure the ephemeris path in your `runtime.exs`:

      config :astro, ephemeris: "/path/to/de440s.bsp"

  """

  use Mix.Task

  @url "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp"
  @filename "de440s.bsp"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [force: :boolean, dest: :string])
    force? = Keyword.get(opts, :force, false)
    custom_dest = Keyword.get(opts, :dest)

    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)

    dest = resolve_dest(custom_dest)

    if File.exists?(dest) and not force? do
      Mix.shell().info("#{Path.basename(dest)} already exists at #{dest}")

      unless Mix.shell().yes?("Overwrite?") do
        Mix.shell().info("Download cancelled.")
        exit(:normal)
      end
    end

    Mix.shell().info("Downloading #{@filename} from #{@url} ...")
    Mix.shell().info("This file is approximately 32 MB and may take a minute.")

    case download(String.to_charlist(@url)) do
      {:ok, body} ->
        File.write!(dest, body)
        size_mb = Float.round(byte_size(body) / (1024 * 1024), 1)
        Mix.shell().info("Saved #{size_mb} MB to #{dest}")

        if custom_dest do
          Mix.shell().info("""

          Remember to configure the ephemeris path in your runtime.exs:

              config :astro, ephemeris: #{inspect(dest)}
          """)
        end

      {:error, reason} ->
        Mix.raise("Failed to download #{@filename}: #{inspect(reason)}")
    end
  end

  defp resolve_dest(nil) do
    priv_dir = :code.priv_dir(:astro) |> to_string()

    unless File.dir?(priv_dir) do
      Mix.shell().info("Creating #{priv_dir}")
      File.mkdir_p!(priv_dir)
    end

    Path.join(priv_dir, @filename)
  end

  defp resolve_dest(custom_path) do
    dir = Path.dirname(custom_path)

    unless File.dir?(dir) do
      Mix.raise("Target directory does not exist: #{dir}")
    end

    custom_path
  end

  defp download(url) do
    ssl_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:get, {url, []}, ssl_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
