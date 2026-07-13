# Agentic Code Review: method-branched-field-store (zhi 019f5368)

**Date:** 2026-07-13
**Branch:** phase5-capstone -> d25cdd6b (chalk); pu (perl5-son)
**Commits reviewed:** chalk 9067e580; perl5-son c48948b + ba6fafc (fixes: chalk 7b3af900, perl5-son e5ded6c)
**Files changed:** chalk lib/Chalk/Target/LLVM.pm (+183/-96), t/corpus/mdtest/classes.md, son-corpus-wide.t; perl5-son lib/SoN/FromOptree.pm (+68/-18)
**Diff size category:** Medium (~250 lines)
**Tier:** TIER_2 (full PAAD) — sanbao showed LLVM.pm as the #1 milestone hotspot (churn 100, score 646200), cross-repo coupling, 25 wip_violations.

## Executive Summary

A cross-repo change lowering a class method body whose body is an if/else
mutating a field in both arms (`method bump { if(C){$n=$n+5}else{$n=$n+1} }`).
The core fix routes method bodies through the same control-chain elaboration the
top-level graph uses (a correct-altitude generalization, not a special case).
Five specialist agents plus a self-verify found ONE real latent miscompile (a
double-pop dropping the value-context arm residual), now converted to a loud GAP;
and two consistency/coverage findings, both fixed. No unresolved Critical or
Important issues remain.

## Critical Issues

### [C1] Value-context field-store ternary silently returned Undef
- **File:** `perl5-son/lib/SoN/FromOptree.pm` (_handle_cond_expr $mem_branch path)
- **Bug:** `$walk_arm` already pops each arm's residual top-of-stack and returns
  it; the code then re-popped from the (now base-depth) sim, capturing undef, so
  a merged value-context ternary was always Undef/Undef. For a CONSUMED ternary
  (`my $x = $c<100 ? ($n=$n+5) : ($n=$n+1); $x`, OPf_WANT scalar) `$x` read undef
  instead of the assigned value.
- **Impact:** Silent miscompile (violates GAP-not-miscompile). Masked for the
  shipped `bump` case (OPf_WANT=0, residual discarded).
- **Resolution:** Treat OPf_WANT=0 as void (bump lowers correctly via the Undef
  merge); GAP loudly when the value is explicitly consumed (the field-read arms
  are unstamped, so the merge would collapse to Undef). Producer commit e5ded6c.
- **Found by:** Logic & Correctness (conf 80), self-verified end-to-end.

## Important Issues

### [I1] _method_body_return returned undef silently vs _method_body_root's loud die
- **File:** `chalk/lib/Chalk/Target/LLVM.pm:389`
- **Bug:** On a graph without exactly one Return, _method_body_return returned
  undef (a silent bare-deref crash downstream in Dominators->from_return_node),
  while sibling _method_body_root dies loudly. Stale comment also claimed it
  returns undef for store-free bodies (false — those have one Return).
- **Resolution:** Die loudly (belt-and-braces; _method_body_root runs first) and
  fix the comment. Commit 7b3af900.
- **Found by:** Contract & Integration (F1/F2, conf 75/65), Error Handling (note).

### [I2] Then-arm-only branch coverage
- **File:** `chalk/t/corpus/mdtest/classes.md`
- **Bug:** The only gate case took the then-arm (n=10 < 100); the else store was
  never exercised, so a miscompile dropping the else arm or selecting the wrong
  Proj would gate-green.
- **Resolution:** Added method-branched-field-store-else-arm (n=200 -> 201).
  Bilateral then/else coverage. Floor 78 -> 79. Commit 7b3af900.
- **Found by:** Test Coverage (conf 85).

## Suggestions

- Producer-layer regression teeth for the dead scope-Phi were missing (Test
  Coverage, conf 80) — addressed by t/from-optree-branched-field-store.t asserting
  no Phi merges two Add residuals.
- `_method_fn_type` is duplicated across two packages (LLVM.pm:203, :1341) — a
  pre-existing latent trap; both copies correctly patched here. Dedup is a
  follow-up, not introduced by this change (Logic, conf 60).
- Field read-defines-scope / write-skips-scope asymmetry holds only because
  FieldAccess is hash-consed and stateless; worth a one-line comment if field
  reads ever become identity-bearing (Concurrency, note).

## Verified-Safe (checked, not bugs)

- `_process_control_chain` extraction is byte-identical to the old inline block
  (Logic).
- Undef->i1 mapping consistent across all four sites; mixed Int/Undef ternary
  arms join to Scalar -> loud GAP, never miscompile (Error Handling).
- Per-method ElaboratedContext caches are id-keyed but never collide across
  method graphs (Concurrency).
- No other consumer of the removed `body_stmts` key / `_method_body_stmts`
  (Contract).

## Review Metadata

- **Agents dispatched:** Logic & Correctness, Error Handling & Edge Cases,
  Contract & Integration, Concurrency & State, Test Coverage (5 parallel) +
  a dedicated debugger agent for the rebase-exposed Region.Phi GAP.
- **Raw findings:** 4 substantive (1 Critical, 2 Important, 1 Suggestion-tier) + several verified-safe.
- **Verified findings:** all 3 actionable findings fixed and committed.
- **Steering files consulted:** CLAUDE.md (GAP-not-miscompile invariant, TDD, correctness > performance).
- **Fix commits:** perl5-son e5ded6c; chalk 7b3af900.
