# Phase 1 Scope Decision: M20 (do-block) and M21 (eval block)

**Issue**: 019e9af9-8a3a  
**Date**: 2026-06-06  
**Status**: M21 = REJECT (decided). M20 = pending perigrin's call (recommendation: IN-SUBSET-DEFERRED).

---

## Context

Two tier-1 corpus idioms required explicit subset classification rather than
mechanical codegen work:

- **M20**: `class C { method m() { my $r = do { my $x = 1; $x + 2 }; return $r; } }`  
  — `do { }` block as an expression (returns the last evaluated expression).
- **M21**: `class C { method m() { my $r = eval { die "boom" }; return defined $r; } }`  
  — `eval { }` block for exception trapping.

Both were previously classified `NOT-YET-COVERED` because no hand graph existed.
The pushback review identified these as scope questions, not mechanical codegen gaps.

---

## M21: eval block — REJECT (decided, policy-cited)

### Evidence

1. **Grammar**: `docs/chalk-bootstrap.bnf` (336 lines) has **zero occurrences** of the
   word `eval`. The grammar has no `eval` rule, no eval keyword, and no eval-related
   production anywhere.

2. **Keyword table**: `lib/Chalk/Grammar/Perl/KeywordTable.pm` lists 36 keyword-to-rule
   mappings. `eval` does not appear anywhere in that file.

3. **IR node inventory**: `ls lib/Chalk/IR/Node/` shows 75 node types. There is no
   `Eval.pm` or anything eval-related.

4. **Project policy (CLAUDE.md)**: The try/catch policy states verbatim:
   > Chalk's exception-handling mechanism is try/catch; eval is excluded in all forms

5. **Grammar has try/catch**: Line 52 of the BNF has `TryCatchStatement` as a
   `StatementItem` alternative. Line 114 defines:
   ```
   TryCatchStatement ::= /try\b/ _ Block _ /catch\b/ _ /\(/ _ ScalarVariable _ /\)/ _ Block ;
   ```
   `Chalk::IR::Node::TryCatch` exists, has a full emitter in `EmitHelpers.pm`, and
   is fully integrated via `Actions.pm`.

### Conclusion

**M21 = REJECT (out-of-subset by policy)**.

The grammar does not admit `eval`. The project has an explicit policy excluding eval in
all forms. The sanctioned exception-handling mechanism (try/catch) is fully wired. There
is nothing to implement here, and classifying M21 as a codegen gap would be incorrect.

M21 remains in the 78-entry denominator (classified, not dropped) with verdict REJECT and
reason: *"out-of-subset by policy: eval is excluded in all forms; Chalk uses try/catch for
exception handling (see CLAUDE.md)"*.

---

## M20: do-block — RECOMMENDATION: IN-SUBSET-DEFERRED

### Evidence

**1. Grammar: does the BNF admit `do { ... }`?**

The BNF (`docs/chalk-bootstrap.bnf`) has **zero occurrences** of the word `do`
(the only grep hit is the `# SPEC: docs/chalk-grammar-spec.md` comment on line 6).

The `Atom` rule (§13) lists: `Variable | Literal | ParenExpr | ArrayConstructor |
HashConstructor | QwLiteral | AnonymousSub | /__SUB__\b/ | QualifiedIdentifier`.
There is no `DoBlock` or `DoExpr` alternative.

**The current grammar does NOT admit `do { }` as an expression.**

M20's snippet (`my $r = do { my $x = 1; $x + 2 }; return $r;`) would parse `do`
as a bareword (QualifiedIdentifier) followed by a HashConstructor `{ my $x = 1; ... }`,
which would fail on the statement content inside. In practice the parser would reject M20.

**2. Self-hosting workload: is `do { }` used in lib/?**

`ag "do {" lib/` finds exactly 3 occurrences:

- `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm:125`: `$_ctx_cache{$key} //= do { ... }`
- `lib/Chalk/Bootstrap/Semiring/FilterComposite.pm:101`: `$_one_cache //= do { ... }`
- `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm:2001`: a string literal containing `' and do { ... }'`

The first two are in `my sub` bodies (non-class methods) and use the `//= do { }` idiom
for lazy initialization. The third is a string, not a real do-block.

**Conclusion on self-hosting pressure**: Chalk's own source uses `do { }` in exactly
two places, both in `my sub` scope (not `method` scope), and both as `//= do { }`.
The M20 corpus entry uses `my $r = do { }` in a class `method`. This is a different
but closely related idiom. The self-hosting workload does create pressure for `do { }`
support — it will be needed when Chalk parses SemanticAction.pm and FilterComposite.pm.

**3. What would IN-SUBSET cost?**

