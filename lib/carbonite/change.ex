# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Change do
  @moduledoc """
  A `Carbonite.Change` records a mutation on a database table.

  `INSERT` statements lead to a `Change` where the `data` field contains the inserted row as a
  JSON object while the `changed` field is an empty list.

  `UPDATE` statements contain the updated record in `data` while the `changed` field is a list
  of attributes that have changed. The `changed_from` field may additionally contain a partial
  representation of the replaced record, showing only the diff to the updated record. This
  behaviour is optional and can be enabled with the `store_changed_from` trigger option.

  `DELETE` statements have the deleted data in `data` while `changed` is again an empty list.
  """

  @moduledoc since: "0.1.0"

  use Carbonite.Schema

  if Code.ensure_loaded?(Jason.Encoder) do
    @derive {Jason.Encoder,
             only: [
               :id,
               :op,
               :table_prefix,
               :table_name,
               :table_pk,
               :data,
               :changed,
               :changed_from
             ]}
  end

  @primary_key false

  @type id :: non_neg_integer()

  @type t :: %__MODULE__{
          id: id(),
          op: :insert | :update | :delete,
          table_prefix: String.t(),
          table_name: String.t(),
          table_pk: nil | [String.t()],
          data: map(),
          changed: [String.t()],
          changed_from: nil | map(),
          transaction: Ecto.Association.NotLoaded.t() | Carbonite.Transaction.t(),
          transaction_xact_id: non_neg_integer()
        }

  schema "changes" do
    field(:id, :integer, primary_key: true)
    field(:op, Ecto.Enum, values: [:insert, :update, :delete])
    field(:table_prefix, :string)
    field(:table_name, :string)
    field(:table_pk, {:array, :string})
    field(:data, :map)
    field(:changed, {:array, :string})
    field(:changed_from, :map)

    belongs_to(:transaction, Carbonite.Transaction)

    field(:transaction_xact_id, :integer)
  end
end
