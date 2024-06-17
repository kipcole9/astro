ExUnit.start()

if Code.ensure_loaded?(TzWorld) do
  Astro.Supervisor.start()
end
