# Full SoN IR Polymorphic Migration Review

**Branch:** worktree-pu
**Base:** 2d2259e3
**Commits reviewed:** 50 commits (da34443b..cedfe00a)
**Date:** 2026-04-06
**Reviewer:** Senior Code Review Agent

## Summary

This review covers Phases 1 through 4b of the SoN IR polymorphic migration:
scaffolding typed node classes, factory shim, consumer migration with dead
Constructor fallback removal, SSA scope with Phi creation, and structural
split of metadata types (Program, ClassInfo, MethodInfo, SubInfo, FieldInfo,
UseInfo). The migration is well-designed and largely well-executed. The
architecture follows Click's Sea of Nodes separation of metadata from
computation faithfully. The incremental strategy -- shim then migrate
consumers then split structure -- was the right call.

That said, there are **2 critical bugs**, **4 important issues**, and
**several suggestions** identified below.

---

## What Was Done Well

1. **Inheritance bridge.** `Chalk::IR::Node :isa(Chalk::Bootstrap::IR::Node)`
   ensures typed nodes pass the ~283 `isa Chalk::Bootstrap::IR::Node` checks
   across the codebase. This is the right migration strategy.

2. **Shim design.** `Chalk::IR::Shim::translate()` returning undef for
   untranslated classes provides a graceful fallback. The enable/disable
   per-class mechanism in DEFAULT_ENABLED is well thought out.

3. **Hash consing.** The new `Chalk::IR::NodeFactory` properly deduplicates
   data nodes by content_hash and gives unique IDs to CFG nodes.

4. **Consumer registration.** Both the old and new factories register
   consumers on inputs, maintaining use-def chains. The new factory's
   `_register_consumers` handles nested arrayrefs.

5. **Metadata structs.** Program, ClassInfo, MethodInfo, SubInfo, FieldInfo,
   UseInfo are clean data containers with `id()` and no-op `add_consumer()`.
   The `id()` methods are content-based and deterministic.

6. **SSA scope.** The hybrid Phi strategy (eager for if/else, lazy sentinel
   for loops) is correct in design. Trivial Phi removal is inline and correct.

7. **Test coverage for new types.** 25 new test files covering typed nodes,
   shim translation, metadata structs, Phi creation, scope merging, and
   pipeline integration. The IR-level tests are thorough.

---

## Critical Findings

### C1. _rewrap_stmt creates Unwind with bare node instead of args arrayref

**File:** `lib/Chalk/Bootstrap/Perl/Actions.pm:568-576`
**What:** `_rewrap_stmt()` for Unwind creates `inputs => [$ctrl, $new_inner]`
where `$new_inner` is a single IR node. But codegen (`_emit_die_call` in both
`Target/Perl.pm:525` and `EmitHelpers.pm:2363`) reads `$node->inputs()->[1]`
and treats it as an **arrayref** by iterating `$args->@*`.
**Why it matters:** If `_rewrap_stmt` is invoked on an Unwind node during
`_unwrap_stmt_from_expr`, the rewrapped Unwind node will have a bare IR node
at `inputs->[1]` instead of an arrayref. When codegen calls `$args->@*` on
this bare node, Target/Perl.pm will crash (no arrayref check). EmitHelpers.pm
has a `ref($args) eq 'ARRAY'` guard (line 2365) so it degrades to an empty
die message, which is wrong but not a crash.
**Suggested fix:** In `_rewrap_stmt`, wrap $new_inner in an arrayref for Unwind:
```perl
return $factory->make_cfg('Unwind', inputs => [$ctrl, [$new_inner]]);
```
**Confidence:** 90

### C2. Target/Perl.pm missing fallback for Constructor:BinaryExpr/UnaryExpr

