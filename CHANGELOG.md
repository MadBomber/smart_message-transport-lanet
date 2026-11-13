## [Unreleased]

- Subscribing with a message Class (not just its name) now receives inbound messages; `network_topology[:active_subscriptions]` lists class-name Strings. (#2)
- `connect` or `configure` after `disconnect` no longer leaves the transport stopped: `configure` now clears the shutdown flag that `disconnect` sets.
- Tests no longer require ostruct (gone from Ruby 4 default gems) and require minitest/mock explicitly instead of relying on minitest 5 autorun to load it.
- Added GitHub Actions CI running `rake test`
- Relocked dev dependencies so `bundle install` works on Ruby 4, and CI now also runs on Ruby 4.0
- A blank numeric `LANET_*` environment variable now falls back to the default instead of becoming zero. (#10)
- Declared `logger` as a runtime dependency; it is a bundled gem, not a default gem, on Ruby 4. (#11)
- An inbound `smart_message` with no payload is now ignored instead of passing the envelope's `inspect` string to `receive`. (#15)

## [0.0.1] - 2025-09-03

- Initial release
