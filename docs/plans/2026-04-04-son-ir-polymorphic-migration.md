# Polymorphic SoN IR Migration

## Problem

Chalk's IR uses a single `Constructor` class with a string `$class` field to
represent 30 semantically distinct node types. Every consumer recovers type
information through string comparison:

```perl
my $class = $node->class();
if ($class eq 'BinaryExpr')   { ... }
elsif ($class eq 'MethodDecl') { ... }
```

This pattern appears across 174 call sites in 8 files. It prevents the
compiler from catching type errors at compile time, makes dispatch fragile,
and blocks convergence with perl5-son's typed node hierarchy.

## Goal

Replace Constructor's type-case dispatch with typed node subclasses under
`Chalk::IR::Node::*`. Separate program structure metadata from executable
computation graphs, following Cliff Click's Sea of Nodes architecture.

## Architecture: Two-Tier IR

Click's SoN represents executable computation within a single method. Class
declarations, field layouts, and module structure live outside the graph in
metadata. Every production SoN compiler (C2, Graal, TurboFan) follows this
separation. Chalk adopts it.

### Tier 1: Program Metadata

Plain data containers describing program organization. No `operation()`,
no `content_hash()`, no hash consing.

```
Chalk::IR::Program
  use_decls: [{module, args}]
  classes: [Chalk::IR::ClassInfo]
    name, parent
    fields: [Chalk::IR::FieldInfo]
      name, attributes, default_value
    methods: [Chalk::IR::MethodInfo]
      name, params, return_type
      graph: Chalk::IR::Graph        # per-method SoN graph
    subs: [Chalk::IR::SubInfo]
      name, params, scope
      graph: Chalk::IR::Graph
  top_level_subs: [Chalk::IR::SubInfo]
```

**Migrated from Constructor:** Program, ClassDecl, MethodDecl, SubDecl,
FieldDecl, UseDecl. These were never computation nodes.

### Tier 2: SoN Computation Graphs

Each method/sub body becomes its own `Chalk::IR::Graph` (one Start node,
one or more Return/Unwind terminators).

```
Chalk::IR::Node (base)
  id, inputs, consumers, stamp
  operation(), content_hash()

CFG nodes (unique per instance, not hash-consed):
  Start                          # graph entry
  Return                         # normal exit (value)
  Unwind                         # exceptional exit (die)
  If                             # conditional branch
  Proj (index)                   # projection from multi-output node
  Region                         # control merge
  Loop                           # loop header

BinOp (left, right):             # intermediate base class
  Add, Subtract, Multiply, Divide, Modulo, Power
  Concat
  NumEq, NumNe, NumLt, NumGt, NumLe, NumGe, NumCmp
  StrEq, StrNe, StrLt, StrGt, StrLe, StrGe, StrCmp
  And, Or
  BitAnd, BitOr, BitXor, LeftShift, RightShift
  Assign

UnaryOp (operand):               # intermediate base class
  Not, Negate, Complement
  Defined

Data nodes (hash-consed):
  Constant (value, stamp)
  Phi

Access:                          # intermediate base class
  PadAccess (targ, varname)
  FieldAccess (field_index, field_stash)
  StashAccess
  Subscript

Call (dispatch_kind, name)       # methods, subs, builtins
  Two control projections: normal continuation + exceptional edge

Aggregate:                       # intermediate base class
  HashRef
  ArrayRef
  Interpolate

AnonSub                          # contains nested Chalk::IR::Graph

Regex:                           # intermediate base class
  RegexMatch (flags)
  RegexSubst (flags)

PostfixDeref (sigil)
CompoundAssign (op)              # or lower to read+binop+assign
BacktickExpr
```

## Key Design Decisions

### Typed Subclasses, Not String Dispatch

Each Constructor class becomes its own Perl class. Consumers use `isa`
checks instead of string comparison:

```perl
# Before
if ($node->class() eq 'BinaryExpr') { ... }

# After
if ($node isa Chalk::IR::Node::BinOp) { ... }
```

### Intermediate Base Classes

Related nodes share a base class that provides common accessors:

- **BinOp**: `left()`, `right()` (aliases for `inputs->[0]`, `inputs->[1]`)
- **UnaryOp**: `operand()` (alias for `inputs->[0]`)
- **Access**: grouping for variable/field/subscript access
- **Aggregate**: grouping for collection constructors
- **Regex**: grouping for regex operations

These serve two purposes: shared behavior and group-level `isa` checks
for consumers that handle all binary ops identically.

### BinaryExpr Decomposition

`Constructor:BinaryExpr` with an `op` field becomes one SoN type per
operator. The operator string is encoded in the type:

| Constructor | SoN Type |
|---|---|
| `BinaryExpr(op="+")` | `Add` |
| `BinaryExpr(op=".")` | `Concat` |
| `BinaryExpr(op="==")` | `NumEq` |
| `BinaryExpr(op="&&")` | `And` |

Consumers that need the operator string can call `operation()`.

### Exception Model: Unwind + Dual Projections

`die` is a CFG terminator, not a function call. Both `return` and `die`
exit the graph:

- **Return**: normal exit, carries return value
- **Unwind**: exceptional exit, carries exception value (goes to `$@`)

Every `Call` node produces two control projections:

```
Call ──Proj[0]──→ normal continuation
  └───Proj[1]──→ exceptional edge
```

