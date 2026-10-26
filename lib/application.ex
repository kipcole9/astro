defmodule Astro.Application do
  @moduledoc false

  use Application

  # The application loads the ephemeris and runs no process of its own:
  # tz_world's backend, which rise and set times use, is started by the
  # application that wants it, directly or through `Astro.Supervisor`. An
  # application that does not start `:astro` lists `Astro.Supervisor`, which
  # loads the ephemeris too.
  @impl true
  def start(_type, _args) do
    with :ok <- Astro.Ephemeris.Loader.ensure_loaded() do
      Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
    end
  end
end