- **Grammar**: Add `DoBlock` to the `Atom` rule:  
  `DoBlock ::= /do\b/ _ Block ;`  
  and add `DoBlock` as an `Atom` alternative. The keyword `do` would need a
  `KeywordTable` entry pointing to a new rule.
- **IR**: Add `Chalk::IR::Node::Do` — a new node type wrapping a block's exit value.
  The node carries the block's IR graph and returns the block's final value.
- **Emitter**: Add `Do` emission in `EmitHelpers.pm` and `Perl.pm`.
- **Actions**: Add `DoBlock` semantic action in `Actions.pm`.

This is 4–5 files, ~50–100 lines of code. It is bounded and well-precedented
(AnonymousSub and Block already handle the similar case of block-valued expressions).

**4. Alternative: is `do { }` replaceable in the self-hosting workload?**

The two lib/ occurrences use `//= do { }` for lazy initialization. Each could be
rewritten as a helper method or as an explicit `if (!defined) { ... }` initialization
block. This is a realistic refactor — the self-hosting workload could avoid `do { }`
at the cost of verbosity.

### Options for perigrin

| Option | Classification | Effect |
|--------|---------------|--------|
| **A) IN-SUBSET-DEFERRED** | `NOT-YET-COVERED` with reason "needs Do IR node; grammar extension required" | Stays in the codegen backlog as a future issue. Not a Phase-1 blocker. |
| **B) IN-SUBSET-PHASE-1** | Becomes a codegen issue (grammar + IR + emitter + actions) | ~50-100 LOC across 4-5 files. Bounded work. |
| **C) REJECT (out of subset)** | `REJECT` | Out-of-subset by decision. Self-hosting files must avoid `do { }`. Requires refactoring SemanticAction.pm and FilterComposite.pm. |

### Recommendation

**Option A: IN-SUBSET-DEFERRED.**

Rationale: `do { }` is a valid Perl expression, is used in Chalk's own source (twice),
and is not excluded by any policy. It will be needed for self-hosting. However, it
requires a new IR node and grammar extension, making it out of scope for a scope-decision
issue. The right classification is `NOT-YET-COVERED` with an explicit reason noting
the grammar extension requirement. It should be tracked as a future codegen issue.

M20 is left as `NOT-YET-COVERED` with reason "no hand graph defined" until perigrin
makes the final call and a Do IR node is implemented.

**FINAL CALL: perigrin.**

Choose from A (deferred), B (Phase-1 codegen), or C (REJECT). If C, the two
SemanticAction.pm / FilterComposite.pm do-blocks must be refactored before self-hosting
those files.

---

## Gap-Map Mechanism Changes

### REJECT verdict added

`lib/Chalk/CodeGen/Harness/GapMap.pm` now has:

- `%REJECT_IDIOMS` hash: maps tag → reason string. M21 is the first entry.
- `_run_one()`: checks `%REJECT_IDIOMS` before the hand-graph path. REJECT idioms
  return immediately without reaching the codegen rig.
- `valid_verdicts()`: returns all valid verdict strings including `REJECT`.
- `tier1_green(\%gap_map)`: returns true iff every in-subset (non-REJECT) entry is PASS.

### Tier-1 green definition

**Green** = `tier1_green($gap_map)` returns true.  
This holds iff: for every entry with verdict ≠ REJECT, verdict == PASS.  
REJECT entries are excluded from the green requirement.  
GAP, MISCOMPILE, NOT-YET-COVERED, UNDER_SPECIFIED on any in-subset idiom blocks green.

### Denominator

The denominator remains 78. M21's classification changed from NOT-YET-COVERED to REJECT;
it did not leave the denominator.

### Current tally (after M21 REJECT)

| Verdict | Count |
|---------|-------|
| PASS | 57 |
| NOT-YET-COVERED | 20 |
| REJECT | 1 |
| **Total** | **78** |

tier1_green = NO (20 in-subset idioms remain NOT-YET-COVERED).

---

## Tests Added

`t/bootstrap/codegen-harness/gap-map-reject.t` — 13 tests:

- R1: REJECT is a valid verdict string
- R2: M21 is classified REJECT in the generated gap map
- R3: denominator remains 78 after REJECT classification
- R4: REJECT idiom does NOT count as GAP/failure; NOT-YET-COVERED decreased
- R5: tier1_green() returns true when all in-subset idioms PASS + one REJECT present
- R6: tier1_green() returns false when an in-subset idiom is NOT-YET-COVERED
- R7: tier1_green() returns false when an in-subset idiom is GAP
- R8: tier1_green() returns false when an in-subset idiom is MISCOMPILE
- R9: REJECT entries carry a non-empty reason
- R10: validate_coverage still passes with REJECT entries present

All 13 tests pass. All pre-existing gap-map tests (29 + 13) continue to pass.
