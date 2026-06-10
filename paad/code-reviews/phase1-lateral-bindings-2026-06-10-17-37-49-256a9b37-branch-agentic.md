# Agentic Code Review: phase1-lateral-bindings (WHOLE BRANCH vs pu)

**Date:** 2026-06-10 17:37:49
**Branch:** phase1-lateral-bindings -> pu (merge-base f4149ea4)
**Commit:** 256a9b37ba894c09f83d27b345812db8be74926e
**Files changed:** 81 | **Lines changed:** +8513 / -1446 | **Commits:** 46
**Diff size category:** Large
**Scope:** the integrated R1 (namespace) + R2/R3 (node convergence) + G6 (regex) + G7 (host) state. Each piece had a per-issue review with fixes; this review hunts the SEAMS between them and the accumulated state.

## Executive Summary

For its stated scope — corpus-driven, hand-authored graphs — the branch is in
shippable shape: every corpus case is GREEN (R1-R6, H1-H3, classes, references,
logical, strings), and the four Critical miscompiles found in the value-cache /
hash-cons family are **pre-existing pu architecture defects the branch
inherited**, not regressions (verifier re-ran the probes against the pu
checkout). They bite only on graph shapes the corpus deliberately avoids
(re-read-after-mutate, repeated identical statements, multi-block values in phi
arms) — and they are the already-flagged "lateral-propagation axis"
(phi_merge_strategy memory: "fix first" before B::SoN). Three findings are
genuinely branch-attributable and should be fixed before merge; the rest ride
as follow-ups — **which must actually be filed** (the verifier confirmed four
of the reconciliation plan's "filed" deferrals were never filed).

## Critical Issues

### [C1] Value cache is stale for pure nodes over mutable-location reads — silent miscompile (PRE-EXISTING)
- **File:** `lib/Chalk/Target/LLVM.pm` lower_value cache (~1199; pu has the identical carve-out)
- **Bug:** only `PadAccess` bypasses the cache; `Add(PadAccess($x), 10)` is cached and reused after `$x` is reassigned. Probe: `my $x=1; $y=$x+10; $x=2; $z=$x+10; $y+$z` → lli `Int:22`, perl `Int:23`, exit 0.
- **Status:** PRE-EXISTING on pu (probe reproduces byte-for-byte). Conf 98.
- **Fix direction:** exclude nodes whose transitive inputs include a mutable-location read (PadAccess/Subscript/FieldAccess); memoize the pad-dependence bit.
- **Found by:** Concurrency&State (F1).

### [C2] Subscript/FieldAccess read-after-store returns the pre-store value (PRE-EXISTING class)
- **Bug:** identical reads hash-cons + cache; an intervening element/field store doesn't invalidate. Probe: `my @a=(1,2); $p=$a[0]; $a[0]=9; $a[0]` → `Int:1` vs perl `Int:9`. Reproduces on pu via ArrayRead/ArrayWrite. Conf 95.
- **Found by:** Concurrency&State (F2).

### [C3] Repeated identical scalar-rebind statements collapse to one node (PRE-EXISTING)
- **Bug:** scalar-rebind `Assign` stays content-hash-consed; `$x=$x+1; $x=$x+1;` is ONE node — one increment executes (`Int:2` vs perl `Int:3`). The branch's I2 fix carved out only Subscript/FieldAccess lvalues. Conf 95.
- **Related:** Graph.pm merge/unmerge/nodes() still key by content_hash — wrong-node substitution + orphan leak for per-call nodes (LOGICB-F2, Important-latent, pre-existing mechanism widened by the branch).
- **Found by:** Concurrency&State (F3), Logic-B (F1 family).

### [C4] Str-length tracking dies at phi merges; G7 capture views then print the subject tail — silent miscompile (**BRANCH-INTRODUCED**)
- **File:** `lib/Chalk/Target/LLVM.pm` phi emission (~5237) + the strlen/`//0` fallbacks (epilogue Path B, Coerce(Str->Num/Bool), method-ret, field-store)
- **Bug:** a Str-repr value crossing an if/else phi loses its `_str_len_table` entry; every fallback assumes NUL-termination — true for all pu-era Strs, FALSE for G7's zero-copy RegexCapture views. Probe: `if (1>0) { $x = $1 } else { $x = "ww" }` with `$1="ab"` from `"xxabyy"` → prints `Str:abyy`, exit 0.
- **Impact:** the one branch-introduced SILENT miscompile. Conf 90.
- **Suggested fix:** emit a parallel i64 length phi for every Str-repr phi (RegexSubst already does exactly this for its own merge), and/or make the NUL-assuming fallbacks die GAP now that non-NUL-terminated Strs exist.
- **Found by:** Logic-A (2).

## Important Issues

### [I1] Call(non-new) per-call identity REGRESSION (**BRANCH-INTRODUCED**)
- **Bug:** pu's `MethodCall` node had per-call identity ("New, MethodCall, and FieldWrite have per-call identity"); the R3 convergence onto `Call` narrowed the carve-out to `name='new'` only. Two identical statement-position method calls (`$obj->advance(); $obj->advance();`) now collapse to one node. CompoundAssign/RegexSubst/TryCatch (the Block fixup's own side-effect list) have the same gap (pre-existing for CompoundAssign; RegexSubst/TryCatch are branch/new). Conf 85.
- **Fix:** per-call identity for every op the Block fixup treats as a statement-position side effect; derive both lists from one table.
- **Found by:** Logic-B (F1), verifier-classified.

