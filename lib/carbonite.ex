# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite do
  @readme Path.join([__DIR__, "../README.md"])
  @external_resource @readme

  @moduledoc @readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.drop(1)
             |> Enum.take_every(2)
             |> Enum.join("\n")

  @moduledoc since: "0.1.0"

  import Ecto.Query
  alias Carbonite.{Outbox, Prefix, Query, Schema, Transaction}
  require Prefix
  require Schema

  @type prefix :: binary()
  @type repo :: Ecto.Repo.t()

  @type prefix_option :: {:carbonite_prefix, prefix()}

  @doc "Returns the default audit trail prefix."
  @doc since: "0.1.0"
  @spec default_prefix() :: prefix()
  def default_prefix, do: Prefix.default_prefix()

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
  Fetches all changes of the current transaction from the database.

  Make sure to run this within a transaction.

  ## Parameters

  * `repo` - the Ecto repository
  * `opts` - optional keyword list

  ## Options

  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.5.0"
  @spec fetch_changes(repo()) :: {:ok, [Carbonite.Change.t()]}
  @spec fetch_changes(repo(), [prefix_option()]) :: {:ok, [Carbonite.Change.t()]}
  def fetch_changes(repo, opts \\ []) do
    %Carbonite.Transaction{changes: changes} =
      [preload: true]
      |> Keyword.merge(opts)
      |> Query.current_transaction()
      |> repo.one()

    {:ok, changes}
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
    opts
    |> Query.triggers()
    |> update([], set: [override_xact_id: fragment("pg_current_xact_id()")])
    |> repo.update_all([])

    :ok
  end

  @type process_option ::
          Carbonite.Query.outbox_queue_option()
          | {:filter, (Ecto.Query.t() -> Ecto.Query.t())}
          | {:chunk, pos_integer()}

  @type process_func_option :: {:memo, Outbox.memo()} | {:discard_last, boolean()}

  @typedoc """
  This type defines the callback function signature for `Carbonite.process/3`.

  The processor function receives the current chunk of transactions and the memo of the last
  function application, and must return one of

  * `:cont` - continue processing
  * `:halt` - stop processing after this chunk
  * `{:cont | :halt, opts}` - cont/halt and set some options

  After the process function invocation the Outbox is updated with new attributes.

  ## Options

  Returned options can be:

  * `memo` - memo to store on Outbox, defaults to previous memo
  * `last_transaction_id` - last transaction id to remember as processed, defaults to previous
                            `last_transaction_id` on `:halt`, defaults to last id in current
                            chunk when `:cont` is returned
  """
  @type process_func ::
          ([Transaction.t()], Outbox.memo() ->
             :cont | :halt | {:cont | :halt, [process_func_option()]})

  @doc """
  Processes an outbox queue.

  This function sends chunks of persisted transactions to a user-supplied processing function. It
  looks up the current "reading position" from a given `Carbonite.Outbox` and yields transactions
  matching the given filter criteria (`min_age`, etc.) until either the input source is exhausted
  or a processing function application returns `:halt`.

  Returns the `{:ok, outbox}` or `{:halt, outbox}` depending on whether processing was halted
  explicitly or due the exhausted input source.

  See `Carbonite.Query.outbox_queue/2` for query options.

  ## Examples

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn [transaction], _memo ->
        # The transaction has its changes preloaded.
        transaction
        |> MyApp.Foo.serialize()
        |> MyApp.Foo.send_to_external_database()

        :cont
      end)

  ### Memo passing

  The `memo` is useful to carry data between each processor application. Let's say you wanted to
  generate a hashsum chain on your processed data:

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn [transaction], %{"checksum" => checksum} ->
        {payload, checksum} = MyApp.Foo.serialize_and_hash(transaction, checksum)

        MyApp.Foo.send_to_external_database(payload)

        {:cont, memo: %{"checksum" => checksum}}
      end)

  ### Chunking / Limiting

  The examples above received a single-element list as their first parameter: This is because the
  transactions are actually processed in "chunks" and the default chunk size is 1. If you would
  like to process more transactions in one chunk, set the `chunk` option:

      Carbonite.process(MyApp.Repo, "rabbit_holes", [chunk: 50], fn transactions, _memo ->
        for transaction <- transactions do
          transaction
          |> MyApp.Foo.serialize()
          |> MyApp.Foo.send_to_external_database()
        end

        :cont
      end)

  The query that is executed to fetch the data from the database is controlled with the `limit`
  option and is independent of the chunk size.

  ### Error handling

  In case you run into an error midway into processing a batch, you may choose to halt processing
  while remembering about the last processed transaction.

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn [transaction], _memo ->
        case send_to_external_database(transaction) do
          :ok ->
            :cont

          {:error, _term} ->
            :halt
        end
      end

  You can, however, if you know the first half of a batch has been processed, still update the
  `memo` and `last_transaction_id`.

      Carbonite.process(MyApp.Repo, "rabbit_holes", fn transactions, _memo ->
        case process_transactions(transactions) do
          {:error, last_successful_transaction} ->
            {:halt, last_transaction_id: last_successful_transaction.id}

          :ok ->
            :cont
        end
      end

  ## Parameters

  * `repo` - the Ecto repository
  * `outbox_name` - name of the outbox to process
  * `opts` - optional keyword list
  * `process_func` - see `t:process_func/0` for details

  ## Options

  * `min_age` - the minimum age of a record, defaults to 300 seconds (set nil to disable)
  * `limit` - limits the query in size, defaults to 100 (set nil to disable)
  * `filter` - function for refining the batch query, defaults to nil
  * `chunk` - defines the size of the chunk passed to the process function, defaults to 1
  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec process(repo(), Outbox.name(), process_func()) :: {:ok | :halt, Outbox.t()}
  @spec process(repo(), Outbox.name(), [process_option()], process_func()) ::
          {:ok | :halt, Outbox.t()}
  def process(repo, outbox_name, opts \\ [], process_func) do
    outbox = load_outbox(repo, outbox_name, opts)

    functions = %{
      query: query_func(repo, opts),
      process: process_func(process_func),
      update: update_func(repo)
    }

    process_outbox(outbox, functions)
  end

  defp load_outbox(repo, outbox_name, opts) do
    outbox_name
    |> Carbonite.Query.outbox(opts)
    |> repo.one!()
  end

  defp query_func(repo, opts) do
    filter = Keyword.get(opts, :filter) || (& &1)
    chunk = Keyword.get(opts, :chunk, 1)

    fn outbox ->
      outbox
      |> Carbonite.Query.outbox_queue(opts)
      |> filter.()
      |> repo.all()
      |> Enum.chunk_every(chunk)
    end
  end

  defp process_func(process_func) do
    fn chunk, outbox ->
      case process_func.(chunk, outbox.memo) do
        cont_or_halt when is_atom(cont_or_halt) -> {cont_or_halt, []}
        {cont_or_halt, opts} -> {cont_or_halt, opts}
      end
    end
  end

  defp update_func(repo) do
    fn outbox, attrs ->
      outbox
      |> Outbox.changeset(attrs)
      |> repo.update!()
    end
  end

  defp process_outbox(outbox, functions) do
    case functions.query.(outbox) do
      [] -> {:ok, outbox}
      chunks -> process_chunks(chunks, outbox, functions)
    end
  end

  defp process_chunks([], outbox, functions) do
    process_outbox(outbox, functions)
  end

  defp process_chunks([chunk | rest], outbox, functions) do
    case process_chunk(chunk, outbox, functions) do
      {:cont, outbox} -> process_chunks(rest, outbox, functions)
      halt -> halt
    end
  end

  defp process_chunk(chunk, outbox, functions) do
    {cont_or_halt, result_opts} = functions.process.(chunk, outbox)

    defaults =
      if cont_or_halt == :cont do
        %{last_transaction_id: List.last(chunk).id}
      else
        %{}
      end

    results =
      result_opts
      |> Keyword.take([:memo, :last_transaction_id])
      |> Map.new()

    outbox = functions.update.(outbox, Map.merge(defaults, results))

    {cont_or_halt, outbox}
  end

  @type purge_option :: Carbonite.Query.outbox_done_option()

  @doc """
  Deletes transactions that have been fully processed.

  See `Carbonite.Query.outbox_done/1` for query options.

  Returns the number of deleted transactions.

  ## Parameters

  * `repo` - the Ecto repository
  * `opts` - optional keyword list

  ## Options

  * `min_age` - the minimum age of a record, defaults to 300 seconds (set nil to disable)
  * `carbonite_prefix` - defines the audit trail's schema, defaults to `"carbonite_default"`
  """
  @doc since: "0.4.0"
  @spec purge(repo()) :: {:ok, non_neg_integer()}
  @spec purge(repo(), [purge_option()]) :: {:ok, non_neg_integer()}
  def purge(repo, opts \\ []) do
    {deleted, nil} =
      opts
      |> Carbonite.Query.outbox_done()
      |> repo.delete_all()

    {:ok, deleted}
  end
end
