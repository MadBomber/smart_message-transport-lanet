## [Unreleased]

- Tests no longer require ostruct (gone from Ruby 4 default gems) and require minitest/mock explicitly instead of relying on minitest 5 autorun to load it.
- Added GitHub Actions CI running `rake test`
- Relocked dev dependencies so `bundle install` works on Ruby 4, and CI now also runs on Ruby 4.0

## [0.0.1] - 2025-09-03

- Initial release
