import Config

config :logger,
  level: :debug,
  truncate: 4096

# Astro is time zone database agnostic (any `Calendar.TimeZoneDatabase`
# implementation works); `tz` is used for local development and test.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# CI points tz_world's data directory at a stable, cacheable location so the
# ~95 MB timezone archive is fetched once rather than once per matrix entry.
# Left unset locally, where tz_world's default (the dep's priv directory under
# _build) applies.
if data_dir = System.get_env("TZ_WORLD_DATA_DIR") do
  config :tz_world, data_dir: data_dir
end
