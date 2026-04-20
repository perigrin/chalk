# Polymorphic SoN IR Migration — In Progress

## Status

This document describes an in-progress migration from the Constructor
type-case dispatch pattern to typed node subclasses under
`Chalk::IR::Node::*`, with program structure separated into metadata
structs and SSA-style scope tracking added. The migration is
approximately 80% complete.

The target architecture described below is partially realized: typed
nodes, the `NodeFactory`, `Graph`, and metadata structs exist; semantic
actions build graphs (via `_build_method_graph`) during parsing; the
reverse-bridge namespace `Chalk::Bootstrap::IR::Node::*` has been
removed.

Transitional scaffolding remains: `Chalk::IR::Shim`, the `compat_class`
field on `Chalk::IR::Node`, the `body` field on `MethodInfo`, and 61
`make('Constructor', ...)` call sites in
`lib/Chalk/Bootstrap/Perl/Actions.pm`. The largest outstanding piece is
codegen: 17 `->body()` call sites across the Perl and C targets, plus
`StructPromotion`, still read `MethodInfo->body` instead of walking the
`Graph`. See "Outstanding Work" and "Acceptance Criteria" below.

## Outstanding Work

- **61 `make('Constructor', ...)` call sites** in
  `lib/Chalk/Bootstrap/Perl/Actions.pm` still use the old API. These
  currently work via `Chalk::IR::Shim`.
- **`Chalk::IR::Shim` is still live.** Consumers: `NodeFactory.pm`,
  `Perl/Actions.pm`, `Optimizer/StructPromotion.pm`, and four test
  files. Deletion of Shim.pm is blocked until the above call sites are
  converted.
- **`compat_class` field on `Chalk::IR::Node`** remains, set by the
  Shim and read by `Node::class()` to override the default class name.
- **`body` field on `Chalk::IR::MethodInfo`** remains. All codegen and
  optimizer passes still read it instead of the `graph`.
- **Codegen has not migrated.** 17 `->body()` call sites across four
  files:
  - `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` (4 sites)
  - `lib/Chalk/Bootstrap/Perl/Target/C.pm` (6 sites)
  - `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (2 sites)
  - `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` (5 sites)
- **`_build_method_graph` is a graph-seeding pass, not a full SSA
  builder.** It stitches control nodes, collects explicit and implicit
  `Return`/`Unwind` exits, and seeds `body_stmts` so side-effect nodes
  are reachable. It does not perform Phi insertion, dominator analysis,
  or rewrite data-flow edges. Codegen consumers do not yet walk the
  resulting graph. The `body_stmts` seeding in `Chalk::IR::Graph` and
  the `consumers`-traversal exclusion in `Graph::nodes()` are both
  workarounds that disappear when full SSA construction lands and
  hash-consing distinguishes graph-local nodes from globally-shared
  constants.
- **2 pipeline tests crash** after passing assertions:
  `ir-program-pipeline`, `ir-sub-info-pipeline`.
- **Codegen targets do not conform to the uniform `Target` interface.**
  `Perl/Target/C.pm` exposes only `generate_c_files($ir, $sa, $ctx)` and
  `generate_xs_wrapper($ir, ...)`, and `Perl/Target/Perl.pm` has a
  `generate_with_cfg($ir, $sa, $ctx)` alongside its `generate($ir)`.
  These context-aware methods exist because codegen needs to recover
  `cfg_state` annotations by walking the parse-time Context tree;
  once the graph is a complete SSA representation, codegen can walk it
  directly and the `($sa, $ctx)` backchannel can be removed.
- **Design docs need updating** to reflect implementation divergences
  (this document is part of that update).

## Acceptance Criteria

The migration is complete when all of the following hold:

- Zero `make('Constructor', ...)` call sites in
  `lib/Chalk/Bootstrap/Perl/Actions.pm`.
- `lib/Chalk/IR/Shim.pm` is deleted; no files reference
  `Chalk::IR::Shim`.
- The `compat_class` field is removed from `Chalk::IR::Node`.
- The `body` field is removed from `Chalk::IR::MethodInfo`; all readers
  have migrated to `graph`.
- All codegen and optimizer passes walk the `Graph` instead of
  `->body()`. Target files: `Perl/Target/Perl.pm`, `Perl/Target/C.pm`,
  `Perl/Target/EmitHelpers.pm`, `Optimizer/StructPromotion.pm`.
- `_build_method_graph` constructs a complete SoN graph with Phi
  insertion.
- `ir-program-pipeline` and `ir-sub-info-pipeline` tests pass.
- Every codegen target derives its output purely from the IR — no target
  exposes context-aware entry points that require `$sa` or `$ctx` arguments.
  (The final interface shape is subject to the separate D1 design work;
  this criterion is about eliminating the parse-time backchannel, not about
  the `generate` / `generate_distribution` split.)

## Target Architecture

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
      body: [IR nodes]           (transitional; to be removed)
      graph: Chalk::IR::Graph (start, returns, schedule)
    subs: [SubInfo]
  top_level_subs: [SubInfo]
```

### Factory + Shim (transitional)

`Chalk::Bootstrap::IR::NodeFactory::make('Constructor', class => 'X', ...)`
routes through `Chalk::IR::Shim::translate()`, which maps Constructor
class names to typed nodes. All grammar operators are in the
BINOP_MAP/UNOP_MAP. The Shim is scaffolding: once all call sites use
the typed-node API directly, the Shim and the `make('Constructor', ...)`
entry point will be removed.

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
- `body_stmts`: top-level and CFG-region statements for reachability

The graph is seeded during parsing by `_build_method_graph` in the
MethodDefinition semantic action, which walks the Context subtree for
`cfg_state` entries. The current implementation stitches control nodes
and exits correctly but does not yet perform full SSA construction
(Phi insertion, dominator analysis) — see "Outstanding Work".

## Phase History

1. **Phase 1**: 76 typed node classes, NodeFactory, Graph, metadata structs.
2. **Phase 2**: Shim translates all computation Constructor classes.
3. **Phase 3**: All non-Actions.pm consumer files migrated to typed isa checks.
4. **Phase 4a**: SSA scope (reassignment tracking, if/else Phis, loop Phis).
5. **Phase 4b**: All 7 structural types migrated to metadata;
   `ReturnStmt` → `Return`, `DieCall` → `Unwind`.
6. **Phase 5 (partial)**: `Constructor.pm` deleted as a class;
   `Chalk::Bootstrap::IR::Node::*` reverse bridge removed; BNF
   migrated. Remaining: Actions.pm call sites, Shim.pm deletion,
   `compat_class`/`body` field removal, codegen graph-walk migration,
   `_build_method_graph` SSA completion. See "Acceptance Criteria".
