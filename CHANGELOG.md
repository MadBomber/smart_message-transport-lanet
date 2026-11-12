## [Unreleased]

- Subscribing with a message Class (not just its name) now receives inbound messages; `network_topology[:active_subscriptions]` lists class-name Strings. (#2)
- Tests no longer require ostruct (gone from Ruby 4 default gems) and require minitest/mock explicitly instead of relying on minitest 5 autorun to load it.
- Added GitHub Actions CI running `rake test`

## [0.0.1] - 2025-09-03

- Initial release
