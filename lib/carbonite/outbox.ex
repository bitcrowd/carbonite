# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Outbox do
  @moduledoc """
  A `Carbonite.Outbox` stores metadata for outboxes like the last processed transaction.

  The `last_transaction_id` field defaults to zero, indicating that nothing has been
  processed yet.
  """

  @moduledoc since: "0.4.0"

  use Carbonite.Schema
  import Ecto.Changeset

  @primary_key false

  @type name() :: String.t()
  @type memo() :: map()

  @type t :: %__MODULE__{
          name: name(),
          last_transaction_id: non_neg_integer(),
          memo: memo(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "outboxes" do
    field(:name, :string, primary_key: true)
    field(:last_transaction_id, :integer)
    field(:memo, :map)

    timestamps()
  end

  @doc """
  Builds an update changeset.
  """
  @doc since: "0.4.0"
  @spec changeset(__MODULE__.t(), params :: map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = outbox, params) do
    outbox
    |> cast(params, [:last_transaction_id, :memo])
    |> validate_required([:memo])
  end
end