**File:** `lib/Chalk/Bootstrap/Perl/Target/Perl.pm:614,633-639`
**What:** The `_emit_expr` method was refactored: typed path `isa BinOp` at
line 614 handles translated BinaryExpr nodes; Constructor fallback at line 633
handles TernaryExpr, StructRef, FieldAccess, then falls through to
`_emit_node`. But `_emit_node`'s Constructor handler (line 340-349) only
handles structural types and dies on unknown classes.

Operators NOT in BINOP_MAP (`//`, `..`, `x`, `isa`, `!~`, `\`) produce
Constructor:BinaryExpr or Constructor:UnaryExpr nodes that miss the typed
path AND miss the Constructor fallback, reaching `die "Unknown Constructor
class: BinaryExpr"`.

Compare with `EmitHelpers.pm:2430-2431` which correctly retains fallback
handlers for `class eq 'BinaryExpr'` and `class eq 'UnaryExpr'`.
**Why it matters:** Any file using `//` (defined-or), `..` (range), `x`
(string repeat), or backslash reference (`\@arr`) will crash during Perl
codegen via Target/Perl.pm. These operators are widespread in the codebase.
**Suggested fix:** Add fallback handlers in `_emit_expr` and `_emit_node`
for `class eq 'BinaryExpr'` and `class eq 'UnaryExpr'`:
```perl
# In _emit_expr, after isa checks and before the Constructor block:
if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
    my $class = $node->class();
    if ($class eq 'BinaryExpr')  { return $self->_emit_binary_expr($node); }
    if ($class eq 'UnaryExpr')   { return $self->_emit_unary_expr($node); }
    ...
}
```
**Confidence:** 95

---

## Important Findings

### I1. Test failures in perl-actions-tier-c.t (crash on Chalk::IR::Program)

**File:** `t/bootstrap/perl-actions-tier-c.t:48-74`
**What:** The test's `is_constructor()` helper calls `$node->operation()` on
the parse result, which is now `Chalk::IR::Program` (no `operation()` method).
The `find_class_decl()` helper calls `$ir->inputs()->[0]` (Program has no
`inputs()` method). The test crashes at line 51 with:
`Can't locate object method "operation" via package "Chalk::IR::Program"`.
**Why it matters:** 1 test file completely broken, preventing regression
coverage of Tier C files (ConciseOp.pm, etc.).
**Suggested fix:** Update `is_constructor` to check for `Chalk::IR::Program`
with `isa`. Update `find_class_decl` to use `$ir->classes()` for Program.
**Confidence:** 100

### I2. Test failures in perl-actions-fixup.t (6 of 68 tests fail)

**File:** `t/bootstrap/perl-actions-fixup.t:496,506`
**What:** The test checks `$stmt isa Chalk::Bootstrap::IR::Node::Constructor`
for BuiltinCall and PostfixDerefExpr nodes, but these are now typed as
`Chalk::IR::Node::Call` and `Chalk::IR::Node::PostfixDeref`. The isa check
fails and the test reports failure.
**Why it matters:** 6 failing tests mask real regressions. These are false
negatives -- the functionality works but the test expectations are stale.
**Suggested fix:** Add typed-node checks alongside the Constructor checks:
```perl
if ($stmt isa Chalk::IR::Node::Call && $stmt->dispatch_kind() eq 'builtin') {
    ...
} elsif ($stmt isa Chalk::Bootstrap::IR::Node::Constructor) {
    ...
}
```
**Confidence:** 100

### I3. Test failures in cfg-statements.t (2 of 177 tests fail)

**File:** `t/bootstrap/cfg-statements.t:567,1329`
**What:** Test 100 checks `$if_cond isa Constructor && class eq 'UnaryExpr'`
but the node is now `Chalk::IR::Node::Not` (a typed node from the shim
translating the `unless` negation). Test 168 checks
`$cond isa Constructor && class eq 'BinaryExpr'` but the node is now
`Chalk::IR::Node::Or`.
**Why it matters:** 2 failing tests. The functionality is correct -- the tests
need to check `isa Chalk::IR::Node::UnaryOp` and `isa Chalk::IR::Node::BinOp`.
**Suggested fix:** Update the isa checks to accept both old and new types.
**Confidence:** 100

### I4. XS int-specialization tests fail (4 of 6) -- Target/C.pm regression

**File:** `t/bootstrap/xs-int-specialization.t`
**What:** Generated C code emits `NULL /* unsupported */` for method bodies,
indicating that `EmitHelpers._emit_expr` returns the unsupported fallback for
nodes that should be recognized. The methods have `SV *self, SV *self`
(duplicated self parameter) suggesting a metadata extraction issue.
**Why it matters:** XS codegen for method bodies containing arithmetic is
broken. The duplicated `self` parameter in the C signature suggests the
MethodInfo->params() includes `$self` when it shouldn't (or the C emitter
adds it unconditionally AND the metadata includes it).
**Suggested fix:** Investigate whether MethodInfo.params includes `$self`
when it should only include explicit parameters. Check Target/C.pm method
signature emission.
**Confidence:** 75

