defmodule Astro.Application do
  use Application

  @default_ephemeris "priv/de440s.bsp"

  def start(_type, _args) do
    ephemeris_path = Application.get_env(:astro, :ephemeris, @default_ephemeris)
    {:ok, kernel} = Astro.Ephemeris.Kernel.load(ephemeris_path)
    :ok = :persistent_term.put(Astro.Ephemeris.Kernel.ephemeris_key(), kernel)

    Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
  end
end
