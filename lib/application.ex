defmodule Astro.Supervisor do
  def start(_type \\ [], _args \\ []) do
    children = [
      TzWorld.Backend.DetsWithIndexCache
    ]

    opts = [strategy: :one_for_one, name: Astro.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
