# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Change do
  @moduledoc """
  A `Carbonite.Change` records a mutation on a database table.

  `INSERT` statements lead to a `Change` where the `new` field contains the inserted row as a
  JSON object while the `old` field is `nil`. `UPDATE` statements contain both `old` and `new`
  fields, and `DELETE` statements only contain data in `old`.
  """

  use Ecto.Schema

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          op: :insert | :update | :delete,
          table_prefix: String.t(),
          table_name: String.t(),
          old: nil | map(),
          new: nil | map(),
          transaction: Ecto.Association.NotLoaded.t() | Carbonite.Transaction.t()
        }

  schema "changes" do
    field(:id, :integer, primary_key: true)
    field(:op, Ecto.Enum, values: [:insert, :update, :delete])
    field(:table_prefix, :string)
    field(:table_name, :string)
    field(:old, :map)
    field(:new, :map)

    belongs_to(:transaction, Carbonite.Transaction)
  end
end
