# Parse Performance Benchmark

**Date**: 2026-04-01
**Status**: Design
**Issue**: Section 11 of dfa-factored-earley-parser design doc

## Problem

The design doc Section 11 specifies performance analysis methodology but no
benchmark implementation exists. The stats tracking infrastructure is in place
(`scan_stats`, `gc_stats`, `set_reuse_stats` fields in Earley.pm) but no
harness collects and reports the numbers.

## Solution

A TAP test file at `t/benchmark/parse-performance.t` that measures parse
performance in two modes:

**Mode 1: Single-file detail** — Parse `Boolean.pm` (~200 lines) with full
FilterComposite semiring. Report wall-clock time, operation counts (scan
matches, cache hits, clustered scans, GC positions freed, safe sets found,
set reuse hits/unique), file size.

**Mode 2: Multi-file throughput** — Parse every parseable `.pm` file in
`lib/Chalk/Bootstrap/Semiring/`. Aggregate total bytes, total time,
bytes/second throughput.

Both modes run twice: once with pure-Perl Earley, once with XS-compiled
Earley (if `chalk.so` has been built via `script/build-chalk-so-generated`).

## Skip Behavior

Skipped unless `CHALK_BENCHMARK=1` is set. Benchmarks are slow.

## Assertions

- Pure-Perl parse completes without error
- Operation counts are positive (parser did work)
- If XS available: XS parse time <= Perl parse time (C must not be slower)
- No hard speedup ratio — hardware varies

## Output

Detailed `diag` lines with timings, operation counts, and speedup ratios.
Human-readable report format for manual inspection.
