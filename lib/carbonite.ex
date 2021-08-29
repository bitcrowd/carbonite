defmodule Carbonite do
  @moduledoc """
  TODO
  """

  alias Carbonite.Transaction

  @default_prefix "carbonite_default"

  @type build_option :: {:meta, map()}
  @type insert_option :: {:prefix, binary()} | build_option()

  @doc """
  TODO
  """
  @spec build() :: Ecto.Changeset.t()
  @spec build([build_option()]) :: Ecto.Changeset.t()
  def build(opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})

    Ecto.Changeset.cast(%Transaction{}, %{meta: meta}, [:meta])
  end

  @doc """
  TODO
  """
  @spec insert(Ecto.Multi.t()) :: Ecto.Multi.t()
  @spec insert(Ecto.Multi.t(), [insert_option()]) :: Ecto.Multi.t()
  def insert(%Ecto.Multi{} = multi, opts \\ []) do
    insert_opts =
      opts
      |> Keyword.take([:prefix])
      |> Keyword.put_new(:prefix, @default_prefix)
      |> Keyword.put_new(:returning, [:id])

    Ecto.Multi.insert(
      multi,
      :carbonite_transaction,
      fn _state -> build(opts) end,
      insert_opts
    )
  end
end
