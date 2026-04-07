# Final Review: SoN IR Polymorphic Migration

**Branch:** worktree-pu  
**Base commit:** 2d2259e3  
**Head commit:** 762fa514 (+ uncommitted fixes)  
**Date:** 2026-04-07  
**Scope:** 72 commits, 171 files changed, +10557/-3524 lines

---

## Executive Summary

The migration successfully achieves its primary architectural goals: Constructor.pm
is deleted, all computation types route through the shim to typed nodes, and a
reverse inheritance bridge connects the Bootstrap and Chalk IR hierarchies. The
core pipeline and struct-promotion optimizer work correctly. However, there are
uncommitted fixes for a critical scope bug, and several test files were not updated
to reflect the metadata struct migration (Program, ClassDecl, MethodDecl, etc.).

**Verdict:** The architecture is sound. The remaining issues are fixable, but
they block a clean test run. The uncommitted changes must be committed, and the
remaining test files must be updated before this branch is merge-ready.

---

## Verification Checklist

### 1. Constructor.pm is deleted -- PASS

No file exists at `lib/Chalk/Bootstrap/IR/Node/Constructor.pm`. Confirmed via
filesystem check.

### 2. Zero `isa Constructor` in lib/ -- PASS

`grep -r 'isa.*Constructor' lib/` returns zero matches. All production code has
been migrated away from the old Constructor type. The word "Constructor" appears
only in comments, string literals (the `make('Constructor', ...)` factory calls
which are intercepted by the shim), and grammar rule names (ArrayConstructor,
HashConstructor) which are unrelated.

### 3. Shim correctness -- PASS

`lib/Chalk/IR/Shim.pm` correctly translates all 18 computation Constructor
classes to typed nodes. The die-on-undef behavior in `NodeFactory.pm:97` ensures
no unknown Constructor class silently falls through:

```perl
die "Unknown or untranslated Constructor class: '$class'" unless defined $typed;
```

The `%DEFAULT_ENABLED` set matches the full list of computation types including
TernaryExpr, StructRef, and FieldAccess.

### 4. Fixup method guards -- CONDITIONAL PASS (requires uncommitted fix)

The guards in `_fix_postfix_chain`, `_fix_postfix_chain_deep`, and
`_unwrap_stmt_from_expr` were correctly changed from `isa Constructor` to
`isa Chalk::IR::Node`. The specific typed-node checks (`isa Chalk::IR::Node::Call`,
`isa Chalk::IR::Node::BinOp`, `isa Chalk::IR::Node::UnaryOp`,
`isa Chalk::IR::Node::PostfixDeref`) are correct and use the intermediate
base classes from the new hierarchy.

**Critical issue:** See Finding C1 below -- `_is_stmt_node` scope bug must be
committed.

### 5. Reverse bridge -- PASS

`lib/Chalk/Bootstrap/IR/Node.pm` correctly inherits from `Chalk::IR::Node`:

```
Chalk::Bootstrap::IR::Node :isa(Chalk::IR::Node)
```

This ensures all Bootstrap node subclasses (Constant, Start, Return, If, Proj,
Region, Phi, Loop) pass `isa Chalk::IR::Node` checks throughout the pipeline.
The new typed nodes (under `Chalk::IR::Node::*`) inherit directly from
`Chalk::IR::Node`, so both old and new nodes satisfy the same guard.

### 6. BNF pipeline -- PASS

`t/bootstrap/bnf-grammar.t` passes all 82 tests. `Grammar::Symbol` and
`Grammar::Rule` are used directly (not wrapped in Constructor nodes).
`t/bootstrap/earley-boolean.t` passes all 35 tests.
`t/bootstrap/perl-grammar-pipeline.t` passes all 20 tests.

### 7. content_hash on new nodes -- PASS (no issue)

TernaryExpr, StructRef, and StructFieldAccess have **no extra parametric
fields** beyond what the base class handles. Their only distinguishing
characteristics are their operation name and their inputs. The base
`Chalk::IR::Node::content_hash()` returns `join('|', operation, serialized_inputs)`,
which is correct and sufficient.

Nodes that DO have parametric fields (Call, PostfixDeref, CompoundAssign, Regex,
Constant, AnonSub) all override `content_hash()` to include those fields.
Verified in the source.

---

## Findings

### Critical (must fix before merge)

**C1. Scope violation: `_is_stmt_node`, `_stmt_inner`, `_rewrap_stmt` unreachable from `_fix_postfix_chain`**

