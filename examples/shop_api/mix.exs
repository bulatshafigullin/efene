# Only used to fetch and build the dependencies (postgrex and cowboy), the API
# is written in efene and built with the efene compiler, see Makefile.
defmodule ShopApi.MixProject do
  use Mix.Project

  def project do
    [app: :shop_api, version: "0.1.0", elixir: "~> 1.15", deps: deps()]
  end

  def application do
    [extra_applications: [:logger, :inets]]
  end

  defp deps do
    [{:postgrex, "~> 0.19"}, {:cowboy, "~> 2.12"}]
  end
end
