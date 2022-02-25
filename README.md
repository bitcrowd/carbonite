<!-- SPDX-License-Identifier: Apache-2.0 -->

<p align="center">
  <a href="https://github.com/bitcrowd/carbonite">
    <img alt="carbonite" src="https://raw.githubusercontent.com/bitcrowd/carbonite/assets/logo/darkmode_stacked.png">
  </a>
</p>

<p align="center">
  <a href="https://hex.pm/packages/carbonite">
    <img alt="Hex pm" src="http://img.shields.io/hexpm/v/carbonite.svg?style=flat">
  </a>
  <a href="https://hexdocs.pm/carbonite/Carbonite.html">
    <img alt="Hexdocs" src="http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat">
  </a>
  <a href="https://www.apache.org/licenses/LICENSE-2.0">
    <img alt="License" src="https://img.shields.io/hexpm/l/carbonite?style=flat">
  </a>
  <a href="https://circleci.com/gh/bitcrowd/carbonite">
    <img alt="CircleCI" src="https://circleci.com/gh/bitcrowd/carbonite.svg?style=shield">
  </a>
</p>

<!-- MDOC -->

Carbonite makes it easy to create audit trails for tables in a PostgreSQL database and integrate them into an Elixir application.

Carbonite implements the [Change-Data-Capture](https://en.wikipedia.org/wiki/Change_data_capture) pattern on top of a PostgreSQL database. It uses triggers to automatically record all changes applied to a database table in order to guarantee a complete audit trail of the contained data.

It is centered around the idea that the database transaction is the natural auditing unit of data mutation. Any mutation on a participating table requires the developer first to record the operation metadata within the same database transaction. The metadata record is associated to the table change records by a constraint.

On top of its database layer, Carbonite provides an API allowing developers to effortlessly retrieve, process, and purge the audit trails within the Elixir application.

<!-- MDOC -->

## Features

- Convenient installation using migration functions
- Guaranteed consistency based on triggers, foreign-key constraints, and ACID
  - No mutation without recorded `Change`
  - No `Change` without `Transaction`
- Customizable audit metadata (per transaction)
- Clear query interfaces to the audit trail
- Optional processing & purging logic following the Outbox pattern
- Based on [Ecto](https://hex.pm/packages/ecto) and [Postgrex](https://hex.pm/packages/postgrex) with no further dependencies.
- No configuration of PostgreSQL database needed

<!-- MDOC -->

## How it works

Carbonite keeps a central `changes` table where all mutations of participating tables are recorded. On each such table a trigger is installed (after `INSERT`, `UPDATE`, and `DELETE` statements - `TRUNCATE` is not supported, see below) which calls a procedure stored within the database. This procedure captures the new or updated data within the `changes` table automatically. The procedure fetches its own per-table settings from another table called `triggers`. These settings customize the procedure's behaviour, for instance, they may exclude certain table columns from being captured.

Besides the `changes` table, storing information about individual database statements (or rather, their impact on the data), Carbonite's `transactions` table stores information on database _transactions_. Within your application logic, you can insert a row into this table after you begin a database transaction, and record arbitrary metadata for it.

Apart from the metadata, the `transactions` table houses two identifier columns: `id` and `xact_id`. While `id` is an ordinary, autoincrementing integer primary key, the `xact_id` is set to `pg_current_xact_id()`, PostgreSQL's internal transaction identifier. Each row in the `changes` table is associated to a single row in the `transactions` table, referencing *both these identifiers*.

- The `changes.transaction_id` (referencing `transactions.id`) field is filled with the ["current value"](https://www.postgresql.org/docs/13/functions-sequence.html) of the related sequence. This is your regular foreign key column, enough to relate a `changes` record with exactly one `transactions` record. Consistency with the `transactions` table is guaranteed by a foreign key constraint.
- Additionally, the `changes.transaction_xact_id` field is set to `pg_current_xact_id()`. Together these references ensure that, not only relates each `changes` record to a single `transactions` record, but records in these tables have been inserted *within the same database transaction*. Consistency is ensure by a manual lookup in the trigger procedure.

This leads to the following interesting properties:

- All `changes` created within a database transaction automatically and implicitly belong to the same record in the `transactions` table, even if they're created separately and agnostic of each other in the application logic. This gives the developer a "natural" way to group related changes into events (more on events later).
- The entry in the `transactions` table _must be created before any `changes`_. Attempting to modify an audited table without prior insertion into the `transactions` table will result in an error.

<h3>ℹ️ &ensp;Trigger vs. Write-Ahead-Log / Logical Decoding / Extensions</h3>

Existing solutions for CDC on top of a PostgreSQL database (e.g. [Debezium](https://debezium.io/)) often tail the [Write-Ahead-Log](https://www.postgresql.org/docs/13/wal-intro.html) or use extensions (e.g. [pgaudit](https://www.pgaudit.org/)) instead of using triggers to create change records. Both approaches have their own advantages and disadvantages, and one should try to understand the differences before making up their mind.

* One of the main selling points of triggers is that they are executed as part of the normal transaction logic in the database, hence they benefit from the usual [atomicity and consistency guarantees](https://en.wikipedia.org/wiki/ACID) of relational databases. For audit triggers, among other things this means that data mutations and their audit trail are committed as an atomic unit.
* At the same time, this property of triggers strongly couples the auditing logic to the business operation. For instance, if the audit trigger raises an error, the entire transaction is aborted. And vice versa, if the business operation aborts, nothing is audited.
* Additionally, auditing unavoidably has an impact on the database performance. A common criticism of audit triggers is the performance penalty they incur on otherwise "simple" database operations, which is said to be much higher than just tailing the WAL. Carbonite tries to limit the work done in its trigger, but a few indexes and tables are nonetheless touched.
* Another advantage of triggers is their universality: You should be able to run Carbonite's migrations on any hosted PostgreSQL instance without the need to tweak its configuration or install custom extensions before.
* The primary advantage of triggers for Carbonite, though, is that we can make use of PostgreSQL's internal transaction id: It allows us to group related changes together and record metadata for the group. This and the simple tooling around it is not (as easily) achievable with a fully decoupled system. However, if you do not need this feature of Carbonite, please be sure to consider other solutions as well.

<h3>ℹ️ &ensp;Why <code>TRUNCATE</code> is not supported</h3>

As the last of the 4 primary data mutating SQL commands, `TRUNCATE` allows to delete all data from a table or a set of tables. It can be instrumented using triggers on the statement level (`FOR EACH STATEMENT` instead of `FOR EACH ROW`), which means the trigger procedure executes only once for the statement and without any data - in contrast to, for instance, an `UPDATE` statement, which also mutates multiple rows but fires the procedure once for each row. While there might be value in auditing `TRUNCATE` statements, the behaviour of the trigger procedure would be quite different from the other commands. For a rarely used SQL command, we chose against this additional complexity and not to support `TRUNCATE` in Carbonite.

## Installation

### Requirements

Due to its use of [`pg_current_xact_id`](https://www.postgresql.org/docs/13/functions-info.html#FUNCTIONS-PG-SNAPSHOT), Carbonite requires PostgreSQL *version 13 or above*. If you see an error message like the following, your PostgreSQL installation is too old:

```
** (Postgrex.Error) ERROR 42704 (undefined_object) type "xid8" does not exist
```

### Hex dependency

```elixir
# mix.exs
def deps do
  [
    {:carbonite, "~> 0.5.0"}
  ]
end
```

## Getting started

As much of Carbonite's logic lives in database functions and triggers, to get started, we first need to create a migration using Ecto.

### Creating the initial migration

Carbonite contains a Mix task that generates the initial migration for you. Please open the generated file and edit it according to your needs.

See `Carbonite.Migrations` for more information on migrations.

```sh
mix carbonite.gen.initial_migration -r MyApp.Repo
```

The final migration should look something like this:

```elixir
# priv/repo/migrations/20210704201534_install_carbonite.exs
defmodule MyApp.Repo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(1)
    Carbonite.Migrations.up(2)
    Carbonite.Migrations.up(3)
    Carbonite.Migrations.up(4)

    # For each table that you want to capture changes of, you need to install the trigger.
    Carbonite.Migrations.create_trigger(:rabbits)

    # Optionally you may configure the trigger inside the migration.
    Carbonite.Migrations.put_trigger_config(:rabbits, :excluded_columns, ["age"])

    # Optional outbox to process transactions later.
    Carbonite.Migrations.create_outbox("rabbit_holes")
  end

  def down do
    # Remove outbox again.
    Carbonite.Migrations.drop_outbox("rabbit_holes")

    # Remove all triggers before dropping the schema.
    Carbonite.Migrations.drop_trigger(:rabbits)

    # Drop the Carbonite tables.
    Carbonite.Migrations.down(4)
    Carbonite.Migrations.down(3)
    Carbonite.Migrations.down(2)
    Carbonite.Migrations.down(1)
  end
end
```

### Updates

When a new Carbonite version is released, it may contain updates to the database schema. As these are announced in the [Changelog](CHANGELOG.md), you each time need to create a migration in your host application like the following.

```elixir
# priv/repo/migrations/20210704201534_update_carbonite.exs
defmodule MyApp.Repo.Migrations.UpdateCarbonite do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.up(3)
  end

  def down do
    Carbonite.Migrations.down(3)
  end
end
```

Applying multiple Carbonite migrations in a single host migration is fine. Note that for each of your Carbonite "partitions" (see below), you need to run each Carbonite migration.

### Trigger configuration

The behaviour of the capture trigger is customizable per table by manipulating the settings in the `triggers` table. Often you will want to update these settings within a migration, as well, which is why Carbonite provides the small helper function `Carbonite.Migrations.put_trigger_config/4` that updates the settings using plain SQL statements.

#### Primary Key Columns

To speed up version lookups for a specific record, Carbonite copies its primary key(s) to the `table_pk` column of the `changes` table. The table keeps an index on this column together with the table prefix and name.

By default, Carbonite will try to copy the `:id` column of the source table. If your table does not have a primary key, has a primary key with a different name, or has a composite primary key, you can override this using the `primary_key_columns` option.

```elixir
# Disable PK copying
Carbonite.Migrations.put_trigger_config(:rabbits, :primary_key_columns, [])

# Different name
Carbonite.Migrations.put_trigger_config(:rabbits, :primary_key_columns, ["identifier"])

# Composite PK
Carbonite.Migrations.put_trigger_config(:rabbits, :primary_key_columns, ["house", "apartment_no"])
```

Since the `changes` table keeps versions of a multitude of different source tables, primary keys are first cast to string (the `table_pk` column has type `VARCHAR[]`). For composite primary keys, set the `primary_key_columns` option to an array as shown above. Each component of a compound primary key will be cast to string before the components are joined into the array.

#### Excluded and Filtered Columns

In case your table contains sensitive data or data otherwise undesirable for change capturing, you can exclude columns using the `excluded_columns` option. Excluded columns will not appear in the captured data. If an `UPDATE` on a table solely touches excluded columns, the entire `UPDATE` will not be recorded.

```elixir
Carbonite.Migrations.put_trigger_config(:rabbits, :excluded_columns, ["age"])
```

If you still want to capture changes to a column (in the `changed` field), but don't need the exact data, you can make it a "filtered" column. These columns appear as `[FILTERED]` in the `data` field.

```elixir
Carbonite.Migrations.put_trigger_config(:rabbits, :filtered_columns, ["age"])
```

### Partitioning the Audit Trail

Carbonite can install its tables into multiple database schemas using the `carbonite_prefix` option. You can use this feature to "partition" your captured data.

```elixir
Carbonite.Migrations.up(1, carbonite_prefix: "carbonite_animals")
Carbonite.Migrations.create_trigger(:rabbits, carbonite_prefix: "carbonite_animals")
```

Basically all of Carbonite's functions accept the same `carbonite_prefix` option to target a particular partition. If desired, tables can participate in multiple partitions by adding multiple triggers on to them. Keep in mind that each partition will need to be processed and purged separately, resulting in multiple streams of change data in your external storage.

## Inserting a `Transaction`

In your application logic, before modifying an audited table like `rabbits`, you need to first create a `Carbonite.Transaction` record.

### With Ecto.Multi

The easiest way to do so is using `Carbonite.Multi.insert_transaction/2` within an `Ecto.Multi` operation:

```elixir
Ecto.Multi.new()
|> Carbonite.Multi.insert_transaction(%{meta: %{type: "rabbit_inserted"}})
|> Ecto.Multi.insert(:rabbit, &MyApp.Rabbit.create_changeset(&1.params))
|> MyApp.Repo.transaction()
```

As you can see, the `Carbonite.Transaction` is a great place to store metadata for the operation. A `type` field can be used to categorize the transactions. A `user_id` would be a good candidate for a transaction log, as well.

### Building a changeset for manual insertion

If you don't have the luxury of an `Ecto.Multi`, you can create a changeset for a `Carbonite.Transaction` using `Carbonite.Transaction.changeset/1`:

```elixir
MyApp.Repo.transaction(fn ->
  %{meta: %{type: "rabbit_inserted"}}
  |> Carbonite.Transaction.changeset()
  |> MyApp.Repo.insert!()

  # ...
end)
```

### Setting metadata outside of the transaction

In case you do not have access to metadata you want to persist in the `Carbonite.Transaction` at the code site where you create it, you can use `Carbonite.Transaction.put_meta/2` to store metadata in the _process dictionary_. This metadata is merged into the metadata given to `Carbonite.Multi.insert_transaction/2`.

```elixir
# e.g., in a controller or plug
Carbonite.Transaction.put_meta(:user_id, ...)
```

### Transactions in data migrations

If you manipulate data inside your transactions, as usual a `Carbonite.Transaction` needs to be inserted before any other statements. You can use `Carbonite.Migrations.insert_migration_transaction/1` to insert a transaction with a `meta` attribute populated from the migration module.


    import Carbonite.Migrations

    def change do
      insert_migration_transaction()

      execute("UPDATE ...")
    end

## Retrieving data

Of course, persisting the audit trail is not an end in itself. At some point you will want to read the data back and make it accessible to the user. `Carbonite.Query` offers a small suite of helper functions that make it easier to query the database for `Transaction` and `Change` records.

### Fetching transactions

The `Carbonite.Query.transactions/1` function constructs an `Ecto.Query` for loading `t:Carbonite.Transaction.t/0` records from the database, optionally preloading their included changes. The query can be further refined to limit the result set.

```elixir
Carbonite.Query.transactions()
|> Ecto.Query.where([t], t.inserted_at > ^earliest)
|> MyApp.Repo.all()
```

### Fetching changes of invididual records

The `Carbonite.Query.changes/2` function constructs an `t:Ecto.Query.t/0` from a schema struct, loading all changes stored for the given source record.

```elixir
%MyApp.Rabbit{id: 1}
|> Carbonite.Query.changes()
|> MyApp.Repo.all()
```

## Processing data

Storing event series in a relational database comes with the usual scaling issues, so at some point you may find it necessary to offload the captured data to an external data store. For processing, exporting, and later purging the captured transactions, Carbonite includes what is called an "Event Outbox", or in fact as many of those as you need.

Essentially, a `Carbonite.Outbox` is a named cursor on the ordered list of transactions stored in an audit trail. Each outbox advances by calling a user-supplied processor function on a batch of transactions. The batch can be filtered and limited in size, but is always ordered ascending by the transaction's `id` attribute, so transactions are processed *roughly* in order of their insertion (see below for a discussion on caveats of this solution). When a batch is processed, the outbox remembers its last position - the last transaction that has been processed - so the following call to the outbox can continue where the last has left of. Besides, the outbox persists a user-definable "memo", an arbitrary map that allows to feed output of the previous processor run into the next one.

### Creating an Outbox

Create an outbox within a migration:

```elixir
Carbonite.Migrations.create_outbox("rabbit_holes")
```

You can create more than one outbox if you need multiple processors, e.g. for multiple target systems for your data.

### Processing

You can process an outbox by calling `Carbonite.process/4` with the outbox name and a processor callback function.

```elixir
Carbonite.process(MyApp.Repo, "rabbit_holes", fn transactions, _memo ->
  for transaction <- transactions do
    send_to_external_database(transaction)
  end

  :cont
end)
```

In practise, you will almost always want to run this within an asynchronous job processor. The following shows an exemplary [Oban](https://github.com/sorentwo/oban) worker:


```elixir
# config/config.exs
config :my_app, :oban,
  repo: MyApp.Repo,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"0 0 * * *", MyApp.PeriodicOutboxWorker, args: %{outbox: "rabbit_holes"}}
    ]
  ]

# lib/my_app/periodic_outbox_worker.ex
defmodule MyApp.PeriodicOutboxWorker do
  # Worker is scheduled every 24h, let's make it unique for 12h to be sure.
  # Retry is disabled, the next scheduled run will pick up failed outboxes.
  use Oban.Worker, queue: :default, unique: [period: 43_200], retry: false

  def perform(%Oban.Job{args: %{"outbox" => outbox}}) do
    Carbonite.process(MyApp.Repo, outbox, fn transactions, _memo ->
      for transaction <- transactions do
        send_to_external_database(transaction)
      end

      :cont
    end)
  end
end
```

<h4>⚠️&ensp;Transactionality & mutual exclusion</h4>

As the outbox processor is likely to call external services as part of its work, `Carbonite.process/4` does not begin a transaction itself, and consequently does not acquire a lock on the outbox record. In other words, users have to ensure that they don't accidentally run `Carbonite.process/4` for the same outbox concurrently, for instance making use of uniqueness options of the used job processor (e.g. [`unique` in Oban](https://hexdocs.pm/oban/Oban.html#module-unique-jobs)).

The absence of transactionality also means that any exception raised within the processor function will immediately abort the `Carbonite.process/4` call without writing the current outbox position to disk. As a result, transactions may be processed again in the next run. Please make sure your receiving system or database can handle duplicate messages.

<h4>⚠️&ensp;Long running / parallel transactions and the outbox order</h4>

When a `Carbonite.Transaction` record is created at the beginning of an operation in your application, it records the "current" sequence value in its `id` field. The record in the `transactions` table becomes visible to other transactions when the current transaction is committed.

A few observations can be made from this:

* When ordered by their `id` field, the transactions will be roughly sorted by the time the corresponding operation was started, not when it was committed.
* Two transactions running in parallel may be committed "out of order", i.e. one with the larger `id` may be committed before the smaller `id` transaction if that has a longer runtime.

The latter point is crucial: For instance, if two transactions with `id=1` and `id=2` run in parallel and `id=2` finishes before `id=1`, an outside viewer can already see `id=2` in the database before `id=1` is committed. If this outside viewer happens to be an outbox processing job, transaction with `id=1` might be skipped and never looked at again. To mitigate this issue, `Carbonite.process/4` has a `min_age` option which excludes transaction younger than a certain from the processing batch (5 minutes by default, increase this is you expect longer running transactions).

### Purging

Now that you have successfully exported your audit data, you may delete old transactions from the primary database. `Carbonite.purge/2` deletes records that have been processed by all existing outboxes.

```elixir
# Deletes records whose id field is less than the transaction_id on each outbox.
Carbonite.purge(MyApp.Repo)
```

## Testing / Bypassing Carbonite

One of Carbonite's key features is that it is virtually impossible to forget to record a change to a table (due to the trigger) or to forget to insert an enclosing `Carbonite.Transaction` beforehand (due to the foreign key constraint between `changes` and `transactions`). However, in some circumstances it may be desirable to temporarily switch off change capturing. One such situation is the use of factories (e.g. ExMachina) inside your test suite: Inserting a transaction before each factory call quickly becomes cumbersome and will unnecessarily increase execution time.

To bypass the capture trigger, Carbonite's trigger configuration provides a toggle mechanism consisting of two fields: `mode` and `override_xact_id`. The former you set while installing the trigger on a table in a migration, while the latter allows to "override" whatever has been set at runtime, and only for the current transaction. If you are using Ecto's SQL sandbox for running transactional tests, this means the override is going to be active until the end of the test case.

As a result, you have two options:

1. Leave the `mode` at the default value of `:capture` and *turn off* capturing as needed by switching to "override mode". This means for every test case where you do not care about change capturing, you explicitly disable the trigger before any database calls; for instance, in an ExUnit setup block. This approach has the benefit that you still capture all changes by default, and can't miss to test a code path that (in production) would require a `Carbonite.Transaction`. It is, however, still pretty expensive at ~1 additional SQL call per test case.
2. Set the `mode` to `:ignore` on all triggers in your `:test` environment and instead selectively *turn on* capturing in test cases where you want to assert on the captured data. For instance, you can set the trigger mode in your migration based on the Mix environment. This approach is cheaper as it does not require any action in your tests by default. Yet you should make sure that you test all code paths that do mutate change-captured tables, in order to assert that each of these inserts a transaction as well.

The following code snippet illustrates the second approach:

```elixir
# config/config.exs
config :my_app, carbonite_mode: :capture

# config/test.exs
config :my_app, carbonite_mode: :ignore

# priv/repo/migrations/000000000000_install_carbonite.exs
defmodule MyApp.Repo.Migrations.InstallCarbonite do
  @mode Application.compile_env!(:my_app, :carbonite_mode)

  def up do
    # ...
    Carbonite.Migrations.create_trigger(:rabbits)
    Carbonite.Migrations.put_trigger_config(:rabbits, :mode, @mode)
  end
end

# test/support/carbonite_helpers.exs
defmodule MyApp.CarboniteHelpers do
  def carbonite_override_mode(_) do
    Carbonite.override_mode(MyApp.Repo)

    :ok
  end

  def current_transaction_meta do
    Carbonite.Query.current_transaction()
    |> MyApp.Repo.one!()
    |> Map.fetch(:meta)
  end
end

# test/some_test.exs
describe "my_operation/0"
  setup [:carbonite_override_mode]

  test "auditing" do
    my_operation()

    assert current_transaction_meta() == %{"type" => "some_operation"}
  end
end
```

<!-- MDOC -->

## Acknowledgements

### Inspiration

The trigger-based table versioning derives from [`audit_trigger_91plus`](https://wiki.postgresql.org/wiki/Audit_trigger_91plus), an "example of a generic trigger function" hosted in the PostgreSQL wiki.

### Artwork

The amazing Carbonite logo has been designed by [Petra Herberger](https://www.petra-herberger.de/). Thank you! 💜

## Copyright and License

Copyright © 2021, Bitcrowd GmbH.

You may use and redistribute Carbonite and its source code under the Apache 2.0 License, see the
[LICENSE](LICENSE) file for details.
