# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.Version do
  @moduledoc false

  @callback up(keyword()) :: :ok
  @callback down(keyword()) :: :ok

  defmacro __using__(_) do
    quote do
      import Carbonite, only: [default_prefix: 0]
      import Carbonite.Migrations.Helper

      @behaviour Carbonite.Migrations.Version
    end
  end
end