### [I2] Self-host golden enshrines a pragma INVERSION: `no warnings` emitted as `use warnings` (branch SURFACED)
- **File:** `t/fixtures/codegen-goldens/Chalk__Bootstrap__Target.pl.golden:4` vs `lib/Chalk/Bootstrap/Target.pm:6`
- **Bug:** `Chalk::MOP::Import` has no `keyword` field; `_emit_mop_import` hardcodes `"use $module"`. R1 added the first `no` pragma to a golden-covered source; the regenerated golden asserts the WRONG output (re-enables the experimental warning). Undermines the Phase-7 byte-compat gate. Conf 95.
- **Fix:** thread `keyword` through MOP::Import → emitter; regenerate the golden.
- **Found by:** Contract&Integration (F1).

### [I3] JSON serializer cannot round-trip the branch's new nodes (**BRANCH-INTRODUCED**, latent)
- **Bug:** `Serialize/JSON.pm` lacks RegexCapture(`n`)/EnvRead(`key`) branches (round-trip DIES) and silently drops Call's new `param_names` (wrong lowering later). No producer ships these through JSON today. Conf 95.
- **Found by:** Contract&Integration (F2).

### [I4] ClassInfo registry: `type // 'Int'` silent default + no node-vs-registry ABI cross-check (silent-garbage channel)
- **Bug:** an untyped Str field lowers as Int (probe: exit 0, garbage `Str:%…`); `_lower_call_method` casts the fn ptr per the NODE's repr while the define used the REGISTRY's — lli accepts the mismatch (the silent channel). Pattern carried forward from pu (`field_repr // 'Int'`), R3 site. Conf 90/80.
- **Fix:** loud GAP on missing field type; one-line repr cross-check in `_lower_call_method`.
- **Found by:** ErrorHandling (F1, F2).

### [I5] Phi-arm / loop-init wiring cannot host multi-block values — invalid IR (PRE-EXISTING)
- **Bug:** four wiring sites lower values after the host block's terminator is set; any multi-block value op (Subscript scan loops, regex matchers...) in a phi arm/loop init → "expected instruction opcode". Reproduces on pu with ArrayRead. Loud, not silent. Conf 95.
- **Found by:** Logic-A (1).

### [I6] ADJUST bodies lowered on the MAIN ctx — second `new` of a class emits nothing (PRE-EXISTING mechanism; dead from the parse path)
- **Bug:** `local` flags can't localize the value cache; probe with two `Pt->new` → `Int:6` vs perl `Int:107`. Reachable only from hand-built graphs today (Actions.pm never passes `adjusts`). Conf 90.
- **Fix direction:** ADJUST as a synthesized per-class fn lowered in a fresh Context (like method bodies).
- **Found by:** Concurrency&State (F4).

