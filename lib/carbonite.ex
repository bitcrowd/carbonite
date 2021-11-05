# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite do
  @readme Path.join([__DIR__, "../README.md"])
  @external_resource @readme

  @moduledoc @readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  @moduledoc since: "0.1.0"

  import Ecto.Query
  alias Carbonite.{Outbox, Transaction, Trigger}

  @type prefix :: binary()
  @type repo :: Ecto.Repo.t()

  @type prefix_option :: {:carbonite_prefix, prefix()}

  @doc "Returns the default audit trail prefix."
  @doc since: "0.1.0"
  @spec default_prefix() :: prefix()
  def default_prefix, do: "carbonite_default"

  @doc """
  Inserts a `t:Carbonite.Transaction.t/0` into the database.

  Make sure to run this within a transaction.

  ## Parameters

  * `repo` - the Ecto repository
  * `params` - map of params for the `Carbonite.Transaction` (e.g., `:meta`)
  * `opts` - optional keyword list

  ## Options

  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`

  ## Multiple inserts in the same transaction

  Normally, you should have exactly one `insert_transaction/3` call per database transaction. In
  practise, there are two scenarios in this function may be called multiple times:

  1. If an operation A, which calls `insert_transaction/3`, sometimes is nested within an outer
     operation B, which also calls `insert_transaction/3`.
  2. In tests using Ecto's SQL sandbox, subsequent calls to transactional operations (even to the
     same operation twice) are wrapped inside the overarching test transaction, and hence also
     effectively call `insert_transaction/3` within the same transaction.

  While the first scenario can be resolved using appropriate control flow (e.g. by conditionally
  disabling the inner `insert_transaction/3` call), the second scenario is quite common and often
  unavoidable.

  Therefore, `insert_transaction/3` **ignores** subsequent calls within the same database
  transaction (equivalent to `ON CONFLICT DO NOTHING`), **discarding metadata** passed to all
  calls but the first.
  """
  @doc since: "0.4.0"
  @spec insert_transaction(repo()) :: {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  @spec insert_transaction(repo(), params :: map()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  @spec insert_transaction(repo(), params :: map(), [prefix_option()]) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  def insert_transaction(repo, params \\ %{}, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    # NOTE: ON CONFLICT DO NOTHING does not combine with RETURNING, so we're forcing an UPDATE.

    params
    |> Transaction.changeset()
    |> repo.insert(
      prefix: carbonite_prefix,
      on_conflict: {:replace, [:id]},
      conflict_target: [:id],
      returning: true
    )
  end

  @doc """
  Sets the current transaction to "override mode" for all tables in the audit log.

  ## Parameters

  * `repo` - the Ecto repository
  * `opts` - optional keyword list

  ## Options

  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec override_mode(repo()) :: :ok
  @spec override_mode(repo(), [prefix_option()]) :: :ok
  def override_mode(repo, opts \\ []) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())

    from(t in Trigger,
      update: [set: [override_transaction_id: fragment("pg_current_xact_id()")]]
    )
    |> repo.update_all([], prefix: carbonite_prefix)

    :ok
  end

  @type process_option ::
          Carbonite.Query.outbox_queue_option()
          | {:batch_filter, (Ecto.Query.t() -> Ecto.Query.t())}

  @type process_func_option :: {:memo, Outbox.memo()} | {:discard_last, boolean()}

  @typedoc """
  This type defines the callback function signature for `Carbonite.process/3`.

  The processor function receives the current transaction and the memo of the last function
  application, and must return one of

  * `:cont` - continue processing
  * `:halt` - stop processing after this transaction
  * `{:cont | :halt, opts}` - cont/halt and set some options

  ## Options

  Returned options can be:

  * `memo` - memo map to carry to the next function application, defaults to previous memo
  * `discard` - boolean indicating whether the last transaction was processed successfully,
                defaults to true (if true, previous memo is reinstated)
  """
  @type process_func ::
          (Transaction.t(), Outbox.memo() ->
             :cont | :halt | {:cont | :halt, [process_func_option()]})

  @doc """
  Processes an outbox queue.

  See `Carbonite.Query.outbox_queue/2` for query options.

  ## Examples

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn transaction, _memo ->
        # The transaction has its changes preloaded.
        transaction
        |> serialize()
        |> send_to_external_database()

        :cont
      end)

  ### Memo passing

  The `memo` is useful to carry data between each processor application. Let's say you wanted to
  generate a hashsum chain on your processed data:

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn transaction, %{"checksum" => checksum} ->
        {payload, checksum} = serialize_and_hash(transaction, checksum)

        send_to_external_database(payload)

        {:cont, memo: %{"checksum" => checksum}}
      end)

  ### Error handling

  In case you run into an error midway into processing a batch, you may choose to halt processing
  while remembering about the last processed transaction.

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn transaction, _memo ->
        case send_to_external_database(transaction) do
          :ok ->
            :cont

          {:error, _term} ->
            :halt
        end
      end

  ## Parameters

  * `repo` - the Ecto repository
  * `outbox_name` - name of the outbox to process
  * `opts` - optional keyword list
  * `process_func` - see `t:process_func/0` for details

  ## Options

  * `min_age` - the minimum age of a record, defaults to 300 seconds (set nil to disable)
  * `batch_size` - limits the query in size, defaults to 100 (set nil to disable)
  * `batch_filter` - function for refining the batch query, defaults to nil
  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec process(repo(), Outbox.name(), process_func()) :: :ok
  @spec process(repo(), Outbox.name(), [process_option()], process_func()) :: :ok
  def process(repo, outbox_name, opts \\ [], process_func) do
    carbonite_prefix = Keyword.get(opts, :carbonite_prefix, default_prefix())
    batch_filter = Keyword.get(opts, :batch_filter) || (& &1)

    outbox =
      outbox_name
      |> Carbonite.Query.outbox(opts)
      |> repo.one!()

    attrs =
      outbox
      |> Carbonite.Query.outbox_queue(opts)
      |> batch_filter.()
      |> repo.all()
      |> process_batch(outbox, process_func)

    outbox
    |> Outbox.changeset(attrs)
    |> repo.update!(prefix: carbonite_prefix)

    :ok
  end

  defp process_batch(batch, outbox, process_func) do
    initial = Map.take(outbox, [:last_transaction_id, :memo])

    Enum.reduce_while(batch, initial, fn transaction, acc ->
      {cont_or_halt, opts} = process_transaction(transaction, acc.memo, process_func)

      new_acc =
        if cont_or_halt == :halt && Keyword.get(opts, :discard, true) do
          acc
        else
          %{
            last_transaction_id: transaction.id,
            memo: Keyword.get(opts, :memo, acc.memo)
          }
        end

      {cont_or_halt, new_acc}
    end)
  end

  defp process_transaction(transaction, memo, process_func) do
    case process_func.(transaction, memo) do
      cont_or_halt when is_atom(cont_or_halt) -> {cont_or_halt, []}
      {cont_or_halt, opts} -> {cont_or_halt, opts}
    end
  end

  @type purge_option :: Carbonite.Query.outbox_done_option()

  @doc """
  Deletes transactions that have been fully processed.

  See `Carbonite.Query.outbox_done/1` for query options.

  ## Parameters

  * `repo` - the Ecto repository
  * `opts` - optional keyword list

  ## Options

  * `min_age` - the minimum age of a record, defaults to 300 seconds (set nil to disable)
  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec purge(repo()) :: :ok
  @spec purge(repo(), [purge_option()]) :: :ok
  def purge(repo, opts \\ []) do
    opts
    |> Carbonite.Query.outbox_done()
    |> repo.delete_all()

    :ok
  end
end
