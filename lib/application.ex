defmodule Astro.Application do
  @moduledoc false

  use Application

  alias Astro.Ephemeris.{Downloader, Kernel}

  def start(_type, _args) do
    with {:ok, path} <- Downloader.ensure_ephemeris(Downloader.ephemeris_path()),
         {:ok, kernel} <- Kernel.load(path) do
      :ok = :persistent_term.put(Kernel.ephemeris_key(), kernel)
      Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
    else
      {:error, reason} ->
        {:error, ephemeris_error(reason)}
    end
  end

  defp ephemeris_error(reason) do
    """
    Astro could not load the JPL DE-series ephemeris file required for
    astronomical calculations.

    Reason: #{inspect(reason)}

    Astro attempts to download the default ephemeris file (de440s.bsp,
    ~32 MB) from NASA NAIF on first startup and cache it on disk. If
    the download failed (e.g. no network access), you can:

      1. Manually download the file from
         https://naif.jpl.nasa.gov/pub/naif/generic_kernels/spk/planets/de440s.bsp
         and save it to:

           #{Astro.Ephemeris.Downloader.ephemeris_path()}

      2. Or configure an explicit path in your application config:

           config :astro, ephemeris: "/path/to/de440s.bsp"

      3. Or override the download URL (e.g. an internal mirror):

           config :astro, ephemeris_url: "https://example.com/de440s.bsp"
    """
  end
end