---

## Suggestions

### S1. Missing operators in BINOP_MAP and UNOP_MAP

**File:** `lib/Chalk/IR/Shim.pm:26-48`
**What:** The following Perl operators are missing from the shim's translation
maps and will always fall through to Constructor:
- BINOP_MAP: `//` (defined-or), `..` (range), `x` (string repeat), `isa`
- UNOP_MAP: `\` (reference constructor)

These are all valid Perl operators that appear in the grammar's BinaryOp rule.
**Why it matters:** These operators stay as Constructor:BinaryExpr, creating
a mixed-type situation where some binary expressions are typed and some are
not. With C2 fixed (fallback handlers), this works but is inconsistent.
**Suggested fix:** Either add these operators to BINOP_MAP (create new node
types like `DefinedOr`, `Range`, `StrRepeat`) or document them as
intentionally excluded with a comment in the shim.
**Confidence:** 70

### S2. BinOp ADJUST fallback assigns wrong input

**File:** `lib/Chalk/IR/Node/BinOp.pm:13-14`
**What:** When `left` is not passed as a named parameter, the ADJUST block
sets `$left //= $self->inputs()->[0]`. But for BinaryExpr shim translation,
inputs are `[$op_constant, $left, $right]`, so `inputs()->[0]` is the op
Constant, not the left operand. Similarly `inputs()->[1]` would be the actual
left, not right.
**Why it matters:** If anyone creates a BinOp with only `inputs` and not
explicit `left`/`right` named params, the accessors will return wrong values.
Currently the shim always passes explicit left/right, so this doesn't fire.
But it's a latent correctness issue for future callers.
**Suggested fix:** Either document that `left`/`right` must always be passed,
or adjust the fallback indices:
```perl
ADJUST {
    # Shim layout: inputs = [op, left, right]
    $left  //= $self->inputs()->[1];
    $right //= $self->inputs()->[2];
}
```
**Confidence:** 80

### S3. UnaryOp ADJUST fallback assigns wrong input

**File:** `lib/Chalk/IR/Node/UnaryOp.pm:13-14`
**What:** Same issue as BinOp. ADJUST does `$operand = $self->inputs()->[0]`
but inputs are `[$op_constant, $operand]`, so `inputs()->[0]` is the op, not
the operand.
**Suggested fix:** `$operand //= $self->inputs()->[1]`
**Confidence:** 80

### S4. AnonSub counter is non-deterministic across processes

**File:** `lib/Chalk/IR/Node/AnonSub.pm:11-18`
**What:** `$anon_counter` is a package-level `my` variable incremented on each
AnonSub creation. The content_hash includes `anon_id=$anon_id`. If the order
of AnonSub creation varies between runs (e.g., due to hash iteration order in
the parser), content hashes will differ.
**Why it matters:** The design doc requires deterministic codegen
("byte-identical output across runs"). The counter itself is deterministic
within a single parse (creation order is parse order), but NodeFactory
`reset_for_testing` does NOT reset this counter.
**Suggested fix:** Either make the counter field-level (per factory instance,
reset with factory) or add a reset mechanism called from
`reset_for_testing()`.
**Confidence:** 65

