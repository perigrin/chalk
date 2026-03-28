# Agentic Code Review: worktree-floofy-sparking-bunny

**Date:** 2026-03-28 03:15:52
**Branch:** worktree-floofy-sparking-bunny -> pu
**Commit:** 929d2b2dc60e288fe4f30516daa4aa491fb884a3
**Files changed:** 82 | **Lines changed:** +6291 / -12948
**Diff size category:** Large
**Review scope:** DFA-Factored-Parser milestone commits (Issues #1-2: CoreItemIndex state_for_core + LR0DFA full construction)

## Executive Summary

The DFA construction (Issues #1-2) is algorithmically sound and produces correct states matching the design doc worked example. Four important issues found: the optimized goto loop lost a terminal/nonterminal key distinction that the original `_goto` method had; Invariant 2 from the design doc is untested; the DFA state infrastructure is built but not yet consumed by Earley.pm; and error-path tests are absent. No critical bugs — all important findings are either latent (will surface during Issues #3-5 integration) or test coverage gaps.

## Critical Issues

None found.

## Important Issues

### [I1] goto_table key collision: terminal and nonterminal symbols share namespace
- **File:** `lib/Chalk/Bootstrap/LR0DFA.pm:146-165`
- **Bug:** The single-pass goto optimization groups advanced items by `$sym->value()` alone (line 154). Terminal regex patterns and nonterminal rule names are hashed under the same key in both `%kernels` and `goto_table`. If a terminal pattern string equals a nonterminal name (e.g., rule `WS` + terminal literal `WS`), items expecting different symbol types merge into one kernel, producing a corrupt target state. The dead `_goto` method (line 113) correctly checks both `$symbol_str` and `$symbol_is_ref` — the optimization dropped this.
- **Impact:** In the current Perl grammar, terminals are regex patterns and nonterminals are PascalCase names, so collision is unlikely. But the DFA is a general-purpose component and the invariant test at line 201 has the same flaw. Any grammar with `Foo ::= 'Foo' Bar` would silently break.
- **Suggested fix:** Prefix the grouping key: `my $sym_key = ($sym->is_reference() ? 'R:' : 'T:') . $sym->value();` Apply consistently to `%kernels`, `goto_table`, and the goto invariant test.
- **Confidence:** High
- **Found by:** Logic & Correctness, Error Handling, Contract & Integration, Concurrency & State (4/5 specialists)

### [I2] Invariant 2 (nonkernel = prediction closure of kernel) not tested
- **File:** `t/bootstrap/lr0-dfa-states.t` (missing test)
- **Bug:** Design doc Section 5.6 (lines 1327-1331) specifies the invariant: for each state, the nonkernel items (dot=0) should equal the epsilon-closure of kernel items minus the kernel. This invariant validates the correctness of `_closure`. It is the only invariant from Section 5.6 without test coverage — invariants 3, 4, and 5 are tested.
- **Impact:** A bug in `_closure`'s nullable advancement could go undetected.
- **Suggested fix:** Add a subtest implementing invariant 2. Handle the start-state edge case (start rule items at dot=0 are kernel, not predictions).
- **Confidence:** High
- **Found by:** Logic & Correctness, Plan Alignment

### [I3] DFA states, terminal_map, completion_map, goto_table, and state_for_core built but unused
- **File:** `lib/Chalk/Bootstrap/LR0DFA.pm:123-176` (build), `lib/Chalk/Bootstrap/Earley.pm:1091` (only consumer)
- **Bug:** Earley.pm calls only `$lr0_dfa->prediction_items_for()`. The full DFA state infrastructure (`states()`, `state()`, `completion_map`, `terminal_map`, `goto_table`, `state_for`/`states_for_bulk`) is constructed during `build()` but never queried during parsing. Earley.pm independently builds `_terminal_map_cache` and `_completion_map_cache` per parse position.
- **Impact:** Wasted construction-time work; more importantly, any bugs in DFA construction (like I1) won't manifest until Issues #3-5 wire the DFA into Earley.pm. The DFA is only tested against the 3-rule arithmetic grammar, not against real parsing workloads.
- **Suggested fix:** Add a comment in `build()` noting this is infrastructure for Issues #3-5. Consider deferring `_build_dfa_states()` until consumed, or adding an integration test that exercises DFA lookups during a real parse.
- **Confidence:** High
- **Found by:** Logic & Correctness, Contract & Integration

### [I4] No error-path or edge-case test coverage
- **File:** `t/bootstrap/lr0-dfa-states.t`, `t/bootstrap/core-item-index.t`
- **Bug:** Both test files cover only happy paths with well-formed grammars. No tests for: empty grammar, undefined nonterminal references, circular rule references (A -> B, B -> A), nullable-only grammars, or out-of-range ID access.
- **Impact:** Error handling in `_closure`, `_compute_nullable_set`, and `_build_dfa_states` is untested. The `%in_set` infinite-loop guard and nullable fixed-point convergence are correct but unverified.
- **Suggested fix:** Add subtests for at least: empty grammar (should die with clear message), circular nonterminals (should terminate), and nullable grammar with epsilon production.
- **Confidence:** High
- **Found by:** Error Handling

## Suggestions

- **[S1]** `state_for_core` many-to-one: nonkernel items appear in multiple states; last-write-wins. Document as intentional or restrict mapping to kernel items only. Currently unused by Earley.pm. *(Logic & Correctness, Error Handling, Contract & Integration, Concurrency & State, Plan Alignment — 5/5)*
- **[S2]** `_goto` method is dead code: never called, replaced by inline optimization. Either remove or keep as reference implementation with a comment. Its terminal/nonterminal distinction is the correct version of what I1 is about. *(Logic & Correctness, Error Handling, Contract & Integration, Concurrency & State — 4/5)*
- **[S3]** Empty grammar guard: `_build_dfa_states` line 128 dereferences `$grammar->[0]` without checking. Add `die "Cannot build DFA from empty grammar"` guard. *(Error Handling)*
- **[S4]** Undefined nonterminal references silently ignored: `_closure` line 72 and `_compute_prediction_closure` line 278 skip undefined nonterminals without warning. Consider `die` or `warn` for grammar authoring errors. *(Error Handling)*
- **[S5]** `grammar->[0]` start rule convention: both LR0DFA.pm:128 and Earley.pm:485 assume first rule is start rule. Add a comment documenting this convention at both sites. *(Contract & Integration)*
- **[S6]** Test helper `terminal()`/`reference()` duplicated across 14 test files with slight divergence. Extract to `t/bootstrap/lib/TestGrammarHelpers.pm`. *(Contract & Integration)*
- **[S7]** `*`-quantified symbols not explicitly treated as nullable: `_closure` and `_compute_nullable_set` only check `?`. In the current pipeline `*` is desugared before reaching LR0DFA (Desugar.pm creates epsilon alternatives), so this is latent only. Add a comment or defensive check. *(User-identified)*
- **[S8]** No double-`build()` guard: calling `build()` twice silently rebuilds, potentially invalidating external references from `states()`. Add a `$built` flag or document single-call contract. *(Concurrency & State)*
- **[S9]** Duplicated nullable advancement logic between `_closure` (lines 84-94) and `_compute_prediction_closure` (lines 297-316). Same check pattern in two places. Consider extracting nullable check to a helper method. *(Contract & Integration)*
- **[S10]** Design doc Section 5.6 line 1126 claims "Each core_id belongs to exactly one DFA state" — this is incorrect for nonkernel items. Update the design doc to acknowledge many-to-one. *(Plan Alignment)*

## Plan Alignment

| Item | Status | Notes |
|------|--------|-------|
| Section 5.1: Core Items (CoreItemIndex) | **Implemented** | Matches spec exactly, plus bonus bulk accessors |
| Section 5.2: DFA States (closure/goto/build) | **Implemented** | closure via worklist matches spec semantics; goto inlined as optimization; build matches spec |
| Section 5.3: State Properties (terminal/completion/goto maps) | **Implemented** | All three maps built per state; no separate complete_items list (consumers filter via is_complete) |
| Section 5.4: Worked Example (6 states) | **Verified** | Test confirms arithmetic grammar produces 6 states matching spec exactly |
| Section 5.6: Invariant 1 (state_for maps back) | **Weakly tested** | Tests weaker property (any valid state) not strict one-to-one |
| Section 5.6: Invariant 2 (nonkernel = closure(kernel)) | **Not tested** | See I2 |
| Section 5.6: Invariant 3 (terminal_map coverage) | **Tested** | lr0-dfa-states.t test 7 |
| Section 5.6: Invariant 4 (completion_map coverage) | **Tested** | lr0-dfa-states.t test 8 |
| Section 5.6: Invariant 5 (goto consistency) | **Tested** | lr0-dfa-states.t test 9 |
| Integration with Earley.pm (Issues #3-5) | **Not yet implemented** | DFA infrastructure built but not consumed |

## Review Metadata

- **Agents dispatched:** 5 specialists + 1 verifier
  - Logic & Correctness
  - Error Handling & Edge Cases
  - Contract & Integration
  - Concurrency & State
  - Plan Alignment
- **Scope:** 5 changed files (DFA-Factored-Parser commits) + adjacent callers (Earley.pm, Symbol.pm, Rule.pm)
- **Raw findings:** 31 (across all specialists)
- **Verified findings:** 14 (4 Important, 10 Suggestions)
- **Filtered out:** 17 (duplicates, below confidence threshold, or not actionable)
- **Steering files consulted:** CLAUDE.md (project + global)
- **Plan/design docs consulted:** `docs/plans/2026-03-27-dfa-factored-earley-parser.md` (Sections 5.1-5.6)
