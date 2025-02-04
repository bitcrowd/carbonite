# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Query do
  @moduledoc """
  This module provides query functions for retrieving audit trails from the database.
  """

  @moduledoc since: "0.2.0"

  import Ecto.Query
  import Carbonite.Prefix
  alias Carbonite.{Change, Outbox, Transaction, Trigger}

  @type prefix :: binary()
  @type disabled :: nil | false

  @type prefix_option :: {:carbonite_prefix, prefix()}
  @type preload_option :: {:preload, boolean()}
  @type order_by_option :: {:order_by, false | nil | term()}

  @type transactions_option :: prefix_option() | preload_option()

  # Must be a macro as when queryable is passed as a variable, Ecto won't allow setting the
  # prefix. Only literal schema modules will allow to have their prefixes updated.
  defmacrop from_with_prefix(queryable, opts) do
    quote do
      carbonite_prefix = Keyword.get(unquote(opts), :carbonite_prefix, default_prefix())

      from(unquote(queryable), prefix: ^to_string(carbonite_prefix))
    end
  end

  @doc """
  Returns an `t:Ecto.Query.t/0` that can be used to select transactions from the database.

  ## Examples

      Carbonite.Query.transactions()
      |> MyApp.Repo.all()

      # Preload changes
      Carbonite.Query.transactions(preload: true)
      |> MyApp.Repo.all()

  ## Options

  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  * `preload` - can be used to preload the changes, defaults to `false`
  """

  @doc since: "0.3.1"
  @spec transactions() :: Ecto.Query.t()
  @spec transactions([transactions_option()]) :: Ecto.Query.t()
  def transactions(opts \\ []) do
    from_with_prefix(Transaction, opts)
    |> maybe_preload(opts, :changes, from_with_prefix(Change, opts))
  end

  @type current_transaction_option :: prefix_option() | preload_option()

  @doc """
  Returns an `t:Ecto.Query.t/0` that can be used to select or delete the "current" transaction.

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

  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  * `preload` - can be used to preload the changes, defaults to `false`
  """
  @doc since: "0.2.0"
  @spec current_transaction() :: Ecto.Query.t()
  @spec current_transaction([current_transaction_option()]) :: Ecto.Query.t()
  def current_transaction(opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    from_with_prefix(Transaction, opts)
    |> where(
      [t],
      t.id == fragment("CURRVAL(CONCAT(?::VARCHAR, '.transactions_id_seq'))", ^carbonite_prefix)
    )
    |> where([t], t.xact_id == fragment("pg_current_xact_id()"))
    |> maybe_preload(opts, :changes, from_with_prefix(Change, opts))
  end

  # Returns all triggers.
  @doc false
  @spec triggers() :: Ecto.Query.t()
  def triggers(opts \\ []) do
    from_with_prefix(Trigger, opts)
  end

  @doc """
  Returns an `t:Ecto.Query.t/0` that selects a outbox by name.

  ## Options

  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec outbox(Outbox.name()) :: Ecto.Query.t()
  @spec outbox(Outbox.name(), [prefix_option()]) :: Ecto.Query.t()
  def outbox(outbox_name, opts \\ []) do
    from_with_prefix(Outbox, opts)
    |> where([o], o.name == ^outbox_name)
  end

  @type outbox_queue_option ::
          prefix_option()
          | preload_option()
          | {:min_age, non_neg_integer() | disabled()}
          | {:limit, non_neg_integer() | disabled()}

  @doc """
  Returns an `t:Ecto.Query.t/0` that selects the next batch of transactions for an outbox.

  * Transactions are ordered by their ID ascending, so *roughly* in order of insertion.

  ## Options

  * `min_age` - the minimum age of a record, defaults to 300 seconds (set nil to disable)
  * `limit` - limits the query in size, defaults to 100 (set nil to disable)
  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  * `preload` - can be used to preload the changes, defaults to `true`
  """
  @doc since: "0.4.0"
  @spec outbox_queue(Outbox.t()) :: Ecto.Query.t()
  @spec outbox_queue(Outbox.t(), [outbox_queue_option()]) :: Ecto.Query.t()
  def outbox_queue(%Outbox{last_transaction_id: last_processed_tx_id}, opts \\ []) do
    opts = Keyword.put_new(opts, :preload, true)

    from_with_prefix(Transaction, opts)
    |> where([t], t.id > ^last_processed_tx_id)
    |> maybe_apply(opts, :limit, 100, fn q, bs -> limit(q, ^bs) end)
    |> maybe_apply(opts, :min_age, 300, &where_inserted_at_lt/2)
    |> maybe_preload(opts, :changes, from_with_prefix(Change, opts))
    |> order_by({:asc, :id})
  end

  @type outbox_done_option :: prefix_option() | {:min_age, non_neg_integer() | disabled()}

  @doc """
  Returns an `t:Ecto.Query.t/0` that selects all completely processed transactions.

  * If no outbox exists, this query returns all transactions.
  * If one or more outboxes exist, this query returns all transactions with an ID less than the
    minimum of the `last_transaction_id` attributes of the outboxes.
  * Transactions are not ordered.

  ## Options

  * `min_age` - the minimum age of a record, defaults to 300 seconds (set nil to disable)
  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec outbox_done() :: Ecto.Query.t()
  @spec outbox_done([outbox_done_option()]) :: Ecto.Query.t()
  def outbox_done(opts \\ []) do
    # NOTE: The query below has a non-optimal query plan, but expressing it differently makes
    #       it a bit convoluted (e.g., fetching the min `last_transaction_id` or `MAX_INT` if that
    #       does not exist and then filtering by <= that number), so we keep the `ALL()` for now.

    outbox_query =
      Outbox
      |> from_with_prefix(opts)
      |> select([o], o.last_transaction_id)

    Transaction
    |> from_with_prefix(opts)
    |> where([t], t.id <= all(outbox_query))
    |> maybe_apply(opts, :min_age, 300, &where_inserted_at_lt/2)
  end

  @default_table_prefix "public"

  @type changes_option ::
          prefix_option() | preload_option() | order_by_option() | {:table_prefix, prefix()}

  @doc """
  Returns an `t:Ecto.Query.t/0` that can be used to select changes for a single record.

  Given an `t:Ecto.Schema.t/0` struct, this function builds a query that fetches all changes
  recorded for it from the database, ordered ascending by their ID (i.e., roughly by
  insertion date descending).

  ## Example

      %MyApp.Rabbit{id: 1}
      |> Carbonite.Query.changes()
      |> MyApp.Repo.all()

  ## Options

  * `carbonite_prefix` defines the audit trail's schema, defaults to `"carbonite_default"`
  * `table_prefix` allows to override the table prefix, defaults to schema prefix of the record
  * `preload` can be used to preload the transaction
  * `order_by` allows to override the ordering, defaults to `{:asc, :id}`
  """
  @doc since: "0.2.0"
  @spec changes(record :: Ecto.Schema.t()) :: Ecto.Query.t()
  @spec changes(record :: Ecto.Schema.t(), [changes_option()]) :: Ecto.Query.t()
  def changes(%schema{__meta__: %Ecto.Schema.Metadata{}} = record, opts \\ []) do
    table_prefix =
      Keyword.get_lazy(opts, :table_prefix, fn ->
        schema.__schema__(:prefix) || @default_table_prefix
      end)

    table_name = schema.__schema__(:source)

    table_pk =
      for pk_col <- Enum.sort(schema.__schema__(:primary_key)) do
        record |> Map.fetch!(pk_col) |> to_string()
      end

    from_with_prefix(Change, opts)
    |> where([c], c.table_prefix == ^table_prefix)
    |> where([c], c.table_name == ^table_name)
    |> where([c], c.table_pk == ^table_pk)
    |> maybe_preload(opts, :transaction, from_with_prefix(Transaction, opts))
    |> maybe_order_by(opts)
  end

  defp maybe_apply(queryable, opts, key, default, fun) do
    if value = Keyword.get(opts, key, default) do
      fun.(queryable, value)
    else
      queryable
    end
  end

  defp maybe_order_by(queryable, opts) do
    case Keyword.get(opts, :order_by, {:asc, :id}) do
      order_by when order_by in [false, nil] ->
        queryable

      value ->
        order_by(queryable, ^value)
    end
  end

  defp maybe_preload(queryable, opts, association, preload_query) do
    case Keyword.get(opts, :preload, false) do
      preload when preload in [false, nil] ->
        queryable

      true ->
        preload(queryable, [{^association, ^preload_query}])
    end
  end

  defp where_inserted_at_lt(queryable, min_age) do
    max_inserted_at = DateTime.add(DateTime.utc_now(), -1 * min_age, :second)

    where(queryable, [t], t.inserted_at <= ^max_inserted_at)
  end
end
