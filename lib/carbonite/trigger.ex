# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Trigger do
  @moduledoc """
  A `Carbonite.Trigger` stores per table configuration for the change capture trigger.
  """

  @moduledoc since: "0.1.0"

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  @type id :: non_neg_integer()
  @type mode :: :capture | :ignore

  @type t :: %__MODULE__{
          id: id(),
          table_name: String.t(),
          table_prefix: String.t(),
          primary_key_columns: [String.t()],
          excluded_columns: [String.t()],
          filtered_columns: [String.t()],
          mode: mode(),
          override_transaction_id: nil | non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "triggers" do
    field(:table_prefix, :string)
    field(:table_name, :string)
    field(:primary_key_columns, {:array, :string}, default: [])
    field(:excluded_columns, {:array, :string}, default: [])
    field(:filtered_columns, {:array, :string}, default: [])
    field(:mode, Ecto.Enum, values: [:capture, :ignore])
    field(:override_transaction_id, :integer)

    timestamps()
  end
end
