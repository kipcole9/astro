import Config

config :logger,
  level: :debug,
  truncate: 4096

# Astro is time zone database agnostic (any `Calendar.TimeZoneDatabase`
# implementation works); `tz` is used for local development and test.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
