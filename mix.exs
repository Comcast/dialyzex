# Copyright 2017 Comcast Cable Communications Management, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Dialyzex.Mixfile do
  use Mix.Project

  def project do
    [
      app: :dialyzex,
      description: description(),
      version: "1.1.0",
      elixir: "~> 1.5",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      source_url: "https://github.com/Comcast/dialyzex",
      dialyzer_ignored_warnings: [
        # Ignore the explicit exit for returning non-zero when dialyzer
        # returns warnings
        {:warn_return_only_exit, {'lib/mix/tasks/dialyzer.ex', :_}, {:no_return, :_}}
      ]
    ]
  end

  def application do
    [extra_applications: [:mix]]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.17", only: :dev},
      {:credo, "~> 0.8.1", only: :dev}
    ]
  end

  defp description do
    "A dialyzer task for Mix with sensible defaults"
  end

  defp package do
    [
      licenses: ["Apache 2.0"],
      maintainers: ["Sean Cribbs", "Zeeshan Lakhani"],
      files: ["lib", "README*", "mix.exs", "CONTRIBUTING", "NOTICE", "LICENSE"],
      links: %{
        "Github" => "https://github.com/Comcast/dialyzex"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