## Suggestions
- Five Slot-payload store sites fall through to `store i64` for Str/Num (loud reject; should GAP-die) — incl. the Call(new) default-field site where the computed `$def_repr` is unused (ERRH-F3 + LOGICA-3, pre-existing).
- Assign(Array-lvalue) with container repr `Array` GEPs an i8* (loud; branch). (STATE-F5)
- Graph.pm per-call-node keying (merge/nodes orphan filter) — pre-existing, widened. (LOGICB-F2)
- ClassInfo/MethodInfo `id()` omit the branch-added fields (adjusts/parent_ci/body_node/return_repr) — `%visited` dedup could drop adjusts. (LOGICB-F3)
- Dead `New`/`FieldDef` branches in MdtestCorpus.pm; unquoted `const_type` builds a garbage Constant silently; MethodInfo/ClassInfo recognizers drop positional inputs silently. (CONTRACT-F4, LOGICB-F4/F5)
- Symbol-prefix logic triplicated (str_const/rxs_lit/env_key) and already micro-diverged (bytes-vs-char length); StrPair store duplicated (call_new + field-store). (CONTRACT-F5/F6)
- CONTRACT-F3 (stale ArrayRead/HashRead labels) REJECTED as duplicate of filed 019eaf54.

## Plan Alignment
- **Implemented:** Phase G (F3/F4/F6/F7/F8) + node convergence + narrow namespace move + sea-of-nodes-ir.md/typed-ir-representation.md docs — essentially in full, with green evidence. F9 dissolved (with the documented self-pointer nuance). G6/G7 delivered per the boundary doc with census-grounded scope.
- **Not yet implemented / deferred-with-label:** TypedInvariant per-phase coverage (019eaf54); regex/host feature tails (019eb073/019eb0d7).
- **Deviations / bookkeeping debt (the real tail):**
  - `mop.md` (criterion 6.2) and `ir-lowering.md` (6.5) NOT updated — ir-lowering.md still says LLVM is "deferred pending C/XS" while the branch ships a 5,304-line backend. Unmet, unlabeled.
  - FOUR "filed" deferrals were never filed: the full Bootstrap-target migration, the F8 §2-purity Coerce route, the I3 parser→LLVM equivalence gate, the F10 Context split issue-ref.
  - The reconciliation plan's own Status header still says "node-convergence phases 0-6 REMAINING WORK (not started)".
  - runtime-free-boundary.md still describes G6 as "deferred" and items 1-7 as future — needs a dated status pass.
  - zhi hygiene: the umbrella GAP-campaign issue can close (G1-G7 done, successors tracked); G5b's dep edge points at the retired G5 id (graph warning).
  - CLAUDE.md "Plan Discipline" item 3 is substantially stale (pre-existing): the 92-site compat_class surface no longer exists; Shim.pm is gone; body_stmts seeding is gone; the ~30-40% figure needs re-audit.

## Review Metadata
- **Agents dispatched:** Logic-A (LLVM emitter seams), Logic-B (IR layer + harness), Error Handling & Edge Cases, Contract & Integration, Concurrency & State, Plan Alignment, + Verifier (probe re-runs incl. against the pu checkout for branch-vs-pre-existing classification). Security lens folded into prior per-issue reviews (injection findings already recorded/deferred).
- **Raw findings:** 24 | **Verified:** 21 | **Rejected/dup:** 3 (incl. CONTRACT-F3 as a 019eaf54 duplicate)
- **Probes:** /tmp/probe_*.pl (runnable miscompile reproductions, several re-run on pu)
- **Steering files:** CLAUDE.md (project+global; staleness finding above), MEMORY.md
- **Plans consulted:** 2026-06-08-ir-taxonomy-reconciliation.md, runtime-free-boundary.md, sea-of-nodes-ir.md, typed-ir-representation.md
