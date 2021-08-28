defmodule Carbonite.Change do
  @moduledoc """
  TODO
  """

  use Ecto.Schema

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          op: :insert | :update | :delete,
          table_name: String.t(),
          relid: non_neg_integer(),
          row_data: map(),
          changes: nil | map(),
          transaction: Ecto.Association.NotLoaded.t() | Carbonite.Transaction.t()
        }

  schema "changes" do
    field(:id, :integer, primary_key: true)
    field(:op, Ecto.Enum, values: [:insert, :update, :delete])
    field(:table_name, :string)
    field(:relid, :integer)
    field(:row_data, :map)
    field(:changes, :map)

    belongs_to(:transaction, Carbonite.Transaction)
  end
end
