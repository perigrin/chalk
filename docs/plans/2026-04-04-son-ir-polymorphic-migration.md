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

## Architecture: Metadata + Per-Method SoN Graphs

Click's SoN represents executable computation within a single method. Class
declarations, field layouts, and module structure live outside the graph in
metadata. Every production SoN compiler (C2, Graal, TurboFan) follows this
separation. Graal receives bytecode with class/method structure already
resolved by the JVM class loader; perl5-son's FromOptree receives one CV at
a time with stash/pad structure already resolved by `perl -c`. In both
cases, structural metadata exists before the SoN graph is built.

Chalk's parser already does this work. Semantic actions for ClassDecl,
MethodDecl, and FieldDecl accumulate structural context during parsing.
When a MethodDecl completes, the full method body is available. The
semantic actions produce metadata structs (ClassInfo, MethodInfo) directly,
with a per-method `Chalk::IR::Graph` inside each one. No structural IR
nodes exist at any point.

### Program Metadata (not IR nodes)

Plain data containers produced directly by semantic actions. No
`operation()`, no `content_hash()`, no hash consing.

```
Chalk::IR::Program
  use_decls: [{module, args}]
  classes: [Chalk::IR::ClassInfo]
    name, parent
    fields: [Chalk::IR::FieldInfo]
      name, attributes: [{name => 'param'}, ...], default_value
    methods: [Chalk::IR::MethodInfo]
      name, params, return_type
      graph: Chalk::IR::Graph        # per-method SoN graph
    subs: [Chalk::IR::SubInfo]
      name, params, scope
      graph: Chalk::IR::Graph
  top_level_subs: [Chalk::IR::SubInfo]
```

**Eliminated Constructor classes:** Program, ClassDecl, MethodDecl, SubDecl,
FieldDecl, UseDecl, _Attribute. These become metadata structs or fields
within metadata structs (e.g., _Attribute folds into FieldInfo.attributes).

### SoN Computation Graphs

Each method/sub body becomes its own `Chalk::IR::Graph` (one Start node,
one or more Return/Unwind terminators).

