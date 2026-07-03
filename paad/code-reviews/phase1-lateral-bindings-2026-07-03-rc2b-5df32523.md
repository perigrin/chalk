# Agentic Code Review: RC2b (cross-repo: phase1-lateral-bindings + perl5-son phase4b-single-exit)

**Date:** 2026-07-03
**Branch:** phase1-lateral-bindings -> pu (Chalk) / phase4b-single-exit (perl5-son)
**Commits:** Chalk db166680, 5df32523; perl5-son fa7e8ef, 60c6ade, d20f1e1, b1530fb, a9630f8
**Files changed:** 12 | **Lines changed:** +842 / -53
**Diff size category:** Large

## Executive Summary

The five RC2b acceptance cases are correct, but the new loop/modifier machinery
is only sound ON the corpus path. Five specialists found 20 verified defects
(0 rejected by the adversarial verifier — every finding was confirmed in code,
most by end-to-end execution). The dominant class is SILENT MISCOMPILES on
ordinary Perl one step off the corpus: loop-control ops, side-effecting
conditions, nested structures, and a decoy-comparison condition-selection
ambiguity. Each violates the producer's own "refuse loudly" discipline. The
fix pass converts every silent-wrong path to a loud GAP (or fixes it outright)
before RC2b closes.

## Critical Issues (5 distinct roots, 9 findings)

### [C1] last/next/redo silently dropped inside loop bodies
- **File:** `perl5-son lib/SoN/FromOptree.pm:1302` (guard omits loopex ops)
- **Bug:** loop-control ops fall to the unhandled-skip; loop translated as if absent.
- **Repro:** `for my $i (1..5) { $s = $s + $i; last } $s` -> oracle Int:1, emitted Int:15.
- **Fix:** extend the loop-body die-guard to last/next/redo.
- **Found by:** errors + contract (independent).

### [C2] cond_expr / nested enterloop/enteriter inside loop bodies silently skipped
- **File:** `perl5-son lib/SoN/FromOptree.pm:1280,1331`
- **Bug:** branch/loop ops inside a body are only handled by the MAIN walker;
  _walk_loop_body skips them (and a nested loop's `and` mints a SECOND Proj
  pair on the OUTER Loop, truncating the body walk).
- **Repro:** if/else in a while body -> oracle Int:103, emitted Int:0.
  Nested while (increment before inner loop) -> oracle Int:6, emitted Int:3.
- **Fix:** die GAP for is_branch ops + enterloop/enteriter in _walk_loop_body;
  die if a second condition tries to mint Projs.
- **Found by:** logic + contract.

### [C3] Side-effecting loop conditions miscompile (three interacting defects)
- **File:** `perl5-son lib/SoN/FromOptree.pm:238,1153,1171`
- **Bug:** (a) postfix-while's first condition walk leaks pad rebinds into the
  Phi inits; (b) the failing (N+1th) condition evaluation's side effects are
  modeled as back-edge-only; (c) post-loop reads see the header Phi, missing
  the final mutation.
- **Repro:** `while ($i-- > 0) { } $i` -> oracle Int:-1, emitted Int:0.
  `$t = $t + $n while $n-- > 0` -> oracle Int:3, emitted Int:1.
- **Fix (this pass):** scout the condition segment; die GAP when the condition
  mutates any pad slot. Full lowering filed as follow-up.
- **Found by:** logic + errors + state (five findings, one root).

### [C4] Loop condition never structurally wired; backend fallback picks a decoy
- **File:** `perl5-son lib/SoN/FromOptree.pm:1308` / Chalk `LLVM.pm:3259`
- **Bug:** producer discards the condition node unconsumed; backend Strategy 1
  (control-linked cmp) can never match, Strategy 2 picks the first icmp
  consumer of any Phi sorted by content-hash id -- arbitrary.
- **Repro:** body containing `my $c = $n > -1` -> oracle Int:4, emitted Int:5.
- **Fix (this pass):** die GAP when more than one icmp consumes header Phis.
  Real fix (control edge through the seam) filed as follow-up.
- **Found by:** contract.

### [C5] Postfix-while Phi-init contamination (subsumed by C3's guard)
- **File:** `perl5-son lib/SoN/FromOptree.pm:242`
- Covered by the C3 condition-mutation guard: any mutating condition dies GAP
  before translation, which includes every reproduced contamination case.

## Important Issues (6 distinct)

1. **TernaryExpr bare-scalar condition unlowerable** -- `$x = 7 if $c` (Int $c)
   fails lli (`i64 vs i1`); pre-existing `_lower_ternary` truthiness gap that
   commit 60c6ade's headline feature now trips. **Fix this pass (Chalk
   backend):** coerce Int condition via `icmp ne i64 ..., 0` mirroring
   `_lower_and`; also repairs plain `$c ? 7 : 5`.
2. **perl5-son's own from_json cannot round-trip loop graphs** -- single-pass
   input resolution under a now-false topo invariant dies on the forward
   backedge. **Fix this pass:** mirror the Chalk defer-patch via set_backedge.
3. **Stale stamp contamination** -- un-stamping a Phi (unstamped backedge)
   leaves body nodes stamped from the optimistic init; contaminates other
   Phis' joins. **Fix this pass:** die GAP (consistent with the widening die).
4. **foreach bound IV_MAX+1 overflow** -- `9223372036854775806..IV_MAX` ->
   oracle Int:2, emitted Int:0. **Fix this pass:** die GAP at IV_MAX.
5. **Orphan dead nodes serialized** (postfix-while's discarded walks pollute
   the contract surface via consumer-edge BFS). **Filed** as follow-up.
6. **Chalk to_json silently drops the CFG skeleton of a LOADED loop graph**
   (control_in and unconsumed conditions unreachable from _all_nodes_topo).
   Latent -- no live round-trip consumer. **Filed** as follow-up.

## Suggestions

- Loader defer-patch accepts out-of-range / self-referential / negative
  backedge indexes silently (folded into the already-filed loader-hardening
  issue, 019f26a5 #5 -- extended to cover the Phi slot).
- Non-lexical foreach iterators (`for (1..3)`, package vars) refused only by
  accident with a misleading bounds message. **Fix this pass:** targ guard
  with a truthful GAP message.

## Review Metadata

- **Agents dispatched:** 5 specialists (logic, errors, contract, state,
  security) + 20 per-finding adversarial verifiers, all in fresh contexts.
- **Raw findings:** 20 | **Verified:** 20 | **Filtered:** 0
- **Verification:** every finding re-derived from code; 14 confirmed by
  end-to-end execution through the repro harness.
- **Steering files:** CLAUDE.md (both repos). **Plan docs:**
  docs/plans/2026-07-01-phase4-corpus-wide-status.md.
- **Known-issue exclusions honored:** the five 019f26a5 filings were not
  re-reported; two adjacent-but-distinct findings were verified as
  non-duplicates before inclusion.
