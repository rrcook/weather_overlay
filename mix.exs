defmodule NaplpsWriter.MixProject do
  use Mix.Project

  def project do
    [
      app: :naplps_writer,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WeatherInit, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:httpoison, "~> 1.8.2"},
      {:elixir_xml_to_map, "~> 3.1"},
      {:proj, "~> 0.2.3"},
      {:prodigy_objects, git: "https://github.com/rrcook/prodigy_objects.git"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
