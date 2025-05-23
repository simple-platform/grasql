defmodule GraSQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :grasql,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GraSQL.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:jason, "~> 1.4"},
      {:rustler, "0.36.1", runtime: false},
      {:typed_struct, "~> 0.3.0"},
      {:credo, "== 1.7.12", only: [:dev, :test], runtime: false},
      {:excoveralls, "0.18.5", only: :test},
      {:benchee, "== 1.4.0", only: [:dev, :test]},
      {:benchee_html, "== 1.0.1", only: [:dev, :test]},
      {:stream_data, "== 1.2.0", only: [:dev, :test]}
    ]
  end
end
