# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Query do
  @moduledoc """
  This module provides query functions for retrieving transaction logs from the database.
  """

  import Ecto.Query, only: [from: 2, preload: 2, put_query_prefix: 2]
  import Carbonite, only: [default_prefix: 0]
  alias Carbonite.Transaction

  @type prefix :: binary() | atom()

  @type current_transaction_option :: {:prefix, prefix()} | {:preload, atom() | [atom()] | true}

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

  * `preload` defines which associations to preload, defaults to none
  * `prefix` defines the transaction log's schema, defaults to `"carbonite_default"`
  """
  @spec current_transaction() :: Ecto.Query.t()
  @spec current_transaction([current_transaction_option()]) :: Ecto.Query.t()
  def current_transaction(opts \\ []) do
    prefix = Keyword.get(opts, :prefix, default_prefix())

    from(t in Transaction, where: t.id == fragment("pg_current_xact_id()"))
    |> put_query_prefix(prefix)
    |> maybe_preload(opts)
  end

  defp maybe_preload(queryable, opts) do
    case Keyword.get(opts, :preload, []) do
      [] -> queryable
      true -> preload(queryable, :changes)
      preload -> preload(queryable, ^preload)
    end
  end
end
