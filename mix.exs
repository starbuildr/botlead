defmodule Botlead.MixProject do
  use Mix.Project

  def project do
    [
      app: :botlead,
      version: "0.3.2",
      elixir: "~> 1.18",
      description: "Elixir framework for writing and configuring chat bots",
      docs: [extras: ["README.md"]],
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def package do
    [
      name: :botlead,
      files: ["lib", "mix.exs"],
      maintainers: ["Vyacheslav Voronchuk"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/starbuildr/botlead"}
    ]
  end

  def application do
    [
      mod: {Botlead, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gen_router, "~> 0.1"},
      {:telegex, "~> 1.9.0-rc.0"},
      {:finch, "~> 0.19", only: [:dev, :test]},
      {:earmark, ">= 0.0.0", only: :dev},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:ex_machina, "~> 2.7", only: :test},
      {:exvcr, "~> 0.15", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/stub_modules", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
