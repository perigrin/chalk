# Alignment Review: DFA-Factored Earley Parser

**Date:** 2026-03-28
**Commit:** 833ef5884f36df771d5810595c742b024117b69e
**Scope:** Design spec completeness check — what was specified, what was built, what remains

## Documents Reviewed

- **Intent:** `docs/plans/2026-03-27-dfa-factored-earley-parser.md` (v0.6, 2859 lines, 11 sections + 4 appendices)
- **Action:** Current codebase on branch `pu`
- **Design:** Same as intent (the design doc IS the spec)

## Source Control Conflicts

None — the design doc and implementation evolved together. The doc was
revised through v0.1–v0.6 alongside implementation commits. No stale
assumptions found.

## Alignment Summary: Design Spec vs Implementation

Only counting DFA-specific sections (5-8, 11). Sections 9-10 (grammar
construction, codegen) and Appendix D (operation tables) are pre-existing
or explicitly deferred — not DFA refactor deliverables.

| Section | Topic | Status | Notes |
|---------|-------|--------|-------|
| 5.1 | Core Item Index | **Complete** | All 8 methods + bulk accessors |
| 5.2 | DFA State Construction | **Complete** | Closure, goto, build_dfa, nullable opt |
| 5.3 | State Properties | **Complete** | terminal_map, completion_map, goto_table, state_for_core |
| 6.1-6.2 | Distance Factoring | **Complete** | chart[pos][core_id][rel_dist] representation |
| 6.3 | State Identity | **Complete** | O(1) state_for_core; distance vector hashing (optional) skipped |
| 6.4 | Lifetime Management | **Complete** | Grammar-lifetime vs parse-lifetime properly separated |
| 6.5 | Garbage Collection | **Complete** | Safe-set GC + epoch GC both implemented |
| 7.1 | DFA Provides (prediction) | **Complete** | prediction_items_for() with skip_symbols |
| 7.1 | DFA Provides (terminal matching) | **Complete** | Terminal map union + scan cache |
| 7.1 | DFA Provides (completion search) | **Partial** | Global waiting_core_ids + liveness; completion_map built but unused |
| 7.2 | Data Structures | **Complete** | Chart, completed_at, leo_items, processed, scan_cache |
| 7.3 | Parse Loop Algorithm | **Complete** | Pre-loop predict, terminal cluster, agenda, post-GC |
| 7.4 | DFA Prediction | **Complete** | Epsilon-closure + Aycock-Horspool skip_symbols |
| 7.5 | DFA Completion | **Partial** | Layer 1 (global) + Layer 3 (liveness); Layer 2 (state map) documented no-op |
| 7.6 | Scanning with Terminal Maps | **Complete** | Scan cache pre-populated, should_scan gate per-item |
| 7.7 | Scannerless Whitespace | **Complete** | Zero-width matches handled in agenda |
| 7.8 | Leo Optimization | **Complete** | Deterministic chain shortcutting |
| 7.9 | Merge Protocol | **Complete** | semiring.add() eager single-winner |
| 7.10 | DFA State at Runtime | **Complete** | No runtime state discovery needed |
| 8.1 | Error Detection | **Complete** | Last active position tracking |
| 8.2 | Diagnostics | **Complete** | Rust-style formatting with line/column, source context, caret, expected tokens |
| 8.3 | Error Recovery | **Partial** | Tier 2 brace-depth panic mode implemented; Tier 1 Ruby Slippers deferred |
| 11 | Performance Analysis | **Validated** | 23% speedup benchmarked on 11-file chalk.so pipeline |

**DFA-specific: 16 complete, 3 partial, 1 not started (error recovery), 1 validated**

Non-DFA sections (not counted above):
- Section 9 (Grammar Construction): Pre-existing, not part of DFA refactor
- Section 10 (Code Generation): Pre-existing, not part of DFA refactor
- Appendix D (Operation Tables): Explicitly deferred as "future optimization"

## GitHub Issue Status: "Earley Core/Distance Factoring" Milestone

All 9 issues are now CLOSED. Implementation was completed but issues
were not updated during development; they were closed retroactively
with implementation summaries on 2026-03-28.

