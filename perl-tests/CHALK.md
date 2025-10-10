# Perl Test Suite for Chalk

This directory contains a partial checkout of the Perl 5 test suite from https://github.com/Perl/perl5.git.

## Purpose

These tests are used to validate that Chalk can parse real-world Perl code. The goal is not to execute the tests (yet), but to ensure Chalk's parser can handle the syntax found in Perl's own test suite.

## Test Structure

Per the upstream `README`, tests should be tackled in this order:

1. **`base/`** - Most basic tests, runnable with miniperl alone
   - Must not use `require`, `Config.pm`, `strict`, or `warnings`
   - These sanity test the rest of the test framework
   - **Start here** for Chalk parsing validation

2. **`comp/`** - Compilation tests, validate that `require` works
   - Run after base/ tests pass

3. **`run/`** - Runtime tests, validate that `-M` flag works
   - Run after comp/ tests pass

4. **Other directories** can be tackled after the above:
   - `cmd/` - Command-line flags and options
   - `io/` - I/O operations
   - `op/` - Operators
   - `uni/` - Unicode
   - `lib/` - Library tests
   - `class/` - Modern Perl class syntax tests (5.38+)
   - And many more...

## Usage with Chalk

To test Chalk's parsing of these files:

```bash
# Parse a single test
chalk parse perl-tests/base/cond.t

# Parse all base tests
find perl-tests/base -name "*.t" -exec chalk parse {} \;
```

## Updating

This directory was added using `git read-tree` from the perl5 repository. To update to the latest perl5 tests:

```bash
# Fetch latest perl5
git fetch perl5 blead

# Update perl-tests/ to latest t/ directory
git rm -rf perl-tests/
git read-tree --prefix=perl-tests/ -u perl5/blead:t
git commit -m "Update perl-tests to latest perl5 blead:t"
```

## Statistics

As of the initial import:
- **619 total test files** (`.t` files)
- **8 test files in base/** (the foundation)
- Tests span from basic syntax to advanced Perl features

## See Also

- Upstream README: `perl-tests/README`
- Issue #12: Track progress on parsing repository files
