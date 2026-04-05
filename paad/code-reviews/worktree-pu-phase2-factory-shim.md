# Phase 2 Factory Shim Review

**Reviewer:** Code Review Agent (Opus 4.6)
**Date:** 2026-04-04
**Branch:** worktree-pu (commits e10c6377..ed8871da, 6 commits)
**Base commit:** f330c26b
**Plan:** docs/superpowers/plans/2026-04-04-son-ir-phase2-factory-shim.md
**Design doc:** docs/plans/2026-04-04-son-ir-polymorphic-migration.md

---

## Executive Summary

The Phase 2 implementation correctly scaffolds the shim translation layer,
named fields on BinOp/UnaryOp, the compat_class mechanism, and
content_hash safety. The core architecture is sound. However, the shim is
**actively breaking existing tests** because translated nodes fail the
ubiquitous `$node isa Chalk::Bootstrap::IR::Node::Constructor` checks
throughout Actions.pm and the codegen targets. The plan anticipated this
(Task 6, Step 2) and prescribed selectively disabling translation for
problematic classes, but this was not done.

**Test impact:** 6 new failures in assignment-scope.t, 5 new failures
across c-data-model-classes.t and c-self-call-optimization.t. The IR-only
tests (16 files, 473 tests) all pass.

---

## What Was Done Well

1. **Named field pattern is clean.** BinOp and UnaryOp use `:param :reader`
   with ADJUST fallback to inputs[]. This handles both old (positional)
   and new (named) construction without ambiguity.

2. **content_hash safety.** All 8 overriding content_hash methods were
   updated to handle undef and arrayref inputs. The base class
   `Chalk::IR::Node::content_hash()` also handles these cases. This was
   thorough and correctly done.

3. **Translation mapping is comprehensive.** The shim handles 16 Constructor
   classes and explicitly lists 10 NOT_TRANSLATED classes. Every Constructor
   class used in Actions.pm is accounted for.

4. **compat_class mechanism is well-designed.** Adding a single field to
   Node base with a fallback to operation() is simpler and more correct
   than per-class monkey-patching.

5. **PostfixDerefExpr dual-path handling.** The shim correctly handles both
   node-type and string-type sigil params, which is a real-world concern.

6. **Commit structure.** Six focused commits in correct dependency order,
   following TDD progression.

---

## Findings

### CRITICAL: Translated nodes break isa Constructor checks (6+ new failures)

**File:** lib/Chalk/IR/Shim.pm (all translation handlers)
**Impact:** lib/Chalk/Bootstrap/Perl/Actions.pm (~35 call sites),
  lib/Chalk/Bootstrap/Perl/Target/Perl.pm (~15 sites),
  lib/Chalk/Bootstrap/Perl/Target/C.pm (~34 sites),
  lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm (~18 sites)
**Confidence:** 100

The codebase has approximately 100 `$node isa Chalk::Bootstrap::IR::Node::Constructor`
checks. Translated nodes (e.g., `Chalk::IR::Node::Add`) do NOT inherit from
`Constructor`, so every check fails. This causes silent behavior changes
wherever the check is used as a guard before accessing `->class()`.

Demonstrated regression in assignment-scope.t:
- Line 2409 of Actions.pm: `$target isa Constructor && $target->class() eq 'VarDecl'`
  fails because VarDecl is now `Chalk::IR::Node::VarDecl`. The
  AssignmentExpression handler falls through to the BinaryExpr path instead
  of merging VarDecl with its initializer.
- Same pattern at line 2399 for FieldDecl (FieldDecl is NOT_TRANSLATED, so
  this particular one is safe).
- Line 178 of assignment-scope.t: CompoundAssign is translated, so
  `isa Constructor` fails.

The Phase 2 plan (Task 6, Step 2) prescribed: "If too many failures,
selectively disable translation for problematic Constructor classes in the
shim (return undef for them) and file issues for Phase 4." This was not
done.

