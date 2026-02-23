# Sea of Nodes CFG for Bootstrap IR

## Problem

The Bootstrap IR represents control flow as tree-shaped Constructor nodes:
`IfStmt(condition, then_body[], else_body[])`, `ForeachLoop(iterator, list, body[])`.
These are AST nodes wearing a Sea of Nodes hat. They prevent optimization across
control flow boundaries, block type narrowing through branches, and diverge from
Cliff Click's design that the main Chalk IR already follows.

The Bootstrap compiler aims to replace the mainline Chalk compiler. Its IR must
support the same optimizations — dead branch elimination, loop-invariant hoisting,
constant propagation through Phi nodes — that a real Sea of Nodes enables.

## Design

### Approach: Scope-in-Focus with Scan-time Loop Sentinels

Enrich SemanticAction's focus value to carry a control token and lexical scope
alongside the IR node. Construct If/Region/Phi/Loop/Proj nodes during semantic
actions, replacing the tree-shaped Constructor classes. Use scan-time detection
of loop keywords to create eager Phi sentinels so loop bodies reference the
correct loop-carried values.

All changes live within the SemanticAction semiring. The Earley parser remains
generic.

### The Scope Model

SemanticAction's focus value grows from a bare IR node to a triple:

```perl
{
    value   => $ir_node,       # the rule's semantic result
    control => $control_node,  # current control-flow token (Start, If, Proj, Region, Loop)
    scope   => { '$x' => $node_for_x, ... },  # lexical variable bindings
}
```

**Scope is lexical.** Each rule's `on_complete` receives scope from its children
and produces a (possibly modified) scope in its output. The comonad's `extend`
threads these richer focus values through the Context tree.

**Control threads sequentially.** In a StatementList, statement 1's output
control becomes statement 2's input control. The comonad preserves child
ordering from the grammar, so `on_complete` composes these in source order.

**Initialization.** `one()` returns `{ value => undef, control => Start, scope => {} }`.

### Variables

**Declarations** (`my $x = 0`): VarDecl's `on_complete` adds `'$x' => Constant(0)`
to the scope. No VarDecl IR node — the `my` keyword is a scope operation, not
a data-flow node.

**References** (`$x` in an expression): ScalarVariable's `on_complete` looks up
`$x` in the scope and returns the IR node it maps to. If `$x` was assigned
`my $x = 0`, the reference returns `Constant(0)` directly.

**Assignments** (`$x = expr`): Updates the scope to `'$x' => rhs_node`. The
assignment's focus value is the rhs_node (for use in assignment-as-expression).

**Variables disappear from the IR.** They exist only in the scope during parsing.
The IR is pure data flow — nodes connected to nodes.

**Field access** (`$self->{name}`, `$obj->method`) remains as IR nodes
(SubscriptExpr, MethodCallExpr). Only lexical variables live in the scope.

### If/Else Construction

IfStatement `on_complete` receives child contexts for condition, then-block,
and optionally else-block. Each block's focus carries `{value, control, scope}`.

1. Extract the condition IR node from child context.
2. Create `If(incoming_control, condition)`.
3. Create `TrueProj(If, 0)` and `FalseProj(If, 1)`.
4. Create `Region(then_exit_control, else_exit_control)` to merge paths.
5. Compare the then-scope and else-scope against the pre-if scope:
   - Variable same in both → keep, no Phi.
   - Variable differs → `Phi(Region, then_value, else_value)`.
   - Modified only in then (no else block) → `Phi(Region, then_value, pre_if_value)`.
6. Output: `{ control => Region, scope => merged_with_phis, value => undef }`.

Elsif chains nest naturally: an elsif is an IfStatement in the else branch.
Unless inverts the condition (swap TrueProj/FalseProj or wrap in Not).

### Loops: Scan-time Sentinels

Loop construction spans three phases.

**Phase A — Scan-time setup.** SemanticAction's `on_scan` detects `while`,
`for`, or `foreach`. It:

1. Snapshots the current scope.
2. Creates a Loop node with entry control + null backedge.
3. Creates eager Phi sentinels for each variable in scope:
   `Phi(Loop, pre_loop_value, <null>)`.
4. Pushes sentinels into the scope, replacing pre-loop values.

The body parses with this modified scope. Variable references inside the body
resolve to Phi sentinels.

**Phase B — Body parsing.** Earley parses the body normally. `$x + 1` becomes
`Add(PhiSentinel($x), Constant(1))`. Assignments update the body's scope:
`$x → Add_result`.

**Phase C — WhileStatement on_complete.** Receives condition and body children.

1. Create `If(Loop_control, condition)` → TrueProj (body), FalseProj (exit).
2. For each Phi sentinel, compare pre-loop scope with body's output scope:
   - Variable modified → fill Phi's second input with body's output value.
     Wire body exit control as Loop backedge.
   - Variable unchanged → Phi has both inputs equal. Leave for the optimizer
     to collapse (`Phi(Loop, X, X) → X`).
3. Create `Region(FalseProj)` as loop exit.
4. Output: `{ control => Region, scope => cleaned_scope, value => undef }`.

**Foreach loops.** The iterator variable is new (introduced by the for keyword).
The list expression becomes the loop bound. Otherwise the same mechanism.

**Nested loops.** Inner `on_scan` snapshots a scope that already contains outer
Phi sentinels. Nesting works because each `on_scan` sees its enclosing context.

**`next` and `last`.** `next` creates a control edge to the Loop backedge.
`last` creates a control edge to the exit Region. Both become additional inputs
to their respective merge points.