- **File:** `lib/Chalk/Bootstrap/Perl/Actions.pm`
- **Line (committed):** `_fix_postfix_chain` at line 277 (plain `sub`), calls `_is_stmt_node` at line 539 (`my sub`)
- **Confidence:** 100
- **Impact:** Runtime crash -- `Undefined subroutine &Chalk::Bootstrap::Perl::Actions::_is_stmt_node` whenever `_fix_postfix_chain` encounters a SubscriptExpr wrapping a Return or Unwind node. Observed in `perl-actions-fixup.t` (test 54) and `perl-actions-tier-c.t` (test 20).
- **Root cause:** `_fix_postfix_chain` is a package-level `sub` (installed in the stash at compile time). `_is_stmt_node` is a lexical `my sub` defined later in the same block. Package subs resolve unqualified calls via the stash, not lexical scope, so `_is_stmt_node` is invisible.
- **Status:** Fix exists in uncommitted working directory changes (moves the three helpers before `_fix_postfix_chain`). **Must be committed.**

**C2. Test file `perl-ir-tier-a.t` crashes: `make('Constructor', class => 'MethodDecl')` dies**

- **File:** `t/bootstrap/perl-ir-tier-a.t:67-68`
- **Confidence:** 100
- **Impact:** Test suite aborts after test 13 with `Unknown or untranslated Constructor class: 'MethodDecl'`. The test also attempts `UseDecl`, `ClassDecl`, and `Program` via the Constructor factory, all of which are now metadata structs. The Return/Unwind sections were updated but the structural type sections were not.
- **Fix:** Rewrite tests 60-130 to construct `Chalk::IR::MethodInfo`, `Chalk::IR::UseInfo`, `Chalk::IR::ClassInfo`, and `Chalk::IR::Program` directly, matching the new APIs.

**C3. Test file `cfg-statements.t` crashes: `make('Constructor', class => 'Program')` dies**

- **File:** `t/bootstrap/cfg-statements.t:173`
- **Confidence:** 100
- **Impact:** Test suite aborts after test 23 with `Unknown or untranslated Constructor class: 'Program'`.
- **Status:** Fix exists in uncommitted working directory changes (uses `Chalk::IR::Program->new(other_stmts => [$if_node])`). **Must be committed.**

**C4. Test file `perl-actions-tier-b.t` crashes: tries to open deleted `Constructor.pm`**

- **File:** `t/bootstrap/perl-actions-tier-b.t:328`
- **Confidence:** 100
- **Impact:** Test suite aborts after test 89. The test section "5. Constructor.pm" tries to parse `lib/Chalk/Bootstrap/IR/Node/Constructor.pm` which no longer exists.
- **Status:** Fix exists in uncommitted working directory changes (replaces with `Phi.pm`). **Must be committed.**

### Important (should fix)

**I1. Uncommitted changes must be committed**

- **Files:** `lib/Chalk/Bootstrap/Perl/Actions.pm`, `lib/Chalk/Bootstrap/IR/Node.pm`, `lib/Chalk/Bootstrap/Scope.pm`, `t/bootstrap/cfg-statements.t`, `t/bootstrap/perl-actions-fixup.t`, `t/bootstrap/perl-actions-tier-b.t`
- **Confidence:** 100
- **Impact:** The working directory contains fixes for C1, C3, and C4 that are not yet committed. Per project policy, all changes must be tracked in git. If the working directory is reset, these fixes are lost.

**I2. Stale `isa Chalk::Bootstrap::IR::Node::Constructor` checks in 7 test files**

- **Files:**
  - `t/bootstrap/cfg-statements.t` (13 occurrences) -- partial fix in uncommitted changes
  - `t/bootstrap/perl-actions-fixup.t` (3 occurrences)
  - `t/bootstrap/perl-actions-tier-a.t` (6 occurrences)
  - `t/bootstrap/perl-actions-tier-b.t` (4 occurrences) -- partial fix in uncommitted changes
  - `t/bootstrap/perl-actions-tier-c.t` (6 occurrences)
  - `t/bootstrap/method-return-type.t` (2 occurrences)
  - `t/bootstrap/semiring-type-inference.t` (2 occurrences)
- **Confidence:** 90
- **Impact:** Since `Chalk::Bootstrap::IR::Node::Constructor` no longer exists, `isa` checks against it silently return false. This causes:
  - `method-return-type.t`: 3 test failures (cannot find MethodDecl nodes)
  - `semiring-type-inference.t`: 1 test failure (push multi-arg IR check)
  - Other tests: logic branches that check `isa Constructor && class() eq 'X'` silently skip, potentially masking regressions
- **Fix:** Replace `isa Chalk::Bootstrap::IR::Node::Constructor && ->class() eq 'X'` with the appropriate typed node check (`isa Chalk::IR::Node::Call`, `isa Chalk::IR::MethodInfo`, etc.) or `isa Chalk::IR::Node && ->class() eq 'X'`.

**I3. Stale comment in committed `lib/Chalk/Bootstrap/IR/Node.pm`**