**Suggested fix:** Add ALL translated classes to NOT_TRANSLATED for now,
effectively making the shim a no-op during Phase 2. Then incrementally
enable translation class-by-class, starting with classes whose isa checks
are least entangled (e.g., BacktickExpr, TryCatch). Alternatively, add
these classes to NOT_TRANSLATED and keep only the ones that have no
isa-Constructor guard sites (verify by grepping).

**Verification:** Run all bootstrap tests after the fix. The acceptance
criterion is: "Existing test suite passes unchanged."

---

### IMPORTANT: Missing binary operators in BINOP_MAP

**File:** lib/Chalk/IR/Shim.pm:8-23
**Confidence:** 85

The grammar (docs/chalk-bootstrap.bnf lines 192-213) defines these BinaryOp
terminals that are NOT in BINOP_MAP:

| Operator | Description | Node type needed |
|---|---|---|
| `//` | Defined-or | DefinedOr (missing from Phase 1) |
| `xor` | Logical xor | Xor (missing from Phase 1) |
| `..` | Range | Range (missing from Phase 1) |
| `...` | Yada/Range | Range or Yada (missing from Phase 1) |
| `isa` | Type check | IsA (missing from Phase 1) |
| `x` | String repeat | Repeat (missing from Phase 1) |
| `!~` | Negated match | NegMatch (missing from Phase 1) |

These fall through gracefully to old-style Constructor (the shim returns
undef for unknown ops, and the old factory handles them). This is correct
behavior for Phase 2. However, the absence of these types from Phase 1
means they cannot be translated until the types are created.

**Suggested fix:** File an issue to add these node types in a Phase 1
supplement, then add them to BINOP_MAP. The `//` operator is extremely
common in Perl code and will need a type.

---

### IMPORTANT: Missing unary operators in UNOP_MAP

**File:** lib/Chalk/IR/Shim.pm:25-31
**Confidence:** 80

The grammar (docs/chalk-bootstrap.bnf lines 180-185) defines these UnaryOp
terminals that are NOT in UNOP_MAP:

| Operator | Description | Node type needed |
|---|---|---|
| `+` | Unary plus (no-op/numeric coerce) | UnaryPlus (missing) |
| `\` | Reference constructor | Ref (missing) |

These also fall through gracefully to Constructor.

**Suggested fix:** File an issue to add these types.

---

### IMPORTANT: Double-caching between old and new factories

**File:** lib/Chalk/Bootstrap/IR/NodeFactory.pm:114-122
**File:** lib/Chalk/IR/NodeFactory.pm:104-119
**Confidence:** 70

When a translated node is created, it exists in both:
1. `Chalk::IR::NodeFactory`'s `%cache` (by content_hash)
2. `Chalk::Bootstrap::IR::NodeFactory`'s `$node_cache` (by content_hash)

This is functionally correct but wastes memory (each translated node is
stored twice). More importantly, the new factory creates a **temporary
node** on every call to compute the content_hash, even for cache hits.
For a second call with the same params:

1. Shim calls `$_new_factory->make('Add', ...)`
2. New factory creates temp node (`id => '_tmp'`), computes hash, finds
   cached node, returns it
3. Old factory gets the cached node back, computes content_hash again,
   finds it in its own cache, returns it

The temp node creation on every call is unnecessary overhead.

**Suggested fix:** This is acceptable for Phase 2. In Phase 5 (cleanup),
the old factory goes away and this duplication disappears. If performance
is a concern before then, the old factory could check its own cache first
(before calling the shim) using a predictable key format.

---

### IMPORTANT: content_hash does not include compat_class

**File:** lib/Chalk/IR/Node.pm:32-46
**Confidence:** 75

The base `content_hash()` does not include `compat_class` in the hash.
This means:
- `Add(id='_tmp', inputs=[$op, $l, $r], compat_class='BinaryExpr')`
- `Add(id='_tmp', inputs=[$op, $l, $r], compat_class=undef)`

produce the same content_hash and would collide in the cache. During
Phase 2 this is not a problem because all Add nodes are created through
the shim (which always sets compat_class). In Phase 3a, when direct
creation starts (without compat_class), a directly-created Add would
get the cached shim-created Add (with compat_class='BinaryExpr'). The
directly-created node would then respond to `->class()` with
'BinaryExpr' instead of 'Add'.

**Suggested fix:** Either include compat_class in content_hash, or ensure
Phase 3a always passes compat_class (even for direct creation). This
should be addressed before Phase 3a begins.

---

### SUGGESTION: SubCall constructor class not handled

**File:** lib/Chalk/IR/Shim.pm
**Confidence:** 60

The design doc lists Call with `dispatch_kind => 'sub'` for subroutine
calls. The shim handles MethodCallExpr (method) and BuiltinCall (builtin)
but there is no SubCall or FunctionCall constructor class in Actions.pm.
If one is added in the future, the shim would silently fall through to
Constructor. This is not a bug today but worth noting.

---

### SUGGESTION: Test coverage gaps

**File:** t/bootstrap/ir-shim.t
**Confidence:** 65

The shim test does not cover:
1. Unknown BinaryExpr ops that fall through (e.g., `//`, `..`) -- only
   `???` is tested, which is good for the general case but does not
   verify that real-world missing ops work
