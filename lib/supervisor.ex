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

  `TzWorld.Backend.SpatialIndex` is used. It is tz_world's
  recommended and default backend, resolving a coordinate against an
  R-tree held in `:persistent_term` without passing through a
  GenServer mailbox.

  """
  if Code.ensure_loaded?(TzWorld.Backend.SpatialIndex) do
    @tz_world_backend [TzWorld.Backend.SpatialIndex]
  else
    @tz_world_backend []
  end

  def start_link(_type \\ [], _args \\ []) do
    opts = [strategy: :one_for_one, name: Astro.Supervisor]
    Supervisor.start_link(@tz_world_backend, opts)
  end
end
