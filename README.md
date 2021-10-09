<!-- SPDX-License-Identifier: Apache-2.0 -->

<p align="center">
  <a href="https://github.com/bitcrowd/carbonite">
    <img alt="carbonite" src="https://raw.githubusercontent.com/bitcrowd/carbonite/assets/logo/rgb_stacked.png">
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

Carbonite makes it easy to create audit trails for tables in a PostgreSQL database and integrate them into an Elixir application.

Carbonite implements the [Change-Data-Capture](https://en.wikipedia.org/wiki/Change_data_capture) pattern on top of a PostgreSQL database. It uses triggers to automatically record all changes applied to a database table in order to guarantee a complete audit trail of the contained data.

It is centered around the idea that the database transaction is the natural auditing unit of data mutation. Any mutation on a participating table requires the developer first to record the operation metadata within the same database transaction. The metadata record is associated to the table change records by a constraint.

On top of its database layer, Carbonite provides an API allowing developers to effortlessly retrieve, process, and purge the audit trails within the Elixir application.

---

<p align="center">🚧 This is work-in-progress and not yet ready to be used 🚧</p>

---

## Features

- Convenient installation using migration functions
- Guaranteed consistency based on foreign-key constraints and ACID
  - No mutation without recorded `Change`
  - No `Change` without `Transaction`
- Customizable audit metadata (per transaction)
- Clear query-based interfaces to the audit trail
- Optional processing & purging logic following the Outbox pattern
- Based on [Ecto](https://hex.pm/packages/ecto) and [Postgrex](https://hex.pm/packages/postgrex) with no further dependencies.
- No configuration of PostgreSQL database needed

## Installation

### Requirements

Due to its use of [`pg_current_xact_id`](https://www.postgresql.org/docs/13/functions-info.html#FUNCTIONS-PG-SNAPSHOT), Carbonite requires ⚠️ PostgreSQL version 13 or above ⚠️. If you see an error message like the following, your PostgreSQL installation is too old:

```
** (Postgrex.Error) ERROR 42704 (undefined_object) type "xid8" does not exist
```

### Hex dependency

```elixir
# mix.exs

def deps do
  [
    {:carbonite, "~> 0.1.0"}
  ]
end
```

## Usage

<!-- MDOC -->

Carbonite implements the [Change-Data-Capture](https://en.wikipedia.org/wiki/Change_data_capture) pattern on top of PostgreSQL using database triggers. It keeps a central `changes` table where all mutations of participating tables are recorded. Each `changes` row is associated to a single row in the `transactions` table using PostgreSQL's _internal transaction id_ as the foreign key. This leads to the following interesting properties:

- All `changes` created within a database transaction automatically and implicitly belong to the same record in the `transactions` table, even if they're created separatedly and agnostic of each other in the application logic. This gives the developer a "natural" way to group related changes into events (more on events later).
- As the `changes` table is associated to the `transactions` table via a non-nullable foreign key constraint, the entry in the `transactions` table _must be created before any `changes`_. Attempting to modify a versioned table without prior insertion into the `transactions` table will result in an error. The `transactions` table carries transactional metadata which can be set by the developer on creation.

Consequently, much of Carbonite's logic lives in database functions and triggers. To get started, we need to create a migration using Ecto.

---

ℹ️ **Trigger vs. Write-Ahead-Log**

Existing solutions for CDC on top of a PostgreSQL database (e.g., [Debezium](https://debezium.io/)) often tail the ["Write-Ahead-Log"](https://www.postgresql.org/docs/13/wal-intro.html) instead of using database logic & triggers to create change records. While this is likely more performant than using triggers, it makes it difficult to correlate changes on a transaction level as Carbonite does, and has different consistency guarantees. Carbonite makes this trade-off in favour of simplicity and universality. You should be able to run Carbonite's migrations on any hosted PostgreSQL instance without the need to tweak its configuration or install custom extensions before.


## Installing the schema & triggers

The following migration installs Carbonite into its "default prefix", a PostgreSQL _schema_ aptly called `carbonite_default`, and installs the change capture trigger for an exemplary table called `rabbits` (in the `public` schema). In a real-world scenario, you will most likely want to install the trigger for a set of tables and optionally split the audit trail into multiple partitions.

See `Carbonite.Migrations` for more information on migrations.

```sh
mix ecto.gen.migration InstallCarbonite
```

```elixir
# priv/repo/migrations/20210704201534_install_carbonite.exs

defmodule MyApp.Repo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def up do
    # Creates carbonite_default schema and tables.
    Carbonite.Migrations.install_schema()

    # For each table that you want to capture changes of, you need to install the trigger.
    Carbonite.Migrations.install_trigger(:rabbits)
  end

  def down do
    # Remove all triggers before dropping the schema.
    Carbonite.Migrations.drop_trigger(:rabbits)

    # Drop the schema & tables.
    Carbonite.Migrations.drop_schema()
  end
end
```

#### Primary Key Columns

To speed up version lookups for a specific record, Carbonite copies its primary key(s) to the `table_pk` column of the `changes` table. The table keeps an index on this column together with the table prefix and name.

By default, Carbonite will try to copy the `:id` column of the source table. If your table does not have a primary key, has a primary key with a different name, or has a composite primary key, you can override this using the `primary_key_columns` option of `Carbonite.Migrations.install_trigger/2` and `Carbonite.Migrations.configure_trigger/2`.

```elixir
# Disable PK copying
Carbonite.Migrations.install_trigger(:rabbits, primary_key_columns: [])

# Different name
Carbonite.Migrations.install_trigger(:rabbits, primary_key_columns: ["identifier"])

# Composite PK
Carbonite.Migrations.install_trigger(:rabbits, primary_key_columns: ["house", "apartment_no"])
```

Since the `changes` table keeps versions of a multitude of different source tables, the `table_pk` column has type `VARCHAR` and primary keys are first cast to string. For composite primary keys, set the `primary_key_columns` option to an array as shown above. Each component of a compound primary key will be cast to string before the components are joined to a single string by `|`.

#### Excluded  and Filtered Columns

In case your table contains sensitive data or data otherwise undesirable for change capturing, you can exclude columns using the `excluded_columns` option. Excluded columns will not appear in the captured data. If an `UPDATE` on a table solely touches excluded columns, the entire `UPDATE` will not be recorded.

```elixir
Carbonite.Migrations.install_trigger(:rabbits, excluded_columns: ["age"])
```

If you still want to capture changes to a column (in the `changed` field), but don't need the exact data, you can make it a "filtered" column. These columns appear as `"[FILTERED]" in the `data` field.

```elixir
Carbonite.Migrations.install_trigger(:rabbits, filtered_columns: ["age"])
```

If you forgot to exclude a column, you can reconfigure a trigger for a particular table using `configure_trigger/2`:

```elixir
# in another migration
Carbonite.Migrations.configure_trigger(:rabbits, excluded_columns: ["age"])
```

#### Partitioning the Audit Trail

Carbonite can install its tables into multiple database schemas using the `prefix` option. You can use this feature to "partition" your captured data.

```elixir
Carbonite.Migrations.install_schema(carbonite_prefix: "carbonite_lagomorpha")
Carbonite.Migrations.install_trigger(:rabbits, carbonite_prefix: "carbonite_lagomorpha")
```

If desired, tables can participate in multiple partitions by adding multiple triggers on to them.

Keep in mind that each partition will need to be processed and purged separately, resulting in multiple streams of change data in your external storage.

## Inserting a Transaction

In your application logic, before modifying a versioned table like `rabbits`, you need to first create a `Carbonite.Transaction` record.

### With Ecto.Multi

The easiest way to do so is using `Carbonite.Multi.insert_transaction/2` within an `Ecto.Multi` operation:

```elixir
Ecto.Multi.new()
|> Carbonite.Multi.insert_transaction(%{meta: %{type: "rabbit_inserted"}})
|> Ecto.Multi.insert(:rabbit, &MyApp.Rabbit.create_changeset(&1.params))
|> MyApp.Repo.transaction()
```

As you can see, the `Carbonite.Transaction` is a great place to store metadata for the operation. A "transaction type" would be an obvious choice to categorize the transactions. A `user_id` would be a good candidate for an transaction log, as well.

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

### Setting metadata outside of the Transaction

In case you do not have access to metadata you want to persist in the `Carbonite.Transaction` at the code site where you create it, you can use `Carbonite.Transaction.put_meta/2` to store metadata in the _process dictionary_. This metadata is merged into the metadata given to `Carbonite.Multi.insert_transaction/2`.

```elixir
# e.g., in a controller or plug
Carbonite.Transaction.put_meta(:user_id, ...)
```

## Retrieving data

Of course, persisting the audit trail is not an end in itself. At some point you will want to read the data back and make it accessible to the user. `Carbonite.Query` offers a small suite of helper functions that make it easier to query the database for `Transaction` and `Change` records.

### Fetching Changes

The `Carbonite.Query.changes/2` function constructs an `Ecto.Query` from a schema struct, loading all changes stored for the given source record.

```elixir
%MyApp.Rabbit{id: 1}
|> Carbonite.Query.changes()
|> MyApp.Repo.all()
```

## Testing / Bypassing Carbonite

One of Carbonite's key features is that it is virtually impossible to forget to record a change to a table (due to the trigger) or to forget to insert an enclosing `Carbonite.Transaction` beforehand (due to the foreign key constraint between `changes` and `transactions`). However, in some circumstances it may be desirable to temporarily switch off change capturing. One such situation is the use of factories (e.g. ExMachina) inside your test suite: Inserting a transaction before each factory call quickly becomes cumbersome and will unnecessarily increase execution time.

To bypass the capture trigger, Carbonite's trigger configuration provides a toggle mechanism consisting of two fields: `mode` and `override_transaction_id`. The former you set while installing the trigger on a table in a migration, while the latter allows to "override" whatever has been set at runtime, and only for the current transaction. If you are using Ecto's SQL sandbox for running transactional tests, this means the override is going to be active until the end of the test case.

As a result, you have two options:

1. Leave the `mode` at the default value of `:capture` and *turn off* capturing as needed by switching to "override mode". This means for every test case where you do not care about change capturing, you explicitly disable the trigger before any database calls; for instance, in a ExUnit setup block. This approach has the benefit that you still capture all changes by default, and can't miss to test a code path that (in production) would require a `Carbonite.Transaction`. It is, however, still pretty expensive at ~1 additional SQL call per test case.
2. Set the `mode` to `:ignore` on all triggers in your `:test` environment and instead selectively *turn on*  capturing in test cases where you want to assert on the captured data. For instance, you can set the trigger mode in your migration based on the Mix environment. This approach is cheaper as it does not require any action in your tests by default. Yet you should make sure that you test all code paths that do mutate change-captured tables, in order to assert that each of these inserts a transaction as well.

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
    Carbonite.Migrations.install_trigger(:rabbits, mode: @mode)
  end
end

# test/support/carbonite_helpers.exs
defmodule MyApp.CarboniteHelpers do
  def carbonite_override_mode(_) do
    Ecto.Multi.new()
    |> Carbonite.Multi.override_mode()
    |> MyApp.Repo.transaction()

    :ok
  end
end

# test/some_test.exs
def SomeTest do
  use MyApp.DataCase
  import MyApp.CarboniteHelpers

  setup [:carbonite_override_mode]
end
```

<!-- MDOC -->

## Acknowledgements

### Inspiration

The trigger-based table versioning derives from [`audit_trigger_91plus`](https://wiki.postgresql.org/wiki/Audit_trigger_91plus), an "example of a generic trigger function" hosted in the PostgreSQL wiki.

### Artwork

The amazing Carbonite logo has been designed by [Petra Herberger](https://www.petra-herberger.de/). Thank you! 💜
