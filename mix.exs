defmodule Astro.MixProject do
  use Mix.Project

  @version "2.6.0"

  def project do
    [
      app: :astro,
      name: "Astro",
      version: @version,
      elixir: "~> 1.17",
      source_url: "https://github.com/kipcole9/astro",
      docs: docs(),
      description: description(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        ignore_warnings: ".dialyzer_ignore_warnings",
        plt_add_apps: ~w(inets jason geo mix)a
      ],
      compilers: Mix.compilers()
    ]
  end

  defp description do
    """
    Astronomical calculations in Elixir including sunrise, sunset, moonrise, moonset,
    equinox, solstice, moonphase and more.
    """
  end

  def docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      logo: "logo.png",
      formatters: ["html", "markdown"],
      extras: [
        "README.md",
        "guides/getting_started.md",
        "guides/solar.md",
        "guides/lunar.md",
        "LICENSE.md",
        "CHANGELOG.md",
        "rise_and_set_comparisons.md"
      ],
      groups_for_extras: [
        Guides: ~r"^guides/"
      ],
      groups_for_modules: [
        Solar: [
          Astro.Solar,
          Astro.Solar.SunRiseSet
        ],
        Lunar: [
          Astro.Lunar,
          Astro.Lunar.MoonRiseSet,
          Astro.Lunar.CrescentVisibility
        ],
        Ephemeris: [
          Astro.Ephemeris,
          Astro.Ephemeris.Kernel,
          Astro.Ephemeris.Downloader,
          Astro.Ephemeris.Subset
        ],
        "Mix tasks": [
          Mix.Tasks.Astro.DownloadEphemeris,
          Mix.Tasks.Astro.BuildEphemeris
        ],
        Internals: [
          Astro.Coordinates,
          Astro.Earth,
          Astro.Time,
          Astro.Supervisor
        ]
      ],
      skip_undefined_reference_warnings_on: ["changelog", "CHANGELOG.md"]
    ]
  end

  def aliases do
    []
  end

  def application do
    [
      mod: {Astro.Application, [strategy: :one_for_one]},
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:dev) do
    [:logger, :inets, :ssl, :public_key, :observer, :wx]
  end

  defp extra_applications(_) do
    [:logger, :inets, :ssl, :public_key]
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "guides",
        "priv/de440s-astro.bsp"
      ]
    ]
  end

  def links do
    %{
      "GitHub" => "https://github.com/kipcole9/astro",
      "Readme" => "https://github.com/kipcole9/astro/blob/v#{@version}/README.md",
      "Changelog" => "https://github.com/kipcole9/astro/blob/v#{@version}/CHANGELOG.md"
    }
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:geo, "~> 3.0"},

      # If using tz_world to resolve geo location to time zone
      {:tz_world, "~> 2.4", optional: true},

      # For Um Al-Qura tests
      {:table_rex, "~> 4.0", only: [:dev, :test]},
      {:tz, "~> 0.26", optional: true},
      {:ex_doc, "~> 0.19", only: [:dev, :release], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false, optional: true},
      {:stream_data, "~> 1.0", only: [:test]}
    ] ++ maybe_json_polyfill()
  end

  # json_polyfill (the EEP 68 :json module for OTP 26) is provided for
  # THIS project's own dev/test/CI only -- `only:` dependencies never
  # enter the hex package requirements. It is needed because `tz_world`
  # calls `:json`, which is built in only from OTP 27. It is deliberately
  # NOT a package dependency: OTP 26 consumers using tz_world add
  # {:json_polyfill, "~> 0.2 or ~> 1.0"} to their own deps. The
  # conditional avoids fetching it on OTP >= 27, where `:json` is built
  # in and the polyfill's own build fails.
  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0", only: [:dev, :test]}]
    end
  end

  defp elixirc_paths(:test), do: ["lib", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