```
Chalk::IR::Node (base)
  id, inputs, consumers, stamp
  operation(), content_hash()

CFG nodes (unique per instance, not hash-consed):
  Start                          # graph entry
  Return                         # normal exit (value)
  Unwind                         # exceptional exit (die) [see Exception Model]
  If                             # conditional branch
  Proj (index)                   # projection from multi-output node
  Region                         # control merge
  Loop                           # loop header

BinOp (left, right, op_str):     # intermediate base class
  Add, Subtract, Multiply, Divide, Modulo, Power
  Concat
  NumEq, NumNe, NumLt, NumGt, NumLe, NumGe, NumCmp
  StrEq, StrNe, StrLt, StrGt, StrLe, StrGe, StrCmp
  And, Or
  BitAnd, BitOr, BitXor, LeftShift, RightShift
  Assign

UnaryOp (operand, op_str):       # intermediate base class
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

Aggregate:                       # intermediate base class
  HashRef
  ArrayRef
  Interpolate

AnonSub                          # contains nested Chalk::IR::Graph

Regex:                           # intermediate base class
  RegexMatch (flags)
  RegexSubst (flags)

TryCatch (try_body, catch_var, catch_body)   # typed node until exception
                                              # design lowers to CFG

PostfixDeref (sigil)
CompoundAssign (op)              # or lower to read+binop+assign
BacktickExpr
VarDecl
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

- **BinOp**: `left()`, `right()` (aliases for `inputs->[0]`, `inputs->[1]`),
  `op_str()` (abstract — each subclass returns its Perl operator string,
  e.g., Add returns `'+'`, NumEq returns `'=='`)
- **UnaryOp**: `operand()` (alias for `inputs->[0]`),
  `op_str()` (e.g., Not returns `'!'`, Negate returns `'-'`)
- **Access**: grouping for variable/field/subscript access
- **Aggregate**: grouping for collection constructors
- **Regex**: grouping for regex operations

These serve two purposes: shared behavior and group-level `isa` checks
for consumers that handle all binary ops identically.

### BinaryExpr Decomposition

`Constructor:BinaryExpr` with an `op` field becomes one SoN type per
operator. The operator string is encoded in the type:

| Constructor | SoN Type | `op_str()` |
|---|---|---|
| `BinaryExpr(op="+")` | `Add` | `'+'` |
| `BinaryExpr(op=".")` | `Concat` | `'.'` |
| `BinaryExpr(op="==")` | `NumEq` | `'=='` |
| `BinaryExpr(op="&&")` | `And` | `'&&'` |

Codegen uses `$node->op_str()` to get the Perl operator for emission.

### Exception Model: Target Architecture

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

**Deferred:** Dual projections on Call nodes and full exception flow are a
separate design and implementation effort. This migration creates the
`Unwind` node type but does not wire exceptional edges. `TryCatch` remains
a typed computation node until the exception design lowers it to CFG
structure (Region + Unwind + Proj). See Dependencies section.

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

### BNF Constructor Nodes

`Constructor:Symbol`, `Constructor:Expression`, and `Constructor:Rule` are
BNF grammar-level nodes used by the BNF pipeline (`BNF::Target::Perl`,
`BNF::Target::XS`, `BNF::Target::C`). They are **excluded from this
migration**. The BNF pipeline is stable and small (4 creation sites, 6
type checks).

The correct disposition is metadata structs (grammar rules are metadata,
not computation), but that work is deferred to a separate ticket to avoid
risk to a working pipeline.

## Migration Strategy

### Approach: Adapter Shim with Gradual Migration

Constructor gains a backward-compatible shim. Consumers migrate
file-by-file from `->class()` string checks to `isa` type checks.

During migration, each new typed node provides a `->class()` method
returning its old Constructor class name. This keeps unmigrated consumers
working.

### Factory Shim

`Chalk::IR::Shim` translates old-style Constructor parameters to new
typed nodes. `Chalk::IR::NodeFactory` creates the typed nodes with hash
consing. The old singleton `Chalk::Bootstrap::IR::NodeFactory` has the
wiring to delegate to the Shim, but **activation is disabled** until
Phase 4 migrates `isa Constructor` checks.

**Why disabled:** ~100 sites across Actions.pm, Target/Perl.pm,
Target/C.pm, EmitHelpers.pm, and StructPromotion.pm check
`$node isa Chalk::Bootstrap::IR::Node::Constructor`. Translated nodes
(e.g., `Chalk::IR::Node::Add`) don't inherit from Constructor, so
these checks silently fail. The shim must be enabled incrementally as
each consumer file's `isa Constructor` checks are migrated in Phase 4.

**Translation API** (works when called directly):
```perl
use Chalk::IR::Shim;
my $typed = Chalk::IR::Shim::translate($factory, 'BinaryExpr',
    op => $op, left => $left, right => $right);
