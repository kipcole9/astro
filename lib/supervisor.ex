defmodule Astro.Supervisor do
  @moduledoc """
  Provides a supervision tree under which
  the required TzWorld backend server can
  be started.

  """

  @doc """
  Starts a TzWorld backend module that
  manages the time zone data required for
  Astro to operate.

  The backend process is started under a
  supervisor called Astro.Supervisor.

  """
  def start_link(_type \\ [], _args \\ []) do
    children =
      if Code.ensure_loaded?(TzWorld.Backend.DetsWithIndexCache) do
        [TzWorld.Backend.DetsWithIndexCache]
      else
        []
      end

    opts = [strategy: :one_for_one, name: Astro.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
