defmodule Astro.Supervisor do
  @moduledoc """
  A supervisor for the time zone lookup Astro uses to report rise and set
  times in the local time zone of a location.

  When `:tz_world` is a dependency and nothing else in the application
  starts its backend, add this supervisor to the application's
  supervision tree:

      children = [
        Astro.Supervisor
      ]

      Supervisor.start_link(children, strategy: :one_for_one)

  An application can instead add `TzWorld.Backend.SpatialIndex` to its own
  tree, as the README describes.

  """

  if Code.ensure_loaded?(TzWorld.Backend.SpatialIndex) do
    @tz_world_backend [TzWorld.Backend.SpatialIndex]
  else
    @tz_world_backend []
  end

  @doc """
  Starts the supervisor and, when `:tz_world` is a dependency, its
  `TzWorld.Backend.SpatialIndex` backend.

  `TzWorld.Backend.SpatialIndex` is tz_world's recommended and default
  backend. It resolves a coordinate against an R-tree held in
  `:persistent_term`, without passing through a GenServer mailbox. The
  supervisor is registered as `Astro.Supervisor`.

  ### Arguments

  * `type` and `args` are ignored.

  ### Returns

  * `{:ok, pid}` once the supervisor and backend have started.

  * `{:error, reason}` if either could not be started.

  ### Examples

  In a script or a test helper that has no supervision tree:

      {:ok, _pid} = Astro.Supervisor.start_link()

  """
  def start_link(_type \\ [], _args \\ []) do
    options = [strategy: :one_for_one, name: Astro.Supervisor]
    Supervisor.start_link(@tz_world_backend, options)
  end

  @doc """
  Returns the specification to start `Astro.Supervisor` under another
  supervisor.

  ### Arguments

  * `options` is a keyword list of options.

  ### Options

  * There are none. `options` is accepted so the module can be listed as
    a child, and is otherwise ignored.

  ### Returns

  * A child specification map.

  ### Examples

      iex> Astro.Supervisor.child_spec([])
      %{id: Astro.Supervisor, start: {Astro.Supervisor, :start_link, []}, type: :supervisor}

  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(_options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, type: :supervisor}
  end
end