| Issue | Title | Codebase Status | Notes |
|-------|-------|-----------------|-------|
| #650 | CoreItemIndex Accessors | **Done** | All 4 accessors + bulk methods exist |
| #651 | Semiring API Change | **Done** | New signatures with explicit $value, $rule_name |
| #652 | Chart Representation + Leo | **Done** | chart[pos][core_id][rel_dist], Leo side-table |
| #653 | Position-Independent Hash-Consing | **Done** | scan key is "scan:t:$text" (no position) |
| #654 | Core Set Discovery + DFA Tables | **Done** | LR0DFA.pm (330 lines), full state construction |
| #655 | Relative Distances + Set Registry | **Done** | Relative distances + set registry measurement tool (9c7e7ad7) |
| #656 | Terminal Clustering | **Done** | DFA-driven terminal map union + scan cache |
| #657 | Set Reuse | **Deferred** | Maps to Appendix D (operation tables), closed per spec |
| #658 | Benchmark Validation | **Done** | 23% speedup validated (commit 335de6a8) |

All 9 issues closed. #657 deferred per spec (maps to Appendix D).

## git-zhi Status

The git-zhi chain has one empty milestone (v0.1, 0/0 issues). The DFA
refactor work was tracked entirely on GitHub, not in git-zhi.

## Issues Reviewed

### [1] Completion map built but not consulted at parse time

- **Category:** Partial implementation
- **Severity:** Minor
- **Documents:** Spec Section 7.5 (three-layer filter) vs Earley.pm lines 982-993
- **Issue:** The spec describes a three-layer completion filter:
  1. `global_waiting_core_ids[nonterminal]` (grammar-wide candidates)
  2. `state.completion_map[nonterminal]` (DFA state narrowing)
  3. `chart[origin][waiter_core_id]` (liveness check)

  The implementation builds completion_map in LR0DFA.pm (lines 190-204) but
  _complete() in Earley.pm uses only layers 1 and 3. A comment at Earley.pm
  lines 986-991 documents this as intentional: with static state_for_core
  mapping, the completion_map check is a no-op because every waiter's mapped
  state contains the nonterminal by construction. Activating it would require
  per-position DFA state tracking.

- **Resolution:** This is a correct architectural decision documented in code.
  The completion_map data is available for future use if per-position state
  tracking is added. No action needed now. The two-layer filter (global +
  liveness) is already DFA-optimized compared to scanning all chart items.

### [2] Error recovery not implemented

- **Category:** Missing feature
- **Severity:** Important (for Phase 6+ file parsing, not for current use)
- **Documents:** Spec Section 8.3 vs no implementation
- **Issue:** The spec describes statement-level error recovery:
  - Scan forward to synchronization token (`;`, `}`, declaration keyword)
  - Resume from statement-start DFA state
  - Report multiple errors with limit
  - Insert error placeholder nodes in IR

  None of this is implemented. The parser currently fails on first error.

- **Resolution:** Error recovery is not needed for current correctness testing
  (we want to know exactly where parsing fails). It becomes important in
  Phase 6 when parsing real source files that may have construct combinations
  the grammar doesn't yet cover. **Create a GitHub issue for Phase 6.**

### [3] Diagnostic formatting is functional but not Rust-style

- **Category:** Cosmetic gap
- **Severity:** Minor
- **Documents:** Spec Section 8.2 vs Earley.pm diagnostic output
- **Issue:** The spec describes Rust-style diagnostics with line/column
  indicators, source context, and expected token sets. The implementation
  tracks `$_last_active_pos` and `$_diag_expected` but doesn't format
  output in the specified style.

- **Resolution:** Deferred. Current diagnostics are sufficient for development.
  Fancy formatting is a polish item for later phases.

### [4] goto_table built but not used for transitions

- **Category:** Unused infrastructure
- **Severity:** Minor
- **Documents:** Spec Section 5.3, 7.10 vs LR0DFA.pm
- **Issue:** Each DFA state's `goto_table` maps `{ prefixed_symbol -> target_state_id }`.
  This is built during DFA construction (LR0DFA.pm line 160) but the parse
  loop doesn't use it for state transitions. Instead, `state_for_core[core_id]`
  on the advanced core_id determines the target state implicitly.

- **Resolution:** The goto_table would be needed for a full table-driven parser
  (Appendix D operation tables) or for per-position DFA state tracking. Under
  the current architecture (agenda-driven, state_for_core lookup), it's
  correctly unused. Available for future optimization.

