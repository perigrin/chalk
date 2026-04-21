# Polymorphic SoN IR Migration — In Progress

> **ARCHIVED** — superseded by
> [2026-04-21-chalk-mop-migration-plan.md](2026-04-21-chalk-mop-migration-plan.md).
> The remaining work (Constructor call sites, Shim deletion,
> codegen migration, full SSA) lands through the MOP migration's
> phases rather than as a separate direct migration. This document
> is kept as reference for the Target Architecture and Outstanding
> Work sections, which describe the pre-MOP state this work
> replaces.

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
`Graph` (18 `->body()` call sites total). See "Outstanding Work" and
"Acceptance Criteria" below.

**Deeper structural issue** (scoped as design task D3): Chalk's IR is
currently a tree of metadata structs (`Program` → `ClassInfo` →
`MethodInfo`) with a SoN `Graph` only at method scope. The metadata
structs don't participate in the use-def chain — they're scaffolding
that lets typed nodes reference them without breaking the factory
protocol. A correct Sea of Nodes is a single graph where method, class,
and program boundaries are subgraph structure. Reaching that shape
(Program-as-graph-of-class-graphs-of-method-graphs) is load-bearing for
fixing problems surfaced during alignment review — consumer-traversal
safety in `Graph.nodes()`, eliminating the parse-time backchannel in
codegen, class-body context tracking for declarator enforcement,
program-scope optimization passes, and more. The polymorphic migration
tracked here is a prerequisite for that work but does not by itself
close the gap.

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
- **`body` field on `Chalk::IR::ClassInfo`** remains. Holds source-order
  body items as parallel state to the typed `fields`/`methods`/`subs`
  collections. `StructPromotion` reads it to walk body items in source
  order. Removal depends on the program-level graph design (D3) — once
  `ClassInfo` becomes graph-shaped, source order is preserved by graph
  edges and the redundant `body` field can be dropped.
- **Codegen has not migrated.** 18 `->body()` call sites across four
  files:
  - `lib/Chalk/Bootstrap/Perl/Target/Perl.pm` (4 sites)
  - `lib/Chalk/Bootstrap/Perl/Target/C.pm` (6 sites)
  - `lib/Chalk/Bootstrap/Perl/Target/EmitHelpers.pm` (2 sites)
  - `lib/Chalk/Bootstrap/Optimizer/StructPromotion.pm` (6 sites)
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
- The `body` field on `Chalk::IR::ClassInfo` is either removed (if D3
  lands first and source order is carried by graph edges) or explicitly
  deferred to the D3 graph-shaped Program work with a tracked issue.
  Do not declare this migration complete with `ClassInfo.body` still
  present and no deferral path documented.
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

### Typed Computation Nodes (79 classes under Chalk::IR::Node/: 74 concrete + 5 intermediate bases)

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

1. **Phase 1**: 79 typed node classes (74 concrete + 5 intermediate bases), NodeFactory, Graph, metadata structs.
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
