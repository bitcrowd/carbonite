defmodule Carbonite.Transaction do
  @moduledoc """
  TODO
  """

  use Ecto.Schema
  import Ecto.Changeset, only: [cast: 3, validate_required: 2]

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  @type type :: String.t()
  @type meta :: map()

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          type: type(),
          meta: meta(),
          inserted_at: DateTime.t(),
          changes: Ecto.Association.NotLoaded.t() | [Carbonite.Change.t()]
        }

  schema "carbonite_transactions" do
    field(:id, :integer, primary_key: true)
    field(:type, :string)
    field(:meta, :map)

    timestamps(updated_at: false)

    #    has_many(:changes, Carbonite.Change, references: :id)
    has_many(:changes, Carbonite.Change, references: :id)
  end

  @doc """
  Builds a changeset for insertion.
  """
  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [:type, :meta])
    |> validate_required([:type])
  end
end
