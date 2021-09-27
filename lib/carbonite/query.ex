# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Query do
  @moduledoc """
  This module provides query functions for retrieving transaction logs from the database.
  """

  import Ecto.Query, only: [from: 2, preload: 2, put_query_prefix: 2]
  import Carbonite, only: [default_prefix: 0]
  alias Carbonite.{Change, Transaction}

  @type prefix :: binary() | atom()
  @type preload :: atom() | [atom()] | true

  @type current_transaction_option :: {:carbonite_prefix, prefix()} | {:preload, preload()}

  @doc """
  Returns an `Ecto.Query` that can be used to select or delete the "current" transaction.

  This function is useful when your tests run in a database transaction using Ecto's SQL sandbox.

  ## Examples

  ### Asserting on the current transaction

  When you insert your `Carbonite.Transaction` record somewhere inside your domain logic, you do
  not wish to return it to the caller only to be able to assert on its attributes in tests. This
  is how you can assert on the current transaction:

      Carbonite.Query.current_transaction()
      |> MyApp.Repo.all()

      # Preload changes
      Carbonite.Query.current_transaction(preload: :changes)
      |> MyApp.Repo.all()

      # Same
      Carbonite.Query.current_transaction(preload: true)
      |> MyApp.Repo.all()

  ### Erasing the current transaction

  Sometimes your test code may run a particular function twice (in multiple transactions if it
  wasn't for the SQL sandbox), in which case you may need to delete the `Carbonite.Transaction`
  inserted first in between.

      # This deletes the transaction as well as any associated change (per FK constraint)
      Carbonite.Query.current_transaction()
      |> MyApp.Repo.delete_all()

  ## Options

  * `carbonite_prefix` defines the transaction log's schema, defaults to `"carbonite_default"`
  * `preload` can be used to preload the changes
  """
  @spec current_transaction() :: Ecto.Query.t()
  @spec current_transaction([current_transaction_option()]) :: Ecto.Query.t()
  def current_transaction(opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    from(t in Transaction, where: t.id == fragment("pg_current_xact_id()"))
    |> put_query_prefix(carbonite_prefix)
    |> maybe_preload(opts, :changes)
  end

  @default_table_prefix "public"

  @type changes_option :: {:carbonite_prefix, prefix()} | {:preload, preload()}

  @doc """
  Returns an `Ecto.Query` that can be used to select changes for a single record.

  Given an `Ecto.Schema` struct, this function builds a query that fetches all changes recorded
  for it from the database, ordered ascending by their ID (i.e., roughly by insertion date
  descending).

  ## Options

  * `carbonite_prefix` defines the transaction log's schema, defaults to `"carbonite_default"`
  * `preload` can be used to preload the transaction
  """
  @spec changes(Ecto.Schema.t()) :: Ecto.Query.t()
  @spec changes(Ecto.Schema.t(), [changes_option()]) :: Ecto.Query.t()
  def changes(%schema{__meta__: %Ecto.Schema.Metadata{}} = record, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    table_prefix = schema.__schema__(:prefix) || @default_table_prefix
    table_name = schema.__schema__(:source)

    table_pk =
      for pk_col <- schema.__schema__(:primary_key) do
        record |> Map.fetch!(pk_col) |> to_string()
      end

    from(c in Change,
      where: c.table_prefix == ^table_prefix,
      where: c.table_name == ^table_name,
      where: c.table_pk == ^table_pk,
      order_by: {:asc, :id}
    )
    |> put_query_prefix(carbonite_prefix)
    |> maybe_preload(opts, :transaction)
  end

  defp maybe_preload(queryable, opts, default) do
    case Keyword.get(opts, :preload, []) do
      [] -> queryable
      true -> preload(queryable, ^default)
      preload -> preload(queryable, ^preload)
    end
  end
end
