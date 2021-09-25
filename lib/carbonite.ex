# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite do
  @readme Path.join([__DIR__, "../README.md"])
  @external_resource @readme

  @moduledoc @readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @moduledoc since: "0.1.0"

  alias Carbonite.Transaction
  alias Ecto.Multi

  @type prefix :: binary() | map()
  @type meta :: map()

  @type build_option :: {:meta, meta()}

  @doc """
  Builds a changeset for a new `Carbonite.Transaction`.
  """
  @spec transaction_changeset() :: Ecto.Changeset.t()
  @spec transaction_changeset([build_option()]) :: Ecto.Changeset.t()
  def transaction_changeset(opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})
    meta = Map.merge(current_meta(), meta)

    Ecto.Changeset.cast(%Transaction{}, %{meta: meta}, [:meta])
  end

  @type insert_option :: {:prefix, prefix()} | build_option()

  @doc """
  Adds an insert operation for a `Carbonite.Transaction` to an `Ecto.Multi`.
  """
  @spec insert(Multi.t()) :: Multi.t()
  @spec insert(Multi.t(), [insert_option()]) :: Multi.t()
  def insert(%Multi{} = multi, opts \\ []) do
    insert_opts =
      opts
      |> Keyword.take([:prefix])
      |> Keyword.put_new(:prefix, default_prefix())
      |> Keyword.put_new(:returning, [:id])

    Multi.insert(
      multi,
      :carbonite_transaction,
      fn _state -> transaction_changeset(opts) end,
      insert_opts
    )
  end

  @meta_pdict_key :carbonite_meta

  @doc """
  Stores a piece of metadata in the process dictionary.

  This can be useful in situations where you want to record a value at a system boundary (say,
  the user's `account_id`) without having to pass it through to the database transaction.

  Returns the currently stored metadata.
  """
  @spec put_meta(key :: any(), value :: any()) :: meta()
  def put_meta(key, value) do
    meta = Map.put(current_meta(), key, value)
    Process.put(@meta_pdict_key, meta)
    meta
  end

  @doc """
  Returns the currently stored metadata.
  """
  @spec current_meta() :: meta()
  def current_meta do
    Process.get(@meta_pdict_key) || %{}
  end

  @doc false
  @spec default_prefix() :: binary()
  def default_prefix, do: "carbonite_default"
end
