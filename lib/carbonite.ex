defmodule Carbonite do
  @moduledoc """
  TODO
  """

  alias Carbonite.Transaction

  @default_prefix "carbonite_default"

  @type build_option :: {:meta, Transaction.meta()}
  @type insert_option :: {:prefix, binary()} | build_option()

  @doc """
  TODO
  """
  @spec build(Transaction.type(), [build_option()]) :: Ecto.Changeset.t()
  def build(type, opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})

    Transaction.create_changeset(%{type: type, meta: meta})
  end

  @doc """
  TODO
  """
  @spec insert(Ecto.Multi.t(), Transaction.type(), insert_option()) :: Ecto.Multi.t()
  def insert(%Ecto.Multi{} = multi, type, opts \\ []) do
    insert_opts =
      opts
      |> Keyword.take([:prefix])
      |> Keyword.put_new(:prefix, @default_prefix)
      |> Keyword.put_new(:returning, [:id])

    Ecto.Multi.insert(
      multi,
      :carbonite_transaction,
      fn _state ->
        build(type, opts)
      end,
      insert_opts
    )
  end
end
