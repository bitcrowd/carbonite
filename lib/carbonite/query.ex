# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Query do
  @moduledoc """
  This module provides query functions for retrieving audit trails from the database.
  """

  @moduledoc since: "0.2.0"

  import Ecto.Query
  import Carbonite, only: [default_prefix: 0]
  alias Carbonite.{Change, Transaction}

  @type prefix :: binary()
  @type preload :: atom() | [atom()] | true

  @type transactions_option :: {:carbonite_prefix, prefix()} | {:preload, preload()}

  @doc """
  Returns an `Ecto.Query` that can be used to select transactions from the database.

  ## Examples

      Carbonite.Query.transactions()
      |> MyApp.Repo.all()

      # Preload changes
      Carbonite.Query.transactions(preload: :changes)
      |> MyApp.Repo.all()

      # Same
      Carbonite.Query.transactions(preload: true)
      |> MyApp.Repo.all()

  ## Options

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `preload` can be used to preload the changes
  """
  @doc since: "0.3.1"
  @spec transactions() :: Ecto.Query.t()
  @spec transactions([transactions_option()]) :: Ecto.Query.t()
  def transactions(opts \\ []) do
    carbonite_prefix = get_carbonite_prefix(opts)

    from(t in Transaction)
    |> put_query_prefix(carbonite_prefix)
    |> maybe_preload(opts, :changes)
  end

  @type current_transaction_option :: {:carbonite_prefix, prefix()} | {:preload, preload()}

  @doc """
  Returns an `Ecto.Query` that can be used to select or delete the "current" transaction.

  This function is useful when your tests run in a database transaction using Ecto's SQL sandbox.

  ## Example: Asserting on the current transaction

  When you insert your `Carbonite.Transaction` record somewhere inside your domain logic, you do
  not wish to return it to the caller only to be able to assert on its attributes in tests. This
  example shows how you could assert on the metadata inserted.

      # Test running inside Ecto's SQL sandbox.
      test "my test" do
        some_operation_with_a_transaction()

        assert current_transaction_meta() == %{"type" => "some_operation"}
      end

      defp current_transaction_meta do
        Carbonite.Query.current_transaction()
        |> MyApp.Repo.one!()
        |> Map.fetch(:meta)
      end

  ## Options

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `preload` can be used to preload the changes
  """
  @doc since: "0.2.0"
  @spec current_transaction() :: Ecto.Query.t()
  @spec current_transaction([current_transaction_option()]) :: Ecto.Query.t()
  def current_transaction(opts \\ []) do
    carbonite_prefix = get_carbonite_prefix(opts)

    from(t in Transaction, where: t.id == fragment("pg_current_xact_id()"))
    |> put_query_prefix(carbonite_prefix)
    |> maybe_preload(opts, :changes)
  end

  @default_table_prefix "public"

  @type changes_option ::
          {:carbonite_prefix, prefix()} | {:table_prefix, prefix()} | {:preload, preload()}

  @doc """
  Returns an `Ecto.Query` that can be used to select changes for a single record.

  Given an `Ecto.Schema` struct, this function builds a query that fetches all changes recorded
  for it from the database, ordered ascending by their ID (i.e., roughly by insertion date
  descending).

  ## Example

      %MyApp.Rabbit{id: 1}
      |> Carbonite.Query.changes()
      |> MyApp.Repo.all()

  ## Options

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `table_prefix` allows to override the table prefix, defaults to schema prefix of the record
  * `preload` can be used to preload the transaction
  """
  @doc since: "0.2.0"
  @spec changes(record :: Ecto.Schema.t()) :: Ecto.Query.t()
  @spec changes(record :: Ecto.Schema.t(), [changes_option()]) :: Ecto.Query.t()
  def changes(%schema{__meta__: %Ecto.Schema.Metadata{}} = record, opts \\ []) do
    carbonite_prefix = get_carbonite_prefix(opts)

    table_prefix =
      Keyword.get_lazy(opts, :table_prefix, fn ->
        schema.__schema__(:prefix) || @default_table_prefix
      end)

    table_name = schema.__schema__(:source)

    table_pk =
      for pk_col <- Enum.sort(schema.__schema__(:primary_key)) do
        record |> Map.fetch!(pk_col) |> to_string()
      end

    from(c in Change)
    |> where([c], c.table_prefix == ^table_prefix)
    |> where([c], c.table_name == ^table_name)
    |> where([c], c.table_pk == ^table_pk)
    |> order_by({:asc, :id})
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

  defp get_carbonite_prefix(opts) do
    opts
    |> Keyword.get(:carbonite_prefix, default_prefix())
    |> to_string()
  end
end
