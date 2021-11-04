# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Migrations.V2 do
  @moduledoc false

  use Ecto.Migration
  use Carbonite.Migrations.Version

  @type prefix :: binary()

  @type up_option :: {:carbonite_prefix, prefix()}

  @impl true
  @spec up([up_option()]) :: :ok
  def up(opts) do
    prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    alter table("triggers", primary_key: false, prefix: prefix) do
      modify(:primary_key_columns, {:array, :string}, null: false, default: ["id"])
      modify(:excluded_columns, {:array, :string}, null: false, default: [])
      modify(:filtered_columns, {:array, :string}, null: false, default: [])
      modify(:mode, :"#{prefix}.trigger_mode", null: false, default: "capture")
    end

    :ok
  end

  @impl true
  @spec down(any()) :: :ok
  def down(_opts) do
    :ok
  end
end