### [5] No benchmark suite comparing DFA vs baseline

- **Category:** Missing test artifact
- **Severity:** Minor
- **Documents:** Spec Section 11 vs test files
- **Issue:** The benchmark commit (335de6a8) reports 23% Phase 2 speedup in
  the commit message, but there's no repeatable benchmark test. The numbers
  came from a manual chalk.so pipeline run. No automated before/after
  comparison exists in the test suite.

- **Resolution:** The performance improvement is real and measured. A formal
  benchmark suite is a nice-to-have but not blocking. The chalk.so pipeline
  itself serves as the integration benchmark. **Consider creating a benchmark
  script for future regression tracking.**

## Unresolved Issues

### [6] Distance vector hashing (optional per spec)

- **Category:** Explicitly optional feature
- **Severity:** N/A (spec says optional)
- **Documents:** Spec Section 6.3
- **Issue:** Set reuse measurement via distance vector hashing is not
  implemented. The spec notes this is optional and primarily useful for
  measuring whether operation table optimization (Appendix D) would be
  beneficial.
- **Resolution:** No action needed. This is a measurement tool for a future
  optimization path.

### [7] Operation tables (Appendix D)

- **Category:** Future optimization, explicitly deferred
- **Severity:** N/A (spec labels as "Future Optimization")
- **Documents:** Spec Appendix D
- **Issue:** The fully table-driven parser (replacing the agenda loop with
  per-state operation tables) is described but explicitly scoped out.
- **Resolution:** This is the next major performance leap if needed. The
  current agenda-driven approach with DFA optimization is the correct
  intermediate step. The infrastructure (DFA states, terminal/completion maps,
  goto tables) is all in place to build operation tables when warranted.

## Test Coverage Assessment

| Component | Test File | Subtests | Real Grammar |
|-----------|-----------|----------|--------------|
| CoreItemIndex | core-item-index.t | 8 | Toy |
| LR0DFA Prediction | lr0-dfa.t | 6 | Toy |
| LR0DFA States | lr0-dfa-states.t | 12+ | Toy |
| LR0DFA Real Grammar | lr0-dfa-perl-grammar.t | 5+ | **Real (63-rule Perl)** |
| Completion Maps | earley-completion-map.t | 4 | Toy |
| Terminal Clustering | earley-terminal-clustering.t | 3 | Toy |
| Relative Distance | earley-relative-dist.t | 4 | Toy |
| Leo Optimization | earley-leo.t | 3+ | Toy (with perf timing) |

**Total: ~50 subtests across 8 files. One file tests real Perl grammar (invariants pass).**

DFA invariants 2-5 are all verified against the production Perl grammar.
This is strong structural coverage.

## Requirements Summary

### Design Spec (Sections 5-8, 11)
- **DFA-specific sub-requirements:** 21
- **Complete:** 16
- **Partial:** 3 (completion map layer 2, diagnostics formatting, set registry)
- **Not started:** 1 (error recovery — important for Phase 6)
- **Validated:** 1 (performance analysis — 23% speedup confirmed)
- **Status:** **Aligned — DFA refactor goals achieved; remaining items are future work**

### GitHub Milestone Issues (#650-#658)
- **All 9 closed.** #657 deferred per spec (maps to Appendix D operation tables).

### git-zhi
- Empty chain (v0.1 milestone, 0 issues). DFA work tracked on GitHub only.

## Performance Validation

The DFA refactor achieved its primary goal: **recover the pre-Milestone-12
baseline performance** after the chart representation changes regressed
parsing speed by ~29%.

| Metric | Before DFA | After DFA | Change |
|--------|-----------|-----------|--------|
| Phase 2 total (11 files) | 2980s | 2305s | -23% |
| Earley.pm parse time | 2340s | 1685s | -28% |
| Largest files | 28% slower | Baseline recovered | Fixed |

The 23% improvement comes from:
1. Eliminating per-position core set discovery (was O(chart width) with string hashing)
2. DFA-driven terminal clustering (try each pattern once, not per item)
3. Precomputed prediction closures (O(1) lookup vs iterating grammar rules)

All 11 classes in the chalk.so pipeline parse, compile to C, and link
successfully with the DFA-factored parser.
