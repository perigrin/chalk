# Pushback Review: Polymorphic SoN IR Migration

**Date:** 2026-04-04
**Spec:** docs/plans/2026-04-04-son-ir-polymorphic-migration.md
**Commit:** e89fad0e (pre-review)

## Source Control Conflicts

None — no conflicts with recent changes.

## Issues Reviewed

### [1] Phase 3 Actions.pm is underspecified and entangled with scope/Phi tracking
- **Category:** feasibility
- **Severity:** serious
- **Issue:** Program() doesn't just collect statements — it does Phi insertion for loop-carried variables, walking computation nodes at the structural level. Codegen crosses the metadata/graph boundary constantly (_scope_body_vars walks body items, _emit_class_decl walks body calling _emit_node). The design underestimated the entanglement.
- **Resolution:** Phase 3 split into 3a (computation node migration) and 3b (structural split + Phi/scope restructuring). Doc updated.

### [2] Phase 6 codegen restructuring must happen with consumer migration, not after
- **Category:** feasibility
- **Severity:** serious
- **Issue:** Target/Perl.pm and Target/C.pm can't just swap isa checks — their entry points must be restructured to walk metadata + per-method graphs. Phase 6 as separate from Phase 4 was wrong.
- **Resolution:** Merged Phase 6 into Phase 4 items 7-8. Entry point restructuring happens alongside consumer migration for codegen files.

### [3] Dual projections on all Call nodes is massive scope expansion
- **Category:** scope imbalance
- **Severity:** serious
- **Issue:** Every Call getting dual projections roughly triples graph node count for call-heavy code. Implementing it requires changing Call construction, exception edge threading, all codegen backends, TryCatch handling, and optimizer. That's a project larger than the type migration itself.
- **Resolution:** Deferred to separate design doc. This migration creates Unwind node type but doesn't wire exceptional edges. TryCatch stays as typed node until exception design lands.

### [4] operation() doesn't return Perl operator strings
- **Category:** ambiguity
- **Severity:** moderate
- **Issue:** After BinaryExpr splits into Add/NumEq/etc., codegen needs the Perl operator string ('+', '==') for emission. operation() returns 'Add', not '+'.
- **Resolution:** Each BinOp/UnaryOp subclass implements op_str() returning the Perl operator. Codegen calls $node->op_str().

### [5] BNF-level Constructor nodes not addressed
- **Category:** omission
- **Severity:** moderate
- **Issue:** Constructor:Symbol/Expression/Rule used by BNF pipeline (4 creation sites, 6 type checks) not mentioned in design.
- **Resolution:** Excluded from this migration (stable, small pipeline). Correct disposition is metadata structs — deferred to separate ticket.

### [6] Hash consing semantics change with BinaryExpr decomposition
- **Category:** ambiguity
- **Severity:** moderate
- **Issue:** During migration, old-style and new-style factory calls could create different cache entries for the same computation if the factory produced different node types for each style.
- **Resolution:** Factory shim eagerly translates old-style calls to new types. No Constructor nodes ever enter the cache. One cache, consistent hashes.

### [7] _Attribute Constructor class missing from design
- **Category:** omission
- **Severity:** minor
- **Issue:** Constructor:_Attribute (for :param, :reader, :writer) not in taxonomy.
- **Resolution:** Folded into FieldInfo.attributes as plain data (arrayref of {name => 'param'} hashes).

### [8] No rollback strategy for mid-migration breakage
- **Category:** omission
- **Severity:** serious
- **Issue:** If Actions.pm emits metadata structs but codegen hasn't been updated, the 16 green files break with no path back.
- **Resolution:** Phase 3b (structural split) and Phase 4 items 7-8 (codegen restructuring) are atomic. Land as one unit, verified against 16 green files.

### [9] TryCatchStmt disposition unclear
- **Category:** ambiguity
- **Severity:** minor
- **Issue:** Design said TryCatch "becomes CFG structure" but exception flow was deferred.
- **Resolution:** TryCatch becomes Chalk::IR::Node::TryCatch typed computation node. Stays in graph until exception design lowers it to CFG.

### [10] No test strategy
- **Category:** omission
- **Severity:** moderate
- **Issue:** 174 call sites changing with no specified acceptance criteria per phase.
- **Resolution:** Added explicit acceptance criteria: Phase 1 unit tests for node types, Phase 2 factory shim verified, Phase 3b+4.7-8 verified against 16 green files, Phase 5 grep verification.

## Unresolved Issues

None — all issues addressed.

## Summary

- **Issues found:** 10
- **Issues resolved:** 10
- **Unresolved:** 0
- **Spec status:** Ready for implementation planning
