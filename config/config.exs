import Config

config :logger,
  level: :debug,
  truncate: 4096

config :elixir,
  :time_zone_database, Tzdata.TimeZoneDatabase

# config :elixir,
#   :time_zone_database, Tz.TimeZoneDatabase