- **File:** `lib/Chalk/Bootstrap/IR/Node.pm:11`
- **Confidence:** 100
- **Impact:** Comment references "Constant, Constructor, etc." but Constructor no longer exists. Fix exists in uncommitted changes.

### Suggestions (nice to have)

**S1. ABOUTME comment in `perl-ir-tier-a.t` mentions MethodDecl**

- **File:** `t/bootstrap/perl-ir-tier-a.t:2`
- **Confidence:** 80
- **Impact:** The ABOUTME says "Validates Program, UseDecl, ClassDecl, MethodDecl" -- once the test is updated, the ABOUTME should reflect the new types tested.

**S2. `BinOp` ADJUST fallback may confuse future maintainers**

- **File:** `lib/Chalk/IR/Node/BinOp.pm:13-16`
- **Confidence:** 60
- **Impact:** `left //= $self->inputs()->[0]` falls back to inputs[0], which for shim-created nodes is the operator, not the left operand. This path is never triggered in practice (the shim always passes `left` and `right` as explicit params), but if someone constructs a BinOp directly with only `inputs`, they would get the wrong `left`/`right`. Consider a comment documenting the expected inputs layout.

**S3. Consider removing `%STMT_BOUNDARY_CLASSES` line from committed Actions.pm**

- **File:** `lib/Chalk/Bootstrap/Perl/Actions.pm:28`
- **Confidence:** 70
- **Impact:** The uncommitted diff removes `%STMT_BOUNDARY_CLASSES` which references Constructor-era class names (ClassDecl, MethodDecl, etc.). If this hash is unused, removing it reduces dead code.

---

## Pre-existing Failures (not caused by this migration)

The following test failures exist at the base commit and are NOT regressions:

| Test file | Failures | Nature |
|---|---|---|
| `cfg-loop-phi.t` | 3 real + 1 TODO | Phi tracking incomplete |
| `cfg-loop.t` | 1 TODO | Postfix for not recognized |
| `concise-actions.t` | 1 TODO | Non-deterministic hash seeds |
| `concise-oracle.t` | 3 | for-loop concise tree |
| `c-build-pipeline.t` | 1 | XS Boolean methods |
| `c-data-model-classes.t` | 7 | C compilation issues |
| `codegen-pipeline.t` | crash | Calls `->inputs()` on Grammar::Rule |

These were confirmed by checking `git diff 2d2259e3..HEAD` shows zero changes to
these files.

---

## Architecture Assessment

### What was done well

1. **Clean separation of concerns.** The shim (`Chalk::IR::Shim`) acts as a
   pure translation layer with no side effects. The factory delegates to it
   without coupling.

2. **Backwards compatibility via `compat_class`.** The `class()` method on
   typed nodes returns the old Constructor class string (e.g., 'BinaryExpr',
   'SubscriptExpr'), allowing the entire codegen pipeline to work without
   changes to class-string dispatch.

3. **Intermediate base classes** (`BinOp`, `UnaryOp`, `Regex`, `Access`,
   `Aggregate`) enable polymorphic dispatch in fixup methods. The
   `isa Chalk::IR::Node::BinOp` check correctly matches all 28 binary
   operator subtypes.

4. **Hash consing preserved.** The factory creates a temporary node, computes
   its `content_hash`, checks the cache, and only then creates the final node.
   Nodes with parametric fields override `content_hash` appropriately.

5. **Metadata struct migration.** Program, ClassDecl, MethodDecl, SubDecl,
   FieldDecl, UseDecl, and _Attribute were correctly migrated to plain Perl
   classes (`Chalk::IR::Program`, `Chalk::IR::ClassInfo`, etc.) with
   direct field accessors, eliminating the inputs/class interface overhead.

### Risk areas

1. **The `_fix_postfix_chain` scope bug (C1)** was a real runtime failure,
   not just a cosmetic issue. The pattern of mixing `sub` and `my sub` in
   class scope is fragile. Consider converting `_fix_postfix_chain` to a
   `my sub` (with a coderef for recursion) or converting the helpers to
   package subs for consistency.

2. **7 test files still reference the deleted Constructor class.** While `isa`
   against a nonexistent class doesn't crash Perl, it silently skips test
   logic, which can mask regressions. These should be fixed before the branch
   is considered stable.

---

## Recommended Next Steps

1. **Commit the uncommitted fixes** (C1, C3, C4, I1, I3)
2. **Fix `perl-ir-tier-a.t`** (C2) -- rewrite structural type tests to use metadata structs
3. **Sweep remaining `isa Constructor` in tests** (I2) -- update all 7 files
4. **Run full test suite** and confirm zero new failures vs. baseline
5. **Consider converting `_fix_postfix_chain` to `my sub`** style for consistency (S1 risk area)
