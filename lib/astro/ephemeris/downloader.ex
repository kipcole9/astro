defmodule Astro.Ephemeris.Downloader do
  @moduledoc """
  Downloads JPL DE-series SPK binary ephemeris files from NASA NAIF.

  The default ephemeris file (`de440s.bsp`, ~32 MB) is not bundled with
  the hex package. It is downloaded automatically at application start
  the first time `Astro` is run, and cached on disk for subsequent runs.

  ### Cache location

  By default the file is cached under the user cache directory as
  resolved by `:filename.basedir(:user_cache, "astro")`. The location
  can be overridden by setting the `:ephemeris` application environment
  key:

      config :astro,
        ephemeris: "/path/to/de440s.bsp"

  When the configured path already contains a valid ephemeris file no
  download is performed.

  ### Source URL

  The default download source is the NASA NAIF generic kernels archive:

      https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp

  This can be overridden by setting the `:ephemeris_url` application
  environment key (for example, when mirroring the file inside an
  air-gapped environment).

  """

  require Logger

  @default_url "https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp"
  @default_file "de440s.bsp"

  @doc """
  Returns the resolved ephemeris file path.

  Resolution order:

  * The `:ephemeris` application environment key, if set.

  * `priv/de440s.bsp` if it exists (used during library development
    and when running from a checkout).

  * The user cache directory as resolved by
    `:filename.basedir(:user_cache, "astro")`.

  ### Returns

  * A binary path string.

  """
  @spec ephemeris_path() :: String.t()
  def ephemeris_path do
    case Application.get_env(:astro, :ephemeris) do
      nil ->
        priv_path = Path.join(:code.priv_dir(:astro), @default_file)

        if File.exists?(priv_path) do
          priv_path
        else
          Path.join(cache_dir(), @default_file)
        end

      path when is_binary(path) ->
        path
    end
  end

  @doc """
  Ensures the ephemeris file is available on disk, downloading it if necessary.

  ### Arguments

  * `path` is the destination file path.

  ### Returns

  * `{:ok, path}` if the file already exists or was downloaded successfully.

  * `{:error, reason}` if the file is missing and the download failed.

  """
  @spec ensure_ephemeris(String.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_ephemeris(path) do
    if File.exists?(path) do
      {:ok, path}
    else
      download(path)
    end
  end

  @doc """
  Downloads the ephemeris file to `path`.

  The destination directory is created if it does not already exist.
  On HTTP error or network failure the partial file (if any) is removed.

  ### Arguments

  * `path` is the destination file path.

  ### Returns

  * `{:ok, path}` on success.

  * `{:error, reason}` if the download failed. `reason` is a tuple
    describing the failure, e.g. `{:http_status, 404}` or an `:httpc`
    error term.

  """
  @spec download(String.t()) :: {:ok, String.t()} | {:error, term()}
  def download(path) do
    url = Application.get_env(:astro, :ephemeris_url, @default_url)

    File.mkdir_p!(Path.dirname(path))

    Logger.info(
      "[Astro] Ephemeris file not found at #{path}. " <>
        "Downloading ~32 MB from #{url} (one-time)."
    )

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), []}

    http_options = [
      ssl: ssl_options(),
      timeout: 120_000,
      connect_timeout: 30_000
    ]

    options = [stream: String.to_charlist(path)]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, :saved_to_file} ->
        Logger.info("[Astro] Ephemeris saved to #{path}")
        {:ok, path}

      {:ok, {{_version, status, _phrase}, _headers, _body}} ->
        _ = File.rm(path)
        {:error, {:http_status, status}}

      {:error, reason} ->
        _ = File.rm(path)
        {:error, reason}
    end
  end

  defp cache_dir do
    case :filename.basedir(:user_cache, ~c"astro") do
      cache when is_list(cache) -> List.to_string(cache)
      cache when is_binary(cache) -> cache
    end
  end

  defp ssl_options do
    try do
      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 3,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    rescue
      _ -> [verify: :verify_none]
    catch
      _, _ -> [verify: :verify_none]
    end
  end
end
