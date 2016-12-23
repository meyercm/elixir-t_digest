defmodule TDigest.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @repo_url "https://github.com/meyercm/sig_auth"

  def project do
    [app: :t_digest,
     version: @version,
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     package: hex_package,
     description: "Elixir native implementation of Dunning's t-digests."
   ]
  end

  defp hex_package do
    [maintainers: ["Chris Meyer"],
     licenses: ["MIT"],
     links: %{"GitHub" => @repo_url}]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [
      {:shorter_maps, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev},
    ]
  end
end
