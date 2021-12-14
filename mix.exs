defmodule Botlead.MixProject do
  use Mix.Project

  def project do
    [
      app: :botlead,
      version: "0.2.1",
      elixir: "~> 1.9",
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
      {:nadia, "~> 0.4.2"},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:ex_machina, "~> 2.2", only: :test},
      {:exvcr, "~> 0.10", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/stub_modules", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