2. RegexSubst translation
3. ArrayRefExpr translation
4. AnonSubExpr translation
5. CompoundAssign translation
6. TryCatchStmt translation
7. InterpolatedString with array-of-nodes parts input

The integration test (ir-factory-shim-integration.t) covers only
BinaryExpr, UnaryExpr, MethodCallExpr, BuiltinCall, VarDecl, and
Program. The remaining translated classes (SubscriptExpr, PostfixDerefExpr,
CompoundAssign, HashRefExpr, ArrayRefExpr, AnonSubExpr, RegexMatch,
RegexSubst, InterpolatedString, BacktickExpr, TryCatchStmt) are not
tested through the old factory integration path.

---

## Plan Alignment

The implementation follows the Phase 2 plan closely with one significant
deviation:

| Plan Task | Status | Notes |
|---|---|---|
| Task 1: BinOp named fields | Complete | Matches plan |
| Task 2: UnaryOp named field | Complete | Matches plan |
| Task 3: Chalk::IR::Shim | Complete | Covers more classes than plan specified |
| Task 4: compat_class field | Complete | Matches plan |
| Task 5: Wire shim into NodeFactory | Complete | Matches plan |
| Task 6: Verify existing tests | **Incomplete** | Tests fail; plan says to disable failing translations |

**Key deviation:** Task 6 Step 2 says "If too many failures, selectively
disable translation for problematic Constructor classes in the shim (return
undef for them)." This step was not performed. The shim is actively
translating classes that break ~100 isa-Constructor check sites.

---

## Pre-existing Failures

For reference, these failures exist on the base commit (f330c26b) and are
NOT caused by Phase 2:

- assignment-scope.t: 4 failures (tests 11, 14, 15, 26) -- plain
  assignment produces BinaryExpr instead of expected VarDecl
- c-build-pipeline.t: 1 failure
- c-target-boolean.t: 3 failures
- c-target-multi-class.t: 2 failures
- c-type-aware-dispatch.t: 1 failure

---

## Recommendations

1. **Immediately:** Add all translated classes to NOT_TRANSLATED (making
   the shim a no-op), then re-enable them one at a time after verifying
   each has no isa-Constructor breakage. The Phase 2 acceptance criterion
   ("existing test suite passes unchanged") is not met.

2. **Before Phase 3a:** Resolve the content_hash/compat_class collision
   issue so direct creation and shim creation of the same computation
   produce nodes with consistent class() behavior.

3. **File issue:** Track the missing BinOp/UnaryOp types (DefinedOr, Xor,
   Range, IsA, Repeat, NegMatch, UnaryPlus, Ref) as a Phase 1 supplement.

4. **Expand test coverage:** Add integration tests for the remaining 11
   translated classes through the old factory path.