The exceptional edge flows to a catch handler (Region merging exception
paths) or propagates via Unwind. Any Perl call can die, so all Call nodes
carry exceptional edges. The optimizer can remove them when it proves a
call cannot throw.

`TryCatchStmt` becomes CFG structure: the try body's Call exceptional edges
flow to a catch Region, which either handles and continues or re-unwinds.

This matches Graal's exception model and corrects perl5-son's current
simplification of `die` as a `Call` node.

### Builtins: Call Now, Specialize Later

Production SoN compilers (C2, Graal) start with generic Call nodes for
builtins and replace them with specialized intrinsic types during
optimization. Chalk follows the same pattern:

- All builtins (`push`, `map`, `grep`, `sin`, `defined`, etc.) start as
  `Call` with `dispatch_kind => 'builtin'`
- Intrinsic node types (`Sin`, `Map`, etc.) are added when optimization
  passes need them
- `Defined` already exists as a specialized type (inherited from SoN)

### Namespace: Chalk::IR::Node::*

All node types live under `Chalk::IR::Node::*`. No external dependency on
perl5-son at runtime. Node types originate in perl5-son's design, then are
inlined into Chalk's codebase.

### perl5-son Convergence

perl5-son should adopt the same design decisions:

- Add Unwind CFG node (replace `die` → `Call` mapping)
- Add dual projections on Call nodes (normal + exceptional)
- Add Perl-specific node types: HashRef, ArrayRef, Interpolate, AnonSub,
  RegexMatch, RegexSubst, PostfixDeref, CompoundAssign, VarDecl,
  BacktickExpr

Both projects produce the same graph vocabulary, enabling `SoN::Compare`
to do structural diff between Chalk's parser output and perl5-son's optree
translation.

## Migration Strategy

### Approach: Adapter Shim with Gradual Migration

Constructor gains a backward-compatible shim. Consumers migrate
file-by-file from `->class()` string checks to `isa` type checks.

During migration, each new typed node provides a `->class()` method
returning its old Constructor class name. This keeps unmigrated consumers
working.

### Factory Shim

`Chalk::IR::NodeFactory` wraps the new type system. The old singleton
`Chalk::Bootstrap::IR::NodeFactory::instance()` returns a thin wrapper
that delegates internally.

Old-style creation:
```perl
$factory->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right)
```

Translates internally to:
```perl
$factory->make('Add', inputs => [$left, $right])  # when op is '+'
```

The singleton goes away when all callers switch to the new API.

### Migration Phases

**Phase 1: Scaffold new types.**
Create `Chalk::IR::Node` base class and all typed subclasses. Create
`Chalk::IR::Graph`. Create metadata types (Program, ClassInfo, MethodInfo,
FieldInfo, SubInfo). Add corresponding types to perl5-son.

**Phase 2: Factory shim.**
Rewrite NodeFactory to accept both old-style and new-style creation. Map
old Constructor classes to new types internally.

**Phase 3: Actions.pm creation sites.**
Migrate 87 `make('Constructor', ...)` calls in Actions.pm to new-style
API. Split method body IR creation from structural metadata extraction.

**Phase 4: Consumer migration (file-by-file).**
Replace `->class() eq 'X'` with `isa Chalk::IR::Node::X`. Order by
increasing risk:

1. ToSoN.pm — delete entirely (adapter no longer needed)
2. DCE.pm — few type checks
3. DepChaser.pm — few type checks
4. StructPromotion.pm — pattern matching on node types
5. BNF/Actions.pm — 4 Constructor uses
6. EmitHelpers.pm — medium
7. Target/Perl.pm — large, codegen dispatch
8. Target/C.pm — largest, XS codegen

**Phase 5: Delete Constructor and old namespace.**
Remove `Chalk::Bootstrap::IR::Node::Constructor`, all
`Chalk::Bootstrap::IR::Node::*` classes, the singleton wrapper, and
`->class()` shim methods.

**Phase 6: Codegen restructuring.**
Target/Perl.pm and Target/C.pm switch from walking a single tree to
walking metadata structure for program/class/method scaffolding and
per-method `Chalk::IR::Graph` for method body codegen.

## Call Site Census

| File | `->class()` checks | `make('Constructor')` calls |
|---|---|---|
| Perl/Actions.pm | 56 | 87 |
| Perl/Target/Perl.pm | 19 | 0 |
| Perl/Target/C.pm | 35 | 0 |
| Perl/Target/EmitHelpers.pm | 35 | 0 |
| Optimizer/StructPromotion.pm | 20 | 7 |
| DepChaser.pm | 2 | 0 |
| Grammar/BNF/Actions.pm | 6 | 4 |
| IR/ToSoN.pm | 1 | 0 |
| **Total** | **174** | **98** |

## Open Questions

1. **CompoundAssign**: Lower to read+binop+assign sequence, or keep as a
   distinct node type? Lowering reduces the node vocabulary but adds a
   lowering pass.

2. **TernaryExpr**: Lower to If+Proj+Region+Phi during parsing (as ToSoN
   already does), or keep as a node and lower in a separate pass?

3. **PostfixDeref**: Does perl5-son need this, or does the optree handle
   dereferencing differently? May need investigation.

4. **BacktickExpr**: Lower to a Call to `readpipe()`, or keep as a
   distinct type?

## Dependencies

- perl5-son: Add Unwind, dual Call projections, and Perl-specific node
  types before Chalk can converge fully
- Chalk Perl 5.42.0: All new classes use `feature class`
