# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite do
  @readme Path.join([__DIR__, "../README.md"])
  @external_resource @readme

  @moduledoc @readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @moduledoc since: "0.1.0"

  @doc "Returns the default audit trail prefix."
  @doc since: "0.1.0"
  @spec default_prefix() :: binary()
  def default_prefix, do: "carbonite_default"
end
