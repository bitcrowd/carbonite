defmodule Carbonite do
  @moduledoc """
  TODO
  """

  alias Carbonite.Transaction
  alias Ecto.Multi

  @default_prefix Application.compile_env!(:carbonite, :default_prefix)
  @meta_pdict_key :carbonite_meta

  @type meta :: map()

  @type build_option :: {:meta, meta()}
  @type insert_option :: {:prefix, binary()} | build_option()

  @doc """
  Builds a changeset for a new `Carbonite.Transaction`.
  """
  @spec build() :: Ecto.Changeset.t()
  @spec build([build_option()]) :: Ecto.Changeset.t()
  def build(opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})
    meta = Map.merge(current_meta(), meta)

    Ecto.Changeset.cast(%Transaction{}, %{meta: meta}, [:meta])
  end

  @doc """
  TODO
  """
  @spec insert(Multi.t()) :: Multi.t()
  @spec insert(Multi.t(), [insert_option()]) :: Multi.t()
  def insert(%Multi{} = multi, opts \\ []) do
    insert_opts =
      opts
      |> Keyword.take([:prefix])
      |> Keyword.put_new(:prefix, @default_prefix)
      |> Keyword.put_new(:returning, [:id])

    Multi.insert(
      multi,
      :carbonite_transaction,
      fn _state -> build(opts) end,
      insert_opts
    )
  end

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
end
