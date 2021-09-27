## Unreleased

### Added

* Store primary key(s) on changes table and index them
* Add `Carbonite.Query` module
  - `current_transaction/2` allows to fetch the ongoing transaction (for sandbox tests)
  - `changes/2` allows to fetch the changes of an invidual source record
* Update Postgrex to 0.15.11 and drop local `Xid8` type

## [0.1.0] - 2021-09-01

* Initial release.
