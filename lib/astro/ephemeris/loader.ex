defmodule Astro.Ephemeris.Loader do
  @moduledoc false

  # Loads the JPL ephemeris Astro computes positions from into
  # `:persistent_term`, once. Astro's application does this as it starts,
  # and `Astro.Supervisor` does it when an application supervises Astro
  # itself and does not start the `:astro` application, so either way the
  # ephemeris is loaded before the first position is asked for.

  alias Astro.Ephemeris.{Downloader, Kernel}

  @doc false
  # Loads the configured ephemeris unless one is loaded already, which is
  # then kept: a second call, as when an application lists `Astro.Supervisor`
  # while the `:astro` application also runs, loads nothing.
  @spec ensure_loaded() :: :ok | {:error, String.t()}
  def ensure_loaded do
    if loaded?(), do: :ok, else: load()
  end

  defp loaded?, do: :persistent_term.get(Kernel.ephemeris_key(), nil) != nil

  defp load do
    case ephemeris_kernel() do
      {:ok, kernel} -> :persistent_term.put(Kernel.ephemeris_key(), kernel)
      {:error, reason} -> {:error, ephemeris_error(reason)}
    end
  end

  defp ephemeris_kernel do
    with {:ok, path} <- Downloader.ensure_ephemeris(Downloader.ephemeris_path()) do
      Kernel.load(path)
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

           #{Downloader.ephemeris_path()}

      2. Or configure an explicit path in your application config:

           config :astro, ephemeris: "/path/to/de440s.bsp"

      3. Or override the download URL (e.g. an internal mirror):

           config :astro, ephemeris_url: "https://example.com/de440s.bsp"
    """
  end
end
