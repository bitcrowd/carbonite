<!-- SPDX-License-Identifier: Apache-2.0 -->

# Carbonite

[![Hex pm](http://img.shields.io/hexpm/v/carbonite.svg?style=flat)](https://hex.pm/packages/carbonite)
[![Hex docs](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/carbonite/Carbonite.html)
[![License](https://img.shields.io/hexpm/l/carbonite?style=flat)](https://www.apache.org/licenses/LICENSE-2.0)
<!-- [![CircleCI](https://circleci.com/gh/bitcrowd/carbonite.svg?style=shield)](https://circleci.com/gh/bitcrowd/carbonite) -->

Carbonite implements the [Change-Data-Capture](https://en.wikipedia.org/wiki/Change_data_capture) pattern on top of a PostgreSQL database and makes it available for Elixir applications. It uses triggers to automatically record all changes applied to a table in order to guarantee a complete audit trail of the contained data.

It is centered around the idea that the database transaction is the natural auditing unit of data mutation. Any mutation on a participating table requires the user first to record the operation metadata within the same database transaction. The metadata record is associated to the table change records by a constraint.

For instance, when a payment for a pending invoice is received, your application might create a record in the `payments` table and update the `invoices` record. Both of these mutations are recorded as a `Carbonite.Change` and are associated to a single `Carbonite.Transaction` which allows to correlate these mutations and provides (at least) a `type` attribute, e.g. `payment_received`.

## Features

- Easy to setup in a migration
- Guaranteed consistency based on foreign-key constraints and ACID
  - No mutation without recorded `Change`
  - No `Change` without `Transaction`
- Accessible Elixir interfaces to the audit data
- Optional processing & purging logic (Outbox pattern)

## Acknowledgements

The trigger-based table versioning draws inspiration from [`audit_trigger_91plus`](https://wiki.postgresql.org/wiki/Audit_trigger_91plus), an "example of a generic trigger function" hosted in the PostgreSQL wiki.

## Trigger vs. Write-Ahead-Log

Existing solutions for CDC on top of a PostgreSQL database (e.g., [Debezium](https://debezium.io/)) often tail the ["Write-Ahead-Log"](https://www.postgresql.org/docs/13/wal-intro.html) instead of using database logic & triggers to create change records. While this is supposedly more performant than using triggers, it makes it difficult to correlate changes on a transaction level as Carbonite does, and has different consistency guarantees. Carbonite makes this trade-off in favour of simplicity and universality. You should be able to run Carbonite's migrations on any hosted PostgreSQL instance without the need to tweak its configuration or install custom extensions before.

## Installation

### Requires PostgreSQL 13

This package requires PostreSQL version 13 or above due to its use of `pg_current_xact_id`. If you see an error message like the following, your Postgres installation is too old:

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

### Add Postgrex type for `xid8`

To load Postgres' `xid8` 64-bit type, we need to tell Postgrex to cast it to an Elixir integer.

```elixir
# lib/my_app/postgrex_types.ex

Postgrex.Types.define(
  MyApp.PostgrexTypes,
  [Carbonite.Postgrex.Xid8 | Ecto.Adapters.Postgres.extensions()],
  json: Jason
)
```

```elixir
# config/config.exs

config :carbonite, MyApp.Repo,
  types: MyApp.PostgrexTypes
```

### Create migrations

```sh
mix ecto.gen.migration InstallCarbonite
```

```elixir
# priv/repo/migrations/20210704201534_install_carbonite.exs

defmodule MyApp.Repo.Migrations.InstallCarbonite do
  use Ecto.Migration

  def up do
    Carbonite.Migrations.install()
    Carbonite.Migrations.install_trigger(:rabbits, excluded_columns: ["age"])
  end

  def down do
    Carbonite.Migrations.drop_trigger(:rabbits)
    execute("DROP SCHEMA carbonite_default;")
  end
end
```

## Usage

### With Ecto.Multi

```elixir
Ecto.Multi.new()
|> Carbonite.insert("rabbit_inserted")
|> Ecto.Multi.put(:params, %{name: "Jack", age: 99})
|> Ecto.Multi.insert(:rabbit, &MyApp.Rabbit.create_changeset(&1.params))
|> MyApp.transaction()
```

## Roadmap

### probably

* `purge`: Function that evicts records from the DB to be sent to external storage (event store), to be executed in recurrent job
* drop `Xid` postgrex type once postgrex has been released

### maybe

* table versioning: Optional version numbers for "main" tables (i.e. add a `version` field and a trigger `BEFORE UPDATE` that bumps it)
* `checksum`: Function that fetches non-checksum'ed transactions from DB and builds a checksum chain across them, to be executed in recurrent job
