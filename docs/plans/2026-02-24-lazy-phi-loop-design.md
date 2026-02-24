# Lazy Phi Creation for Loop-Carried Dependencies

## Problem

The bootstrap IR builds CFG nodes (If, Loop, Proj, Region) at parse time, but
variables inside loops lack SSA form. A loop that modifies `$x` produces no Phi
node at the loop header. Without Phis, optimization passes (GCM, DCE) cannot
see loop-carried dependencies, and codegen must guess variable bindings by
position rather than following data-flow edges.

The if/else path already creates Region nodes where branches merge, but neither
if nor loops create Phi nodes for variables that differ across branches or
iterations.

## Design

Adopt Click's lazy Phi pattern (Simple compiler, Chapter 8). At loop entry,
replace every scope binding with a sentinel. When an action method reads a
variable inside the loop body, the sentinel triggers Phi creation on demand.
Variables never referenced in the body get no Phi.

Extend the same mechanism to assignments: when `$x = expr` executes, the scope
updates to point `$x` at the new IR node. This makes the scope the single
source of truth for variable bindings throughout the parse.

### Four Components

1. **Scope sentinels** — fork the scope at loop entry
2. **Lazy Phi creation** — variable reads resolve sentinels into Phis
3. **Assignment scope updates** — variable writes update the scope
4. **Backedge wiring** — close the loop after body parsing

## Component 1: Scope Sentinels

`Chalk::Bootstrap::Scope` gains three methods:

**`fork_for_loop($loop_node)`** returns a new Scope where every binding is
replaced with a sentinel hashref:

```perl
{ sentinel => 1, loop => $loop_node, pre_value => $original_binding }
```

**`resolve_sentinel($name, $factory)`** checks whether the binding for `$name`
is a sentinel. If so, it creates a Phi node, replaces the sentinel with the
Phi in a new Scope, and returns both:

```perl
my ($value, $new_scope) = $scope->resolve_sentinel('$x', $factory);
# $value    = the Phi node (or existing binding if not a sentinel)
# $new_scope = updated Scope (or undef if no sentinel was resolved)
```

The Phi is created with `Phi(loop, [pre_value, undef])`. The second input
(backedge) is filled in after the body is parsed.

**`raw_lookup($name)`** returns the binding without resolving sentinels. Used
during backedge wiring to distinguish sentinels from Phis.

## Component 2: Lazy Phi Creation in Variable Actions

`ScalarVariable`, `ArrayVariable`, and `HashVariable` in `Actions.pm` currently
return a Constant node with `const_type => 'variable'`. They change to consult
the scope first:

```perl
method ScalarVariable($ctx) {
    my $text = $ctx->scanned_text();
    $text =~ s/^\s+|\s+$//g;

    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
    if (defined $sa) {
        my $state = $sa->inherited_cfg_state($ctx);
        if (defined $state) {
            my ($value, $new_scope) = $state->{scope}->resolve_sentinel($text, $factory);
            if (defined $value) {
                if ($new_scope) {
                    $sa->update_cfg({ %$state, scope => $new_scope });
                }
                return $value;
            }
        }
    }

    # Fallback: variable not in scope (field access, global, $self)
    return $factory->make('Constant', const_type => 'variable', value => $text);
}
```

Variables not in scope fall through to the existing Constant behavior. Only
scope-tracked locals get Phi treatment.

## Component 3: Assignment Scope Updates

`AssignmentExpression` in `Actions.pm` creates Constructor nodes for assignments
but does not update the scope. It changes to:

1. After building the assignment IR node, check if the target is a variable
   name present in scope.
2. If so, call `scope.define($name, $rhs_node)` to update the binding.
3. Call `update_cfg` with the new scope.

This makes `$x = $x + 1` inside a loop produce:

1. Reading `$x` on the RHS hits the sentinel, creating `Phi(loop, [pre_value, undef])`
2. `BinaryExpr(+, Phi, Constant(1))` is the RHS value
3. Assignment updates scope: `$x => BinaryExpr(+, Phi, Constant(1))`

