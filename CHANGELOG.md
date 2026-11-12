## [Unreleased]

- `connect` or `configure` after `disconnect` no longer leaves the transport stopped: `configure` now clears the shutdown flag that `disconnect` sets.
- Tests no longer require ostruct (gone from Ruby 4 default gems) and require minitest/mock explicitly instead of relying on minitest 5 autorun to load it.
- Added GitHub Actions CI running `rake test`

## [0.0.1] - 2025-09-03

- Initial release