### S5. Phi content_hash includes region but not values type

**File:** `lib/Chalk/IR/Node/Phi.pm:14-16`
**What:** content_hash iterates `$self->inputs()->@*` which includes ALL
inputs. But the new Phi (created via new factory) never receives `inputs` --
the `region` and `values` are separate `:param` fields. So
`$self->inputs()->@*` is always `[]` for new Phi nodes, and the content_hash
degrades to `"Phi|region=REGION_ID|"`.
**Why it matters:** Two Phi nodes with different values but the same region
would hash identically, causing incorrect deduplication. However, Phis are
currently always created via the OLD factory (which sets inputs correctly), so
this doesn't fire yet.
**Suggested fix:** This is a latent bug for Phase 5 when the old factory is
removed. Either make the new Phi accept `inputs` that includes region+values,
or override content_hash to use the `$region` field and a `values` field
directly.
**Confidence:** 70

### S6. struct-promotion end-to-end test has SKIP label error

**File:** `t/bootstrap/struct-promotion/end-to-end.t`
**What:** Test exits with error: `Label not found for "last SKIP"`. This is a
Test::More/Test2 interaction issue where the SKIP block's label is lost.
**Why it matters:** 14 of ~14 tests pass before the crash, but the test file
doesn't complete cleanly.
**Suggested fix:** Convert the bare `skip` to a proper `SKIP: { skip ... }`
block with explicit label.
**Confidence:** 85

### S7. Repeated metadata isa check chains in Actions.pm

**File:** `lib/Chalk/Bootstrap/Perl/Actions.pm:891-896,944-950,963-968`
**What:** The pattern `$val isa UseInfo || $val isa ClassInfo || $val isa
FieldInfo || $val isa MethodInfo || $val isa SubInfo` is repeated in
Program(), StatementList(), and StatementItem(). Each addition of a new
metadata type requires updating all three sites.
**Why it matters:** Maintenance risk. A missed update would silently drop
metadata items.
**Suggested fix:** Extract to a helper:
```perl
my sub _is_metadata($val) {
    return $val isa Chalk::IR::UseInfo
        || $val isa Chalk::IR::ClassInfo
        || ...;
}
```
**Confidence:** 60

---

## Completeness Assessment

### Constructor Types Still Existing

The following Constructor types are NOT yet translated by the shim and remain
as `Chalk::Bootstrap::IR::Node::Constructor`:

| Constructor Class | Status | Notes |
|---|---|---|
| TernaryExpr | Intentionally deferred | Lowered to If+Proj+Region+Phi in future |
| StructRef | Optimizer-specific | Created by StructPromotion |
| FieldAccess | Optimizer-specific | Created by StructPromotion |
| FieldDecl | Legacy fallback | Active code creates FieldInfo; fallback in AssignmentExpression |
| Symbol | BNF pipeline | Excluded from migration |
| Expression | BNF pipeline | Excluded from migration |
| Rule | BNF pipeline | Excluded from migration |

These are documented in the design doc and their exclusion is justified.

### Structural Types Successfully Migrated

