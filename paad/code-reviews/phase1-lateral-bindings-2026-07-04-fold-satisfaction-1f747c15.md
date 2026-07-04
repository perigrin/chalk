# Agentic Code Review: fold-satisfaction (zhi 019f2a50)

**Date:** 2026-07-04
**Branch:** phase1-lateral-bindings (commit 1f747c15, review fixes follow)
**Scope:** t/lib/Chalk/CodeGen/Harness/MdtestCorpus.pm (fold-satisfaction), t/bootstrap/corpus/shape-subset-check.t, the corpus format doc.

## Executive Summary

Fold-satisfaction lets the corpus keep the unfolded `Add(1,2)` op shape while
matching a perl-folded `Constant(3)` producer graph. The mechanism is sound
(the false-green specialist confirmed +7 gate-green with zero spurious
passes, and the honest-GAP guard holds). Review found TWO real correctness
holes, both empirically reproduced and both fixed with teeth-verified tests:
a repr-blind fold that warned + coincidentally false-matched string literals,
and an id-set operand subsumption that over-satisfied a hash-consed literal
shared with a non-fold consumer.

## Important Issues (fixed)

### [I1] Repr-blind fold: string literal warns + coincidental false PASS
- **File:** MdtestCorpus.pm `_fold_satisfied_ids` / `_literal_operand`
- **Bug:** `_literal_operand` returned any Constant's value regardless of repr; `Add(Constant("foo"):Str, Constant(2):Int)` ran `"foo" + 2` → warning to STDERR (violates the pristine-output standard) AND folded to `2`, coincidentally matching a real `Constant(2)` → false PASS. Empirically reproduced.
- **Found by:** Edge-cases (80/68), Logic (62) — 3 agents.
- **Fix:** `_literal_operand` returns `($value, $repr, $node)`; the fold gates on `%_NUMERIC_REPR{Int,Num}` for both operands. No warning, no false match. Test 17 (teeth-verified).

### [I2] Id-set operand subsumption over-satisfies a shared hash-consed literal
- **File:** MdtestCorpus.pm `_fold_satisfied_ids`
- **Bug:** operand Constants were marked satisfied by id. `_collect_node_signatures` dedups by id, so a `Constant(2)` shared between a fold op and a live `Coerce` produced ONE signature; skipping its id dropped it for the Coerce too → the Coerce's requirement vanished → false PASS even when the real graph lacked `Constant(2)`. Empirically reproduced (PASS with `missing=[]` where FAIL was correct).
- **Found by:** Logic (85).
- **Fix:** consumer-count fixpoint — a node is subsumed only when EVERY reachable spec consumer of it is a subsumed fold op; a literal shared with a non-fold consumer keeps its signature. Test 16 (teeth-verified: `not ok` under the old blanket-mark, `ok` restored).

## Suggestions

- **Shape-axis weakening is by-design** (false-green specialist): a correct `1+2` folding to `Constant(3)` is byte-identical to a buggy producer that emitted `3` without adding — shape alone no longer independently verifies these ops for the perl/B::SoN producer. Compensated by the behavior leg (lli==perl runs the real arithmetic) in the triple gate. Documented in the fold comment; no code change. (Applied: noted.)
- **Float stringification fragility** (false-green: ~35): the value key is string-eq; `3/4=0.75` matches perl-default stringification on both sides, but a non-terminating fold (`1/3`) relies on identical 15-sig-fig stringification. Consistent today, no corpus case exercises it. (Ponytail-noted in the doc.)
- **Simplification: skip-set threading** (quality): the satisfied-set is still passed to `_collect_node_signatures`; kept as an id-set (op nodes + fully-subsumed inputs are genuine node identities), which is correct and clearer than a per-occurrence multiset. Not changed.
- **Coerce-unwrap duplication** (reuse/false-green): resolved incidentally — `_literal_operand` now returns the node, and the fixpoint handles Coerce subsumption structurally rather than re-walking.

## Plan Alignment

- **Implemented:** fold-satisfaction for arithmetic + Num comparisons over literals; rule recorded in the format doc; corpus gate-green 9→16, zero non-arithmetic/comparison topics changed.
- **Not yet implemented (filed):** recursive/ternary folding (019f2b61); Str comparisons (no corpus case).

## Review Metadata

- **Agents:** 2 quality (reuse, simplification) + 3 bug-hunting (logic, edge-cases, contract/false-green). Security/concurrency omitted (single-process test harness, no trust boundary).
- **Raw findings:** ~9. **Verified + fixed:** 2 Important (each empirically reproduced before fixing). Remainder documentation/no-change.
- **Both fixes went through TDD:** RED test reproducing the bug → fix → GREEN → teeth-check (test goes red without the fix).
