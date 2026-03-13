defmodule Astro.Application do
  @moduledoc false

  use Application

  @default_ephemeris "de440s.bsp"

  def start(_type, _args) do
    priv_dir = :code.priv_dir(:astro)
    default_ephemeris = Path.join(priv_dir, @default_ephemeris)

    ephemeris_path = Application.get_env(:astro, :ephemeris, default_ephemeris)
    {:ok, kernel} = Astro.Ephemeris.Kernel.load(ephemeris_path)
    :ok = :persistent_term.put(Astro.Ephemeris.Kernel.ephemeris_key(), kernel)

    Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
  end
end
