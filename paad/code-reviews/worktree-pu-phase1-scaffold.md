# Agentic Code Review: Phase 1 Scaffold

**Date:** 2026-04-04
**Branch:** worktree-pu
**Base commit:** 2d2259e3
**Head commit:** 5c0b87cd

## Executive Summary

Phase 1 scaffold creates 63 node classes, 5 metadata structs, a hash-consing NodeFactory, and a Graph container with topological sort. All 230 tests across 9 test files pass. The implementation closely matches the design document's node hierarchy and follows project conventions (ABOUTME comments, `use 5.42.0`, `use utf8`, `feature class`, postfix deref). Two important issues exist around mutation methods not maintaining use-def chain invariants, and one latent bug in `content_hash()` with undefined inputs. No critical issues found.

## Critical Issues

None found.

## Important Issues

### I-1: Phi::set_backedge and Loop::set_backedge_ctrl do not update consumer use-def chains

**File:** `lib/Chalk/IR/Node/Phi.pm:19-21`, `lib/Chalk/IR/Node/Loop.pm:12-14`
**Confidence:** 95

Both `set_backedge($value)` and `set_backedge_ctrl($ctrl)` directly overwrite `inputs->[1]` but do not remove the old input's consumer reference or add the new input's consumer reference.

Verified by test: after calling `$phi->set_backedge($v3)`, the old input `$v2` still lists `$phi` as a consumer, while the new input `$v3` has zero consumers.

**Why it matters:** Use-def chains are a core invariant of the Sea of Nodes graph. Stale consumer references can cause the optimizer to believe a node is still in use when it has been replaced, preventing dead code elimination. Missing consumer references can cause the optimizer to incorrectly eliminate live nodes.

**Suggested fix:** Both methods should call `remove_consumer` on the old input (if defined) and `add_consumer` on the new input (if defined). For example:

```perl
method set_backedge($value) {
    my $old = $self->inputs()->[1];
    $old->remove_consumer($self) if defined $old;
    $self->inputs()->[1] = $value;
    $value->add_consumer($self) if defined $value;
}
```

### I-2: Node::content_hash() crashes on undef inputs

**File:** `lib/Chalk/IR/Node.pm:28`
**Confidence:** 90

The base `content_hash()` method does `map { $_->id() } $inputs->@*` which calls `->id()` on undef elements. Loop nodes are explicitly created with `undef` in `inputs->[1]` (backedge slot not yet wired).

Currently not triggered in practice because Loop is a CFG node (created via `make_cfg`, which does not call `content_hash`), but it is a latent bug if any code path calls `content_hash()` on a node with undef inputs.

**Suggested fix:** Filter undefs in the map: `map { defined $_ ? $_->id() : '_undef' } $inputs->@*`

### I-3: AnonSub content_hash uses refaddr -- nondeterministic across runs

**File:** `lib/Chalk/IR/Node/AnonSub.pm:19`
**Confidence:** 80

`refaddr($graph)` produces a memory address that varies between process invocations. This means the AnonSub node's id (derived from content_hash) is nondeterministic, which conflicts with the project's determinism requirement ("Code generation must produce byte-identical output across runs").

**Why it matters:** If codegen emits AnonSub node IDs in output, the output will differ between runs. However, in practice each AnonSub IS semantically unique (different closure body), so deduplication is wrong here. The real question is whether AnonSub should be hash-consed at all, or whether it should be treated as a CFG-like unique node created via `make_cfg`.

**Suggested fix:** Either (a) move AnonSub to `%CFG_CLASSES` and create via `make_cfg()` to give it a stable sequential ID, or (b) use a factory-level counter to produce deterministic unique IDs for AnonSub nodes.

## Suggestions

### S-1: TryCatch lacks the fields specified in the design doc

**File:** `lib/Chalk/IR/Node/TryCatch.pm`
**Confidence:** 70