# Returns Chalk::IR::Node::Add with class() => 'BinaryExpr'
```

**Activation sequence** (Phase 4, per-file):
1. Migrate a consumer file's `isa Constructor` checks to `isa` typed nodes
2. Enable shim translation for the Constructor classes that file uses
3. Verify tests pass
4. Repeat for next file

The singleton goes away when all callers switch to the new API.

### Migration Phases

**Phase 1: Scaffold new types.**
Create `Chalk::IR::Node` base class and all typed subclasses with
intermediate base classes (BinOp, UnaryOp, Access, Aggregate, Regex).
Create `Chalk::IR::Graph`. Create metadata structs (Program, ClassInfo,
MethodInfo, FieldInfo, SubInfo) as plain `feature class` data containers.
Add corresponding node types to perl5-son.

**Phase 2: Factory shim (built but disabled).**
Create `Chalk::IR::Shim` translation module and wire it into the old
NodeFactory. The shim correctly translates 17 Constructor classes to
typed nodes, but activation is disabled behind `if (0)` because ~100
`isa Constructor` checks in consumers would break. BinOp/UnaryOp gain
named fields (left/right/operand) with ADJUST fallback for migration
layout compatibility. Node base gains `compat_class` field and `class()`
method for backward compat. Phase 4 enables the shim incrementally.

**Phase 3: Consumer migration + shim activation (file-by-file).**
This is the critical phase — it migrates `isa Constructor` checks to
typed `isa` checks and enables the factory shim incrementally. For each
consumer file:

1. Replace `$node isa Chalk::Bootstrap::IR::Node::Constructor` with
   typed checks (e.g., `$node isa Chalk::IR::Node::BinOp`)
2. Replace `$node->class() eq 'X'` with `$node isa Chalk::IR::Node::X`
3. Enable shim translation for the Constructor classes that file uses
4. Verify tests pass

Order by increasing risk:

1. ToSoN.pm — delete entirely (adapter no longer needed)
2. DCE.pm — few type checks
3. DepChaser.pm — few type checks
4. StructPromotion.pm — pattern matching on node types
5. BNF/Actions.pm — 4 Constructor uses (excluded from this migration,
   see BNF Constructor Nodes section)
6. EmitHelpers.pm — medium
7. Actions.pm — large, both creation sites and isa checks
8. Target/Perl.pm — large; includes restructuring entry points to walk
   metadata + per-method graphs
9. Target/C.pm — largest; same entry point restructuring

The shim's `if (0)` guard is replaced with a set of enabled classes
that grows as consumers are migrated.

**Phase 4: Structural split (metadata + per-method graphs).**
After consumers use typed nodes, change Actions.pm structural rules
(Program, ClassDecl, MethodDecl, FieldDecl, SubDecl, UseDecl) to emit
metadata structs with per-method `Chalk::IR::Graph` instead of
Constructor nodes. Restructure Phi insertion and scope tracking in
Program() for the new representation. **Atomic with codegen entry point
changes** — Actions.pm structural output and codegen structural
traversal must change together, verified against the 16 green eval files.

**Phase 5: Delete Constructor and old namespace.**
Remove `Chalk::Bootstrap::IR::Node::Constructor`, all
`Chalk::Bootstrap::IR::Node::*` classes, the singleton wrapper, and
`->class()` shim methods.

### Acceptance Criteria Per Phase

**Phase 1:** New node types have unit tests — `operation()`, `content_hash()`
determinism, intermediate base class accessors (`left()`, `right()`,
`operand()`, `op_str()`). Hash consing verified: identical inputs produce
same node object.

**Phase 2:** Shim translation works correctly when called directly (21
tests). Old factory shim wiring exists but is disabled — existing test
suite passes unchanged. Named fields and class() compat verified.

**Phase 3 (per-file):** Existing test suite passes after each file
migration. Shim enabled for migrated Constructor classes. No regressions
in the 16 green eval files.

**Phase 4 (structural split):** 16 green files still eval correctly.
Actions.pm emits metadata structs. Codegen walks metadata + per-method
graphs.

**Phase 5:** `grep -r 'Chalk::Bootstrap::IR::Node' lib/` returns zero hits
(excluding BNF pipeline). No `->class()` calls remain outside BNF.

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

(Counts are approximate — may shift as the codebase evolves.)

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

5. **StructRef / FieldAccess**: Optimizer-specific Constructor classes.
   Handle during Phase 4 when StructPromotion.pm is migrated.

## Dependencies

- **perl5-son convergence:** Add Unwind, dual Call projections, and
  Perl-specific node types. Can proceed in parallel with this migration.
- **Exception flow design:** Separate design doc for Unwind + dual
  projections on Call + TryCatch lowering to CFG. Depends on this
  migration completing first (typed nodes must exist before exception
  edges can be wired).
- **BNF Constructor migration:** Separate ticket to convert
  Constructor:Symbol/Expression/Rule to metadata structs.
- **Chalk Perl 5.42.0:** All new classes use `feature class`.