| Old Constructor | New Type | Producer | Consumers Updated |
|---|---|---|---|
| Program | Chalk::IR::Program | Actions.pm:Program() | Target/Perl.pm, EmitHelpers.pm, StructPromotion.pm, DepChaser.pm |
| ClassDecl | Chalk::IR::ClassInfo | Actions.pm:ClassBlock() | Target/Perl.pm, EmitHelpers.pm, StructPromotion.pm |
| MethodDecl | Chalk::IR::MethodInfo | Actions.pm:MethodDefinition() | Target/Perl.pm, EmitHelpers.pm, StructPromotion.pm |
| SubDecl | Chalk::IR::SubInfo | Actions.pm:SubroutineDefinition() | Target/Perl.pm, EmitHelpers.pm, StructPromotion.pm |
| FieldDecl | Chalk::IR::FieldInfo | Actions.pm:FieldDeclaration() | Target/Perl.pm, EmitHelpers.pm |
| UseDecl | Chalk::IR::UseInfo | Actions.pm:UseDeclaration() | Target/Perl.pm, DepChaser.pm |
| _Attribute | plain hashref | Actions.pm | Target/Perl.pm, EmitHelpers.pm |
| ReturnStmt | Chalk::IR::Node::Return | Actions.pm:ReturnStatement() | Target/Perl.pm, EmitHelpers.pm |
| DieCall | Chalk::IR::Node::Unwind | Actions.pm:BuiltinCall/fixup | Target/Perl.pm, EmitHelpers.pm |

### Inheritance Bridge Status

`Chalk::IR::Node :isa(Chalk::Bootstrap::IR::Node)` -- documented in
`lib/Chalk/IR/Node.pm:8-9`. To be removed in Phase 5 when all `isa
Chalk::Bootstrap::IR::Node` checks are migrated.

---

## Test Coverage Gaps

1. **No test for operators outside BINOP_MAP.** No test parses `$a // $b` or
   `$a .. $b` and verifies correct Constructor:BinaryExpr codegen through the
   full pipeline.

2. **No test for _rewrap_stmt on Unwind.** The stale-value merge fixup
   rewrapping an Unwind node through `_unwrap_stmt_from_expr` is untested.

3. **No integration test for Phi codegen.** The scope tests verify Phi nodes
   are created correctly, but no test verifies that Target/Perl.pm emits
   correct Perl when a Phi node appears in the IR (e.g., `my $x; if (...) {
   $x = 1 } else { $x = 2 }`).

4. **Tier C tests completely broken.** `perl-actions-tier-c.t` crashes at
   line 5, providing zero coverage for ConciseOp.pm, TypeInference.pm, etc.

---

## Test Results Summary

| Test File | Result |
|---|---|
| t/bootstrap/ir-*.t (25 files) | All PASS |
| t/bootstrap/scope-*.t (8 files) | All PASS |
| t/bootstrap/perl-actions-tier-a.t | 70/70 PASS |
| t/bootstrap/perl-actions-tier-b.t | 104/104 PASS |
| t/bootstrap/perl-actions-tier-c.t | CRASH at test 5 |
| t/bootstrap/perl-actions-fixup.t | 62/68 PASS (6 FAIL) |
| t/bootstrap/cfg-statements.t | 175/177 PASS (2 FAIL) |
| t/bootstrap/perl-ir-tier-a.t | 44/44 PASS |
| t/bootstrap/perl-target-sub-decl.t | 15/15 PASS |
| t/bootstrap/assignment-scope.t | 26/26 PASS |
| t/bootstrap/xs-int-specialization.t | 2/6 PASS (4 FAIL) |
| t/bootstrap/xs-*.t (other 3) | All PASS |
| t/bootstrap/struct-promotion/ir-rewriter.t | 4/4 PASS |
| t/bootstrap/struct-promotion/pipeline-integration.t | 9/9 PASS |
| t/bootstrap/struct-promotion/end-to-end.t | 14 PASS then SKIP label crash |

---

## Verdict

The migration architecture is sound and the execution is mostly correct.
Before proceeding to Phase 5 (Constructor deletion), the following must be
addressed:

**Must fix (Critical):**
- C1: _rewrap_stmt Unwind args arrayref
- C2: Target/Perl.pm missing BinaryExpr/UnaryExpr fallback

**Should fix (Important):**
- I1: perl-actions-tier-c.t crash
- I2: perl-actions-fixup.t test expectation updates
- I3: cfg-statements.t test expectation updates
- I4: XS int-specialization regression investigation

**Can defer (Suggestions):**
- S1 through S7 can be addressed during Phase 5 cleanup
