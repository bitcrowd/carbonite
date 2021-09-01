# SPDX-License-Identifier: Apache-2.0

defmodule Carbonite.Outbox do
  @moduledoc """
  Implements the outbox pattern to process (and evict) recorded transactions in the database,
  in order of insertion.
  """

  import Carbonite, only: [default_prefix: 0]
  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [from: 2]
  import Ecto.Adapters.SQL, only: [query!: 3]
  alias Carbonite.Transaction
  alias Ecto.Multi

  @default_batch_size 20
  @default_min_age 300

  @type process_fun :: (repo :: module(), Transaction.t() -> {:ok, any()} | {:error, any()})
  @type process_option ::
          {:batch_size, non_neg_integer()} | {:min_age, non_neg_integer()} | {:prefix, String.t()}

  @doc """
  Builds an `Ecto.Multi` that can be used to load `Carbonite.Transaction` records from database
  (in order of insertion) and process them one-by-one through a function.

  Processed items are marked as processed and can be purged.

  ## Options

  * `batch_size` is the size of records to load in one chunk, defaults to 20
  * `min_age` is the minimum age of a record, defaults to 300 seconds (see below)
  * `prefix` is the Carbonite schema, defaults to `"carbonite_default"`

  ## Long running transactions & insertion order

  A warning: As `Carbonite.Transaction` records are inserted at the beginning of a database
  transaction, their `inserted_at` is already a bit in the past when they become visible to other
  connections, e.g. to your processing job. This means that in case of long running transactions,
  `Carbonite.Transaction` records with more recent `inserted_at` values might be processed before
  older ones, and hence the eventual total order of `inserted_at` in the processed records can
  not be guaranteed. To mitigate this issue, Carbonite will by default exclude records younger than
  `min_age` seconds from processing. Tweak this setting if you have even longer transactions.
  """
  @spec process(process_fun()) :: Ecto.Multi.t()
  @spec process([process_option()], process_fun()) :: Ecto.Multi.t()
  def process(opts \\ [], process_fun) do
    Multi.new()
    |> Multi.put(:batch_size, Keyword.get(opts, :batch_size, @default_batch_size))
    |> Multi.put(:min_age, Keyword.get(opts, :min_age, @default_min_age))
    |> Multi.put(:prefix, Keyword.get(opts, :prefix, default_prefix()))
    |> Multi.put(:process_fun, process_fun)
    |> Multi.run(:advisory_xact_lock, &acquire_advisory_xact_lock/2)
    |> Multi.run(:batch, &load_batch/2)
    |> Multi.merge(&reduce_batch/1)
  end

  defp acquire_advisory_xact_lock(repo, %{prefix: prefix}) do
    <<key::signed-integer-64, _rest::binary>> = :crypto.hash(:sha, to_string(prefix))

    {:ok, query!(repo, "SELECT pg_advisory_xact_lock($1);", [key])}
  end

  defp load_batch(repo, %{batch_size: batch_size, min_age: min_age, prefix: prefix}) do
    min_inserted_at = DateTime.add(DateTime.utc_now(), -1 * min_age, :second)

    {:ok,
     from(t in Transaction,
       where: is_nil(t.processed_at) and t.inserted_at < ^min_inserted_at,
       order_by: {:asc, t.inserted_at},
       limit: ^batch_size,
       preload: [:changes]
     )
     |> repo.all(prefix: prefix)}
  end

  defp reduce_batch(%{batch: batch, process_fun: process_fun}) do
    Enum.reduce(batch, Multi.new(), fn %Transaction{id: id} = tx, acc ->
      acc
      |> Multi.put("tx-loaded:#{id}", tx)
      |> Multi.run("tx-processed:#{id}", fn repo, state ->
        process_fun.(repo, Map.fetch!(state, "tx-loaded:#{id}"))
      end)
      |> Multi.update("tx-updated:#{id}", fn state ->
        change(Map.fetch!(state, "tx-loaded:#{id}"), %{processed_at: DateTime.utc_now()})
      end)
    end)
  end

  @type purge_option :: {:prefix, binary()}

  @doc """
  Builds an `Ecto.Multi` that can be used to delete `Carbonite.Transaction` records and their
  associated `Carbonite.Change` rows from the database once they have been successfully processed
  using `process/2`.

  ## Options

  * `prefix` is the Carbonite schema, defaults to `"carbonite_default"`
  """
  @spec purge() :: Ecto.Multi.t()
  @spec purge([purge_option()]) :: Ecto.Multi.t()
  def purge(opts \\ []) do
    Multi.new()
    |> Multi.put(:prefix, Keyword.get(opts, :prefix, default_prefix()))
    |> Multi.run(:purged, fn repo, %{prefix: prefix} ->
      from(t in Transaction, where: not is_nil(t.processed_at))
      |> repo.delete_all(prefix: prefix)
    end)
  end
end
