# Only used to fetch and build the postgrex driver (and its deps), the ORM
# itself is written in efene and built with the efene compiler, see Makefile.
defmodule EfeneOrm.MixProject do
  use Mix.Project

  def project do
    [app: :efene_orm, version: "0.1.0", elixir: "~> 1.15", deps: deps()]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [{:postgrex, "~> 0.19"}]
  end
end
