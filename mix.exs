defmodule Astro.MixProject do
  use Mix.Project

  @version "0.5.0"

  def project do
    [
      app: :astro,
      name: "Astro",
      version: @version,
      elixir: "~> 1.8",
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
      extras: [
        "README.md",
        "LICENSE.md",
        "CHANGELOG.md"
      ],
      skip_undefined_reference_warnings_on: ["changelog"]
    ]
  end

  def aliases do
    []
  end

  def application do
    [
      mod: {Astro.Application, [strategy: :one_for_one]},
      extra_applications: [:hackney, :tzdata, :logger]
    ]
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache 2.0"],
      links: links(),
      files: [
        "lib",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
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
      {:tzdata, "~> 1.0"},
      {:tz_world, "~> 0.7"},
      {:geo, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:calcalc, path: "deps/calcalc"},
      {:ex_cldr_calendars, "~> 1.15"},
      {:ex_doc, "~> 0.19", only: [:dev, :release], runtime: false},
      {:dialyxir, "~> 1.0.0-rc", only: [:dev], runtime: false, optional: true}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
