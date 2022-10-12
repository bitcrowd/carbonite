# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Trigger do
  @moduledoc """
  A `Carbonite.Trigger` stores per table configuration for the change capture trigger.
  """

  @moduledoc since: "0.1.0"

  use Carbonite.Schema

  @primary_key {:id, :id, autogenerate: true}

  @type id :: non_neg_integer()
  @type mode :: :capture | :ignore

  @type t :: %__MODULE__{
          id: id(),
          table_name: String.t(),
          table_prefix: String.t(),
          primary_key_columns: [String.t()],
          excluded_columns: [String.t()],
          filtered_columns: [String.t()],
          store_changed_from: boolean(),
          mode: mode(),
          override_xact_id: nil | non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "triggers" do
    field(:table_prefix, :string)
    field(:table_name, :string)
    field(:primary_key_columns, {:array, :string})
    field(:excluded_columns, {:array, :string})
    field(:filtered_columns, {:array, :string})
    field(:store_changed_from, :boolean)
    field(:mode, Ecto.Enum, values: [:capture, :ignore])
    field(:override_xact_id, :integer)

    timestamps()
  end
end
