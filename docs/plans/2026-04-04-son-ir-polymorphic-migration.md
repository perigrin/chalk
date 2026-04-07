# Polymorphic SoN IR Migration — Final State

## Summary

This migration replaced the Constructor type-case dispatch pattern with
typed node subclasses under `Chalk::IR::Node::*`, separated program
structure into metadata structs, and added SSA-style scope tracking.

**Constructor.pm is deleted.** All computation types produce typed nodes
via the Shim. Structural types produce metadata structs directly.

## Architecture

### Typed Computation Nodes (76 classes under Chalk::IR::Node/)

```
Chalk::IR::Node (base: id, inputs, consumers, stamp, operation, content_hash)
├── CFG: Start, Return, Unwind, If, Proj, Region, Loop
├── BinOp (left, right, op_str): Add, Subtract, ..., Assign, Range, IsaOp (29 types)
├── UnaryOp (operand, op_str): Not, Negate, Complement, Defined, UnaryPlus, Ref
├── Data: Constant, Phi
├── Access: PadAccess, FieldAccess, StashAccess, Subscript
├── Call (dispatch_kind, name)
├── Aggregate: HashRef, ArrayRef, Interpolate
├── AnonSub (graph)
├── Regex: RegexMatch, RegexSubst
├── TernaryExpr, TryCatch, PostfixDeref, CompoundAssign, BacktickExpr, VarDecl
└── StructRef, StructFieldAccess
```

### Program Metadata (6 structs under Chalk::IR/)

```
Chalk::IR::Program
  use_decls: [UseInfo]
  classes: [ClassInfo]
    fields: [FieldInfo]
    methods: [MethodInfo]
      body: [IR nodes]
      graph: Chalk::IR::Graph (start, returns, schedule)
    subs: [SubInfo]
  top_level_subs: [SubInfo]
```

### Factory + Shim

`Chalk::Bootstrap::IR::NodeFactory::make('Constructor', class => 'X', ...)`
routes through `Chalk::IR::Shim::translate()` which maps Constructor class
names to typed nodes. All grammar operators are in the BINOP_MAP/UNOP_MAP.

### SSA Scope

- Variable reassignments (`$x = expr`) update the scope
- If/else branches create Phis eagerly at Region merge (Click-style)
- Loop Phis created in ForeachStatement/WhileStatement via merge_for_loop
- Trivial Phi removal inline
- No post-hoc Phi pass in Program()

### Per-Method Graphs

Each MethodInfo/SubInfo carries a `Chalk::IR::Graph` with:
- `start`: the Start CFG node
- `returns`: [Return, Unwind] CFG terminators
- `schedule`: hashref mapping node IDs to control flow context

The schedule is built during parsing in the MethodDefinition semantic
action by walking the Context subtree for cfg_state entries.

## Completed Phases

1. **Phase 1**: 76 typed node classes, NodeFactory, Graph, metadata structs
2. **Phase 2**: Shim translates all computation Constructor classes
3. **Phase 3**: All consumer files migrated to typed isa checks
4. **Phase 4a**: SSA scope (reassignment tracking, if/else Phis, loop Phis)
5. **Phase 4b**: All 7 structural types → metadata, ReturnStmt → Return, DieCall → Unwind
6. **Phase 5**: Constructor.pm deleted, inheritance bridge inverted, BNF migrated

## Remaining Work

- 64 `make('Constructor', ...)` calls in Actions.pm use old API (work via shim)
- 2 pipeline tests crash after passing all assertions (ir-program-pipeline, ir-sub-info-pipeline)
- Design docs need updating to reflect implementation divergences
- Old `Chalk::Bootstrap::IR::Node::*` namespace still exists (reverse bridge)
- `compat_class` field still on Chalk::IR::Node (needed for old API)
