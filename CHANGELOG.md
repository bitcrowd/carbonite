## Unreleased

**New migration patches:** 5

### Added

* Optional tracking of previous data in changes. Set the `store_changed_from` trigger option.

## [0.5.0] - 2022-02-25

**New migration patches:** 4

### Switch to normal identity column on `transactions`

* The `id` column on `transactions` has been replaced with an ordinary autoincrementing integer PK, filled from a sequence. Next to it a new `xact_id` column continues to store the transaction id (from `pg_current_xact_id`). Both values used together ensure that, first the `id` is monotonically increasing and survives a backup restore (see issue #45), and second the `changes` records can still only be inserted within the same transaction.

### Added

* `Carbonite.Migrations.insert_migration_transaction/1` and its macro friend, `insert_migration_transaction_after_begin`, help with data migrations.
* `Carbonite.fetch_changes` returns the changes of the current (ongoing) transaction.

## [0.4.0] - 2021-11-07

**New migration patches:** 2, 3

### Switch to top-level API with `repo` param

* `Carbonite.override_mode/2` (kept a wrapper in `Carbonite.Multi`)
* `Carbonite.insert_transaction/3` (kept a wrapper in `Carbonite.Multi`)
* `Carbonite.process/4` (previously `Carbonite.Outbox.process/3` with major changes)
* `Carbonite.purge/2` (previously `Carbonite.Outbox.purge/1` with major changes)

### Big outbox overhaul

* Split into query / processing
* Simplify processing
* No more transaction
* New capabilities: memo, halting, chunking

### Migration versioning

* Explicit for now with `Carbonite.Migrations.up(non_neg_integer())`
* `Carbonite.Migrations.install_schema/1` is now `Carbonite.Migrations.up/2`
* `Carbonite.Migrations.put_trigger_option/4` to ensure old migrations continue to work
* At the same time removed long configuration statement from `Carbonite.Migrations.install_trigger/1`, so this does not need to be versioned and continues to work
* Mix task for generating the "initial" migration

### Other Changes

* Optionally derive Jason.Encoder for `Carbonite.Transaction` and `Carbonite.Change`
* Made all prefix options binary-only (no atom) as `Ecto.Query.put_query_prefix/2` only accepts strings

## [0.3.1] - 2021-10-23

### Added

* `table_prefix` option to `Query.changes/2` allows to override schema prefix of given record
* `Query.transactions/1` query selects all transactions

## [0.3.0] - 2021-10-22

### Added

* `Carbonite.Migrations.drop_tables/1` allows to drop the carbonite audit trail without removing the schema

### Changed

* Renamed the option that can be passed to `Carbonite.Migrations.drop_schema/1` from `prefix` to `carbonite_prefix`
* Changed `Carbonite.Migrations.drop_schema/1` to also drop the tables
* Made `Carbonite.Multi.insert_transaction/3` ignore conflicting `INSERT`s within the same transaction
* Also, changed `Carbonite.Multi.insert_transaction/3` to always reloads all fields from the database after insertion, immediately returning the JSONinified `meta` payload

### Fixed

* Fixed ignore mode when `override_transaction_id` is NULL

## [0.2.1] - 2021-10-10

### Fixed

* Fixed broken documentation

## [0.2.0] - 2021-10-10

### Added

* Store primary key(s) on changes table and index them
* Add `Carbonite.Query` module
  - `current_transaction/2` allows to fetch the ongoing transaction (for sandbox tests)
  - `changes/2` allows to fetch the changes of an invidual source record
* Update Postgrex to 0.15.11 and drop local `Xid8` type
* Add `mode` field to trigger (capture or ignore)
* Add "override mode" reversing the `mode` option for the current transaction to enable/disable capturing on demand (e.g. in tests)
* Add filtered columns

### Changed

* Moved top-level functions to nested modules `Transaction` and `Multi`
* Made `table_pk` be `NULL` when `primary_key_columns` is an empty array
* Default `primary_key_columns` to `["id"]`
* Renamed `prefix` option to `carbonite_prefix` on `install_schema/2` for consistency

## [0.1.0] - 2021-09-01

* Initial release.