The scope now tracks the "current version" of each variable through the
parse, matching SSA semantics.

## Component 4: Backedge Wiring

After `ForeachStatement` or `PostfixModifier` finishes parsing the loop body:

1. Read the post-body scope from the body's final cfg_state.
2. For each variable that has a Phi (created by sentinel resolution), set the
   Phi's backedge input to the post-body value of that variable.
3. Wire the Loop node's `backedge_ctrl` to the body's exit control.
4. Discard unresolved sentinels (restore pre-loop values for variables never
   read in the body).

**Three cases for a variable `$x` in a loop:**

| Case | Sentinel resolved? | Post-body value | Backedge input |
|------|-------------------|-----------------|----------------|
| Never read | No | Sentinel (discarded) | N/A — no Phi |
| Read, not written | Yes → Phi | Phi itself | Phi (degenerate, optimizer removes) |
| Read and written | Yes → Phi | New value (e.g. BinaryExpr) | New value (real dependency) |

**Phi and Loop mutation**: Backedge inputs cannot exist at construction time
(the backedge doesn't exist yet). Both Phi and Loop nodes accept `undef` for
their backedge fields at construction, then receive the real value via
`set_backedge` / `set_backedge_ctrl`. These are the only mutation points in
the IR.

## Nested Loops

The mechanism handles nesting naturally. When an inner loop calls
`fork_for_loop`, the outer loop's scope may already contain Phis (from the
outer loop's sentinel resolution). The inner loop creates sentinels wrapping
those Phis. Reading a variable in the inner body resolves the inner sentinel,
creating a new Phi for the inner loop whose `pre_value` is the outer Phi.

## Files to Modify

| File | Change |
|------|--------|
| `lib/Chalk/Bootstrap/Scope.pm` | Add `fork_for_loop`, `resolve_sentinel`, `raw_lookup` |
| `lib/Chalk/Bootstrap/IR/Node/Phi.pm` | Add `set_backedge($value)` method |
| `lib/Chalk/Bootstrap/IR/Node/Loop.pm` | Add or verify `set_backedge_ctrl($ctrl)` |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | Variable actions: scope lookup before Constant fallback |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | AssignmentExpression: `scope.define()` after assignment |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | ForeachStatement: `fork_for_loop` + backedge wiring |
| `lib/Chalk/Bootstrap/Perl/Actions.pm` | PostfixModifier: same for while/until/for postfix loops |
| `t/bootstrap/cfg-loop-phi.t` | New test file for lazy Phi creation |
| `t/bootstrap/scope.t` | Tests for sentinel, resolve, fork_for_loop |

## What This Does Not Include

- **Codegen changes**: Targets already have `emit_cfg_phi_if`. A loop
  equivalent (`emit_cfg_phi_loop`) is a follow-on step.
- **GCM / DCE passes**: Phi nodes enable these but implementing optimization
  passes is separate work (Phase 9 in the roadmap).
- **If/else Phi creation**: IfStatement already creates Region nodes. Adding
  Phi creation at if/else merge points uses the same `scope.diff()` +
  `scope.snapshot()` infrastructure that exists today. This is a natural
  follow-on but not part of this design.
- **Removing VarDecl Constructors**: Variable actions still produce VarDecl
  Constructors alongside scope updates. Removing VarDecl from the IR is a
  future cleanup once codegen reads from scope-derived Phis instead.

## Success Criteria

1. `for my $i (1..10) { $i }` produces a Loop node with a Phi at the header
   for `$i`, with `pre_value = iterator` and `backedge = Phi` (degenerate,
   read-only).
2. `my $sum = 0; for my $x (@list) { $sum = $sum + $x }` produces a Phi for
   `$sum` with `pre_value = Constant(0)` and `backedge = BinaryExpr(+, Phi, $x)`.
3. Variables not referenced inside the loop body get no Phi.
4. Nested loops produce nested Phis (inner Phi wraps outer Phi).
5. All existing tests pass — the fallback to Constant for unscoped variables
   preserves backward compatibility.
