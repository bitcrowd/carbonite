# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.Version do
  @moduledoc false

  @callback up(keyword()) :: :ok
  @callback down(keyword()) :: :ok

  defmacro __using__(_) do
    quote do
      import Carbonite.Migrations.Helper
      import Carbonite.Prefix

      @behaviour Carbonite.Migrations.Version
    end
  end
end
