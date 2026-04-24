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
  if Code.ensure_loaded?(TzWorld.Backend.DetsWithIndexCache) do
    @tz_world_backend [TzWorld.Backend.DetsWithIndexCache]
  else
    @tz_world_backend []
  end

  def start_link(_type \\ [], _args \\ []) do
    opts = [strategy: :one_for_one, name: Astro.Supervisor]
    Supervisor.start_link(@tz_world_backend, opts)
  end
end