### Why Scan-time Sentinels (Not Post-hoc Rewriting)

An alternative: parse the body with pre-loop values, then rewrite the body
subgraph to substitute Phi nodes for pre-loop references. This fails because
the body's IR would be wrong — `$x + 1` referencing `Constant(0)` instead of
`Phi($x)` produces incorrect results on iteration 2+.

Concrete trace of `my $x = 0; while ($x < 10) { $x = $x + 1; }`:
- Without sentinels: body builds `Add(Constant(0), Constant(1))` — always 1.
- With sentinels: body builds `Add(Phi($x), Constant(1))` — correct per-iteration.

Scan-time sentinels avoid rewriting. The coupling (SemanticAction knowing that
`while` triggers scope operations) mirrors how TypeInference uses `should_scan`
for keyword rejection. The semantic knowledge lives in the semiring, not the
parser.

### New IR Node Types

**New dedicated classes** in `lib/Chalk/Bootstrap/IR/Node/`:

| Node   | Inputs                        | Output          | Purpose                    |
|--------|-------------------------------|-----------------|----------------------------|
| If     | [control, condition]          | tuple (T, F)    | Conditional branch         |
| Region | [ctrl_1, ctrl_2, ...]         | merged control  | Control merge point        |
| Phi    | [region, val_1, val_2, ...]   | selected value  | Value selection at merge   |
| Loop   | [entry_ctrl, backedge_ctrl]   | loop control    | Loop header (special Region)|
| Proj   | [source]  attr: index         | single value    | Projection from tuple      |

**Constructor classes that survive** (data-flow nodes):
BinaryExpr, UnaryExpr, TernaryExpr, MethodCallExpr, BuiltinCall, SubscriptExpr,
PostfixDerefExpr, HashRefExpr, ArrayRefExpr, RegexMatch, RegexSubst,
InterpolatedString, ClassDecl, MethodDecl, FieldDecl, AnonSubExpr.

**Constructor classes removed:**
IfStmt, ForeachLoop, PostfixLoop, VarDecl, ReturnStmt, DieCall, NextUnless,
Program, StatementList. CompoundAssign desugars to BinaryExpr + scope update.

### XS Target: From Tree-Walk to Graph Scheduling

The XS target replaces tree-walking with graph scheduling.

**Scheduling.** Reverse-postorder walk from Return backward through use-def
chains. CFG nodes impose ordering; data-flow nodes emit within basic blocks.

**Structured reconstruction.** The IR was constructed from structured source, so
every If has a matching Region and every Loop has structured entry/exit. Pattern
matching reconstructs `if/else` and `while` from the graph primitives.

**Phi nodes in C.** Phi at an if-merge becomes a C variable declared before the
if, assigned in each branch. Phi at a loop header becomes the loop variable.

```c
// If/else Phi:
SV *x;
if (SvTRUE(cond)) { x = val_a; }
else               { x = val_b; }

// Loop Phi:
SV *x = entry_val;
while (SvTRUE(cond)) { x = body_val; }
```

**Methods removed from XS target:** `_emit_xs_if_stmt`, `_emit_xs_foreach_loop`,
`_emit_xs_postfix_loop`, `_emit_xs_var_decl`, `_collect_var_decls`,
`_has_early_return`, `_body_contains_return`.

### Migration Strategy

Each phase keeps all existing tests passing.

**Phase 0 — Scope threading.** Add scope to SemanticAction focus values. VarDecl
populates scope, variable references look up from scope. Output IR unchanged.
New tests verify scope correctness. Zero existing test breakage.

**Phase 1 — New CFG node types.** Implement If, Region, Phi, Loop, Proj as node
classes. Add NodeFactory support. Unit tests for construction and hash-consing.
Pure addition.

**Phase 2 — If/else migration.** IfStatement `on_complete` produces
If/Proj/Region/Phi instead of IfStmt Constructor. Update XS and Perl targets.
Verify full pipeline tests (concise-actions, concise-validation, perl-actions-*).

**Phase 3 — Loop migration.** Add scan-time sentinels to `on_scan`. Loop
`on_complete` produces Loop/Phi/If/Proj. Update both targets. Full pipeline
verification.

**Phase 4 — Cleanup.** Remove dead Constructor classes and tree-walk methods.
Remove stale-value workarounds if the scope model makes them unnecessary.

**Phase 5 — Optimizer foundation.** Peephole optimizations:
- `Phi(Region, X, X) → X` — redundant Phi elimination (critical for sentinel cleanup)
- `If(constant) → collapse` to live branch
- `Region(single_input) → collapse`

These should improve B::Concise oracle matching since perl's optimizer performs
the same transformations.

## References

- Click, "A Simple Graph-Based Intermediate Representation" (1995)
  https://www.oracle.com/technetwork/java/javase/tech/c2-ir95-150110.pdf
- Simple compiler, Sea of Nodes pedagogical implementation
  https://github.com/SeaOfNodes/Simple
- Chapter 5 (If/Region/Phi), Chapter 7 (Loops/eager Phi), Chapter 8 (lazy Phi)
- Main Chalk IR: `lib/Chalk/IR/Node/{If,Region,Phi,Loop}.pm`
- Bootstrap IR: `lib/Chalk/Bootstrap/IR/Node/`, `lib/Chalk/Bootstrap/IR/NodeFactory.pm`
- SemanticAction: `lib/Chalk/Bootstrap/Semiring/SemanticAction.pm`
- Actions: `lib/Chalk/Bootstrap/Perl/Actions.pm`
- XS Target: `lib/Chalk/Bootstrap/Perl/Target/XS.pm`
