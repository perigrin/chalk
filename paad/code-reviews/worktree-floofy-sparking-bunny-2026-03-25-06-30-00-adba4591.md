# Agentic Code Review: worktree-floofy-sparking-bunny

**Date:** 2026-03-25 06:30:00
**Branch:** worktree-floofy-sparking-bunny -> pu
**Commit:** adba4591680063883d974e4f36bc0ef0c76c568d
**Files changed:** 30 | **Lines changed:** +2355 / -1142
**Diff size category:** Large

## Executive Summary

The Earley parser core/distance factoring refactor (Milestone 12, Components 3-8) is well-executed. The chart representation change, semiring API migration, and optimization infrastructure (core sets, terminal clustering, prediction caching) are consistent and thoroughly tested. One critical ordering issue exists where `completed_at` indexes zero-valued completions, causing wasted work and a minor index-chart inconsistency. Five important cleanup items (dead code, stale comments, unused fields) should be addressed before merge.

## Critical Issues

### [C1] `completed_at` records zero-valued completions before the zero check
- **File:** `lib/Chalk/Bootstrap/Earley.pm:628-637`
- **Bug:** Lines 630-631 unconditionally record completed items in `%completed_at`, including items whose `on_complete` returned zero/undef. The zero check at line 637 only prevents propagation via `_complete`, not the `completed_at` indexing. Additionally, the chart stores the zero/undef value (line 628) making `_chart_has` return false while `completed_at` has an entry pointing to it — an index-chart inconsistency.
- **Impact:** `_advance_from_completed` iterates stale entries, calling `_chart_get` and `multiply` before discovering the value is zero. For FilterComposite with high rejection rates, this creates measurable overhead. The inconsistency between `_chart_has` (returns false for undef) and `completed_at` (has entry) is a latent source of confusion.
- **Suggested fix:** Move the zero check above the `completed_at` recording, or guard the push with the same zero check.
- **Confidence:** High
- **Found by:** Error Handling

## Important Issues

### [I1] Dead `_cluster_scan` method and stale comment
- **File:** `lib/Chalk/Bootstrap/Earley.pm:282-295, :1075`
- **Bug:** `_cluster_scan` is defined but never called. Terminal clustering is done inline at lines 530-545. Comment at line 1075 references the dead method.
- **Impact:** Maintenance confusion — a developer might modify the dead method thinking it's active.
- **Suggested fix:** Remove the dead method and update the comment at line 1075.
- **Confidence:** High
- **Found by:** Logic, Contract, Plan (3 specialists agreed)

### [I2] Stale comment describes hash-based chart
- **File:** `lib/Chalk/Bootstrap/Earley.pm:462`
- **Bug:** Comment says `$chart[$pos][$core_id]{$origin}` (hash) but actual implementation uses `$chart[$pos][$core_id][$rel_dist]` (array, rel_dist = pos - origin).
- **Impact:** Misleads developers about the chart data structure.
- **Suggested fix:** Update to `# Chart: $chart[$pos][$core_id][$rel_dist] = $value  (rel_dist = pos - origin)`
- **Confidence:** High
- **Found by:** Logic, Error Handling, Contract, Concurrency, Plan (all 5 agreed)

### [I3] `%_profile_data` not reset between parses
- **File:** `lib/Chalk/Bootstrap/Earley.pm` — `reset_parse_state()` and `_run_parse()` inline reset
- **Bug:** `%_profile_data` is not cleared in either reset path. Profile data accumulates across multiple parses on the same parser instance.
- **Impact:** Misleading profiling data when `EARLEY_PROFILE` is set and multiple parses are done.
- **Suggested fix:** Add `%_profile_data = ();` to `reset_parse_state()` and the inline reset in `_run_parse`.
- **Confidence:** High
- **Found by:** Concurrency & State

### [I4] `$_leo_origin_min` is dead code
- **File:** `lib/Chalk/Bootstrap/Earley.pm:51, 150, 478, 1298-1299`
- **Bug:** Written but never read. Tracked incrementally for a planned but unimplemented Leo-aware GC optimization.
- **Impact:** Wasted writes on every Leo item creation.
- **Suggested fix:** Remove or add a comment documenting future intent.
- **Confidence:** High
- **Found by:** Concurrency & State

### [I5] DFA `completion_map` built but never consumed
- **File:** `lib/Chalk/Bootstrap/Earley.pm:244-276`
- **Bug:** `_build_dfa_tables` builds `completion_map` per core set, but no production code reads it.
- **Impact:** Wasted memory and construction time per core set.
- **Suggested fix:** Remove or document as reserved for future use.
- **Confidence:** High
- **Found by:** Plan Alignment

## Suggestions

- [S1] O(n^2) nonterminal dedup in prediction cache (line 585-586): replace `grep` with `%seen` hash. Low priority — n is small. (Contract, Plan)
- [S2] Prediction cache creates throwaway Symbol objects (lines 570-573) on every reuse hit. Consider caching Symbol objects or refactoring `_predict` to accept strings. (Plan)
- [S3] Misleading comment on `_clear_grammar_caches()` (line 162): says "grammar changes" but grammar is immutable after construction. (Concurrency)
- [S4] Prediction cache field comment (line 85) says "core_set_id" but actual keys are comma-joined hash strings. (Plan)

## Plan Alignment

- **Implemented:** Components 3-8 (chart representation, hash-consing, core sets, relative distances, terminal clustering, prediction caching). All matching plan intent.
- **Not yet implemented:** Goto table (plan section 7), scan decision caching, same-set completion caching (plan section 8). Partial implementation is expected and delivers the highest-value optimizations first.
- **Deviations:** DFA tables live in Earley.pm rather than LR0DFA.pm as the plan suggested. Leo item fields use `top_core_id`/`top_origin` naming (improvement over plan's `core_id`/`origin`). Terminal clustering uses direct `$ci_symbols_after` iteration rather than DFA terminal_map.

## Review Metadata

- **Agents dispatched:** Logic & Correctness, Error Handling & Edge Cases, Contract & Integration, Concurrency & State, Plan Alignment (5 specialists + 1 verifier)
- **Scope:** 9 lib/ files + 21 test files (changed + adjacent callers)
- **Raw findings:** 16 (before verification)
- **Verified findings:** 10 (after verification)
- **Filtered out:** 6 (false positives or below threshold)
- **Steering files consulted:** CLAUDE.md (project and global)
- **Plan/design docs consulted:** docs/plans/2026-03-24-earley-core-distance-factoring.md
