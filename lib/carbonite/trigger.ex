# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Trigger do
  @moduledoc """
  A `Carbonite.Trigger` stores per table configuration for the change capture trigger.
  """

  @moduledoc since: "0.1.0"

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          table_name: String.t(),
          table_prefix: String.t(),
          primary_key_columns: [String.t()],
          excluded_columns: [String.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "triggers" do
    field(:table_prefix, :string)
    field(:table_name, :string)
    field(:primary_key_columns, {:array, :string}, default: [])
    field(:excluded_columns, {:array, :string}, default: [])

    timestamps()
  end
end
