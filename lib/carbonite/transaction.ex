# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Transaction do
  @moduledoc """
  A `Carbonite.Transaction` is the binding link between change records of tables.

  As such, it contains a set of optional metadata that describes the transaction.
  """

  @moduledoc since: "0.1.0"

  use Carbonite.Schema
  import Ecto.Changeset

  @encodable_columns [:id, :meta, :inserted_at, :changes]

  if Code.ensure_loaded?(JSON) do
    @derive {JSON.Encoder, only: @encodable_columns}
  else
    if Code.ensure_loaded?(Jason.Encoder) do
      @derive {Jason.Encoder, only: @encodable_columns}
    end
  end

  @primary_key false

  @type meta :: map()

  @type id :: non_neg_integer()

  @type t :: %__MODULE__{
          id: id(),
          xact_id: non_neg_integer(),
          meta: meta(),
          inserted_at: DateTime.t(),
          changes: Ecto.Association.NotLoaded.t() | [Carbonite.Change.t()]
        }

  schema "transactions" do
    field(:id, :integer, primary_key: true)
    field(:xact_id, :integer)
    field(:meta, :map, default: %{})

    timestamps(updated_at: false)

    has_many(:changes, Carbonite.Change, references: :id)
  end

  @meta_pdict_key :carbonite_meta

  @doc """
  Stores a piece of metadata in the process dictionary.

  This can be useful in situations where you want to record a value at a system boundary (say,
  the user's `account_id`) without having to pass it through to the database transaction.

  Returns the currently stored metadata.
  """
  @doc since: "0.2.0"
  @spec put_meta(key :: any(), value :: any()) :: meta()
  def put_meta(key, value) do
    meta = Map.put(current_meta(), key, value)
    Process.put(@meta_pdict_key, meta)
    meta
  end

  @doc """
  Returns the currently stored metadata.
  """
  @doc since: "0.2.0"
  @spec current_meta() :: meta()
  def current_meta do
    Process.get(@meta_pdict_key) || %{}
  end

  @doc """
  Builds a changeset for a new `Carbonite.Transaction`.

  The `:meta` map from the params will be merged with the metadata currently stored in the
  process dictionary.
  """
  @doc since: "0.2.0"
  @spec changeset() :: Ecto.Changeset.t()
  @spec changeset(params :: map()) :: Ecto.Changeset.t()
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:meta])
    |> merge_current_meta()
  end

  defp merge_current_meta(changeset) do
    meta = Map.merge(current_meta(), get_field(changeset, :meta))

    put_change(changeset, :meta, meta)
  end
end
