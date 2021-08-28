defmodule Carbonite.Transaction do
  @moduledoc """
  A `Carbonite.Transaction` is the binding link between change records of tables.

  As such, it contains a mandatory `type` attribute as well as a set of optional metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, validate_required: 2]

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          type: String.t(),
          meta: map(),
          inserted_at: DateTime.t(),
          changes: Ecto.Association.NotLoaded.t() | [Carbonite.Change.t()]
        }

  schema "transactions" do
    field(:id, :integer, primary_key: true)
    field(:type, :string)
    field(:meta, :map)

    timestamps(updated_at: false)

    has_many(:changes, Carbonite.Change, references: :id)
  end

  @doc """
  Builds a changeset for a `Carbonite.Transaction`.
  """
  @spec changeset(params :: map()) :: Ecto.Changeset.t()
  @spec changeset(t(), params :: map()) :: Ecto.Changeset.t()
  def changeset(transaction \\ %__MODULE__{}, params) do
    transaction
    |> cast(params, [:type, :meta])
    |> validate_required([:type])
  end
end