The design doc specifies `TryCatch (try_body, catch_var, catch_body)` as named fields, but the implementation has no extra fields beyond what `Node` provides. The bodies would need to be passed through `inputs`, which is fine for a Phase 1 scaffold but may need named accessors (like BinOp's `left()`/`right()`) before the node is actually used. This is acceptable to defer to Phase 2/3, but worth noting.

### S-2: Consistent `no warnings 'experimental::class'` usage

**File:** Various
**Confidence:** 60

Only `Graph.pm` and `NodeFactory.pm` include `no warnings 'experimental::class'`. All other files rely on `use experimental 'class'` to suppress warnings, which is correct and sufficient. The two files with `no warnings` have a redundant pragma. This is purely cosmetic -- the pragma is harmless -- but removing it from the two files would be slightly more consistent.

### S-3: Test for FieldAccess and CompoundAssign content_hash correctness

**Confidence:** 70

The test files verify content_hash for Constant, Phi, PadAccess, Call, BinOp, and UnaryOp, but do not explicitly test FieldAccess's custom content_hash (which includes field_index and field_stash), CompoundAssign's (includes op), PostfixDeref's (includes sigil), or Regex's (includes flags). These overrides exist and were verified to work via ad-hoc testing during this review, but having explicit unit tests for them would improve confidence.

### S-4: content_hash delimiter collision potential

**Confidence:** 65

The pipe `|` character is used as a delimiter in content_hash strings, but values (like Constant value, Call name, PadAccess varname) are not escaped. A value containing `|` would create an ambiguous hash. In practice, Perl variable names and function names cannot contain `|`, and constant values containing `|` are unlikely to collide with structurally different hashes. This is a theoretical concern unlikely to cause real issues, but worth documenting.

## Plan Alignment

### Implemented (Phase 1 complete)

- Chalk::IR::Node base class with id, inputs, consumers, stamp, operation(), content_hash()
- All 7 CFG node types: Start, Return, Unwind, If, Proj, Region, Loop
- BinOp intermediate base class with left(), right(), op_str()
- All 29 BinOp leaf types with correct operation/op_str pairs
- UnaryOp intermediate base class with operand(), op_str()
- All 4 UnaryOp leaf types with correct operation/op_str pairs
- Access intermediate base class; PadAccess (targ, varname), FieldAccess (field_index, field_stash), StashAccess, Subscript
- Aggregate intermediate base class; HashRef, ArrayRef, Interpolate
- Regex intermediate base class (flags); RegexMatch, RegexSubst
- Call (dispatch_kind, name)
- Constant (value, const_type), Phi (region, set_backedge)
- AnonSub (graph), TryCatch, PostfixDeref (sigil), CompoundAssign (op), BacktickExpr, VarDecl
- Loop (set_backedge_ctrl)
- Chalk::IR::NodeFactory with hash consing for data nodes, sequential IDs for CFG nodes
- Chalk::IR::Graph with BFS node discovery and DFS topological sort
- 5 metadata structs: Program, ClassInfo, MethodInfo, SubInfo, FieldInfo
- 9 test files with 230 passing tests covering all acceptance criteria

### Not yet implemented (Phases 2-5)

- Phase 2: Factory shim (old-style `make('Constructor', class => ...)` translation)
- Phase 3a: Computation node migration in Actions.pm
- Phase 3b: Structural split (metadata structs instead of Constructor nodes)
- Phase 4: Consumer migration (file-by-file `->class()` to `isa` checks)
- Phase 5: Delete Constructor and old namespace

### Deviations

- **TryCatch fields omitted**: Design doc says `(try_body, catch_var, catch_body)` but implementation has no named fields. Acceptable for Phase 1 scaffold; the design doc itself says TryCatch "remains a typed computation node until the exception design lowers it to CFG structure."
- **No `->class()` backward compatibility shim**: The design doc mentions each new typed node providing a `->class()` method for backward compatibility during migration. This is Phase 2 work, correctly deferred.
- **AnonSub uses refaddr for content_hash**: Not specified in design doc. See I-3 above.

## Review Metadata

- Files reviewed: 80 (63 node classes, 5 metadata structs, 1 base class, 1 factory, 1 graph, 9 test files)
- Raw findings: 9
- Verified findings: 7 (3 Important, 4 Suggestions)
- All 230 tests pass across 9 test files
- All operator/op_str pairs verified correct for 29 BinOp and 4 UnaryOp types
- Hash consing verified: identical inputs produce same node object; different inputs produce different objects
- Consumer registration verified: cache hits do not double-register; tmp nodes do not leak consumers
