defmodule Astro.MixProject do
  use Mix.Project

  @version "0.1.0"

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
        plt_add_apps: ~w(gettext inets jason mix plug sweet_xml)a
      ],
      compilers: Mix.compilers()
    ]
  end

  defp description do
    """
    Common Locale Data Repository (CLDR) functions for Elixir to localize and format numbers,
    dates, lists and units with support for over 500 locales for internationalized (i18n) and
    localized (L10N) applications.
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

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
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
      {:tz_world, "~> 0.2"},
      {:geo, "~> 3.0"},
      {:jason, "~> 1.0"},
      {:ex_doc, "~> 0.19", only: [:dev, :release], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "bench"]
  defp elixirc_paths(_), do: ["lib"]
end
