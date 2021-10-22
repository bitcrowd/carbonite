## [0.3.0] - 2021-10-22

### Added

* `Carbonite.Migrations.drop_tables/1` allows to drop the carbonite audit trail without removing the schema

### Changed

* Renamed the option that can be passed to `Carbonite.Migrations.drop_schema/1` from `prefix` to `carbonite_prefix`
* Changed `Carbonite.Migrations.drop_schema/1` to also drop the tables
* Made `Carbonite.Multi.insert_transaction/3` ignore conflicting `INSERT`s within the same transaction.
* Also, changed `Carbonite.Multi.insert_transaction/3` to always reloads all fields from the database after insertion, immediately returning the JSONinified `meta` payload.

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
