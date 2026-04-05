# Phase 4: SSA Scope + Structural Split

## Problem

Actions.pm produces a single Constructor tree mixing program structure
(Program, ClassDecl, MethodDecl, FieldDecl, UseDecl) with computation
(BinaryExpr→Add, Call, VarDecl, etc.). Codegen walks this tree top-down.
Phi insertion happens as a post-hoc pass in Program() that walks the full
statement list after parsing completes.

This design has three problems:
1. Structural nodes don't belong in SoN — Click's model puts structure
   in metadata, not the graph
2. Phi insertion in Program() is fragile — it only handles loops, misses
   if/else merges, and can't work with per-method graphs
3. Variable reassignments (`$x = expr`) don't update the scope — only
   `my` declarations do. This means the IR doesn't track SSA versions
   for reassigned variables.

## Goal

**Phase 4a (SSA Scope):**
1. Assign nodes update the scope (new SSA value per reassignment)
2. IfStatement forks scope per-branch and merges eagerly at Region
   completion with Phis for variables that differ between branches
3. Loop Phis continue via the existing sentinel mechanism
4. Trivial Phi removal inline
5. Remove post-hoc Phi pass from Program()

**Phase 4b (Structural Split):**
1. Actions.am emits metadata structs incrementally, one structural type
   at a time: UseDecl → FieldDecl → MethodDecl → SubDecl → ClassDecl → Program
2. Each method/sub body becomes a self-contained `Chalk::IR::Graph`
   with a schedule (control flow context per node)
3. ReturnStmt → Return CFG node, DieCall → Unwind CFG node
4. Codegen accepts both old and new formats during transition
5. TernaryExpr stays as computation node (lowered in a future pass)

## Phase 4a: SSA Scope

### Current State

`Chalk::Bootstrap::Scope` is an immutable name→value map. Only VarDecl
(my/our/state declarations) updates the scope. Variable reassignment
(`$x = expr`) produces an Assign node but does not update the scope.

Phi insertion is a post-hoc pass in `Program()` that only handles loops
via `$_loop_body_var_refs`. If/else branches don't produce Phis.

The scope already has `fork_for_loop()` and `resolve_sentinel()` for
lazy loop Phi creation, but these are only used in tests.

### Hybrid Phi Strategy (Click + Sentinel)

Earley's left-to-right completion order means that by the time
IfStatement completes, both branches' scope effects are available.
This enables eager Phi creation at if/else merge points (Click-style).

Loops are different — the loop body is parsed before the backedge is
known. The existing sentinel mechanism handles this (lazy Phi creation).

**If/else Phis (eager, Click-style):**
1. IfStatement's semantic action reads per-branch scopes from child
   Contexts via `inherited_cfg_state`
2. Diffs the two branch scopes against the pre-if scope
3. For variables that differ, creates Phi at the Region node
4. Post-if scope maps those variables to the Phi nodes

**Loop Phis (lazy, sentinel-based):**
1. At loop entry, `fork_for_loop()` replaces bindings with sentinels
2. When a variable is read inside the loop, `resolve_sentinel()` creates
   a Phi on demand
3. At loop exit, backedge values are wired into the Phis

**Trivial Phi removal:**
```
remove_trivial_phi($phi):
  $same = undef
  for each operand:
    skip if operand is $phi itself (self-reference)
    skip if operand is undef (unfilled backedge)
    if !defined $same: $same = operand
    elsif $same != operand: return $phi  # non-trivial
  replace all uses of $phi with $same
  return $same
```

### Scope Changes

1. **Assign updates scope:** The `AssignmentExpression` semantic action
   calls `$update_scope->($var_name, $assign_node)` for plain
   assignments, not just VarDecl.

2. **IfStatement merges scopes:** After creating the Region, IfStatement
   reads the then-branch and else-branch final scopes, diffs them
   against the pre-if scope, and creates Phis for differing variables.

3. **Remove Program() Phi pass:** The `$_loop_body_var_refs` side table
   and the loop-walking Phi insertion logic in `Program()` are deleted.
   Phi insertion happens during parsing via the hybrid mechanism.

### Testing

- Variables assigned in if-branch get Phis at the merge point
- Variables unchanged across branches don't get Phis (trivial removal)
- Loop-carried variables get Phis at the loop header (sentinel mechanism)
- Variables only read in loops don't get Phis (sentinel resolves to same value)
- Nested if/else and loops produce correct Phis
- The 16 green eval files still produce correct codegen output

## Phase 4b: Structural Split (Incremental)

### Migration Order

One structural type at a time, simplest first:

1. **UseDecl** → `Chalk::IR::UseInfo` (new class: name, args)
2. **_Attribute** → plain hashref `{name => $str}`
3. **FieldDecl** → `Chalk::IR::FieldInfo`
4. **MethodDecl** → `Chalk::IR::MethodInfo` with `Chalk::IR::Graph`
5. **SubDecl** → `Chalk::IR::SubInfo` with `Chalk::IR::Graph`
6. **ClassDecl** → `Chalk::IR::ClassInfo`
7. **Program** → `Chalk::IR::Program`

Each step: change the semantic action, update codegen to accept both
formats, verify 16 green files.

### ReturnStmt → Return, DieCall → Unwind

When MethodDecl/SubDecl build per-method graphs (step 4-5):

- `ReturnStmt(value)` becomes `Return(control, value)` — a CFG node
  created via `make_cfg('Return', ...)`. The graph's `returns` field
  collects all Return nodes.
- `DieCall(args)` becomes `Unwind(control, exception_value)` — a CFG
  node. The graph's `returns` field collects Unwind nodes too (they're
  both graph exits).
- Dual projections on Call (normal + exceptional edge) remain deferred.

### Per-Method Graph Construction

MethodDecl action builds the graph:

```perl
my $start = $factory->make_cfg('Start');
# ... body parsing with scope produces computation nodes ...
# ... ReturnStmt actions produce Return CFG nodes ...
my $graph = Chalk::IR::Graph->new(
    start    => $start,
    returns  => \@return_nodes,
    schedule => $method_schedule,  # extracted from cfg_state
);
Chalk::IR::MethodInfo->new(
    name   => $name_str,      # plain string, not Constant node
    params => \@param_strs,   # plain strings
    graph  => $graph,
);
```

### Schedule

The schedule maps node IDs to their control flow context — the per-method
extract of the current global `cfg_state` side table.

```perl
field $schedule :param :reader = {};
# Keys: node ID strings
# Values: { region => $node, if_node => ..., loop => ..., etc. }
```

During parsing, semantic actions already build cfg_state entries. The
MethodDecl action collects entries for its body's nodes and packages
them as the graph's schedule.

Future: a Click-style scheduler derives the schedule from graph structure,
replacing the parse-time schedule. The Graph interface stays the same.

### New Type: Chalk::IR::UseInfo

```perl
class Chalk::IR::UseInfo {
    field $name :param :reader;
    field $args :param :reader = [];
}
```

### Codegen Restructuring

Codegen accepts both old Constructor and new metadata during transition.
For each structural type migrated:

```perl
# UseDecl example:
method _emit_use($node_or_info) {
    if ($node_or_info isa Chalk::IR::UseInfo) {
        # New path: plain accessors
        my $name = $node_or_info->name();
        my $args = $node_or_info->args();
    } else {
        # Old path: Constructor node
        my $name = $node_or_info->inputs()->[0]->value();
        my $args = $node_or_info->inputs()->[1];
    }
    # ... rest of emission unchanged
}
```

Old path removed when all structural types are migrated.

For method body emission:

```perl
method _emit_method_info($method_info) {
    my $sig = '(' . join(', ', $method_info->params()->@*) . ')';
    my $graph = $method_info->graph();
    return $self->_emit_body_from_graph(
        "method " . $method_info->name() . "$sig {", $graph);
}

method _emit_body_from_graph($decl, $graph) {
    my $schedule = $graph->schedule();
    # Walk schedule entries, emit nodes via existing _emit_node/_emit_expr
}
```

Both Target/Perl.pm and Target/C.pm need this. Shared methods can live
in EmitHelpers.

### What Gets Deleted (after all structural types migrated)

- Constructor:Program, ClassDecl, MethodDecl, SubDecl, FieldDecl, UseDecl,
  _Attribute, ReturnStmt, DieCall entries from NodeFactory %INPUT_SPECS
- The `$_loop_body_var_refs` side table in Actions.pm (Phase 4a)
- The Phi insertion logic in Program() (Phase 4a)
- Old-path codegen branches for structural types (Phase 4b)

## Ordering

1. **Phase 4a** — SSA scope (independently testable)
2. **Phase 4b step 1-3** — UseDecl, _Attribute, FieldDecl (no graph needed)
3. **Phase 4b step 4-5** — MethodDecl, SubDecl (graph construction + Return/Unwind)
4. **Phase 4b step 6-7** — ClassDecl, Program (collecting metadata)

Phase 4a can land independently. Phase 4b steps are incremental and
independently verifiable.

## Risks

1. **Scope change + Earley ambiguity:** Earley explores multiple parse
   paths. Each alternative carries its own Context/scope. Scope merging
   in `multiply()` must not create spurious Phis from Earley ambiguity
   (as opposed to genuine if/else control flow merges). Phis should only
   be created in IfStatement's semantic action, not in multiply().

2. **cfg_state extraction per-method:** The global cfg_state keyed by
   Context refaddr must be partitioned to extract per-method schedules.
   Entries for nodes in method A must not leak into method B's schedule.

3. **Return/Unwind inside nested control flow:** A `return` inside an
   if-branch inside a loop must produce a Return CFG node at the right
   control point. The control token threading should handle this, but
   needs careful testing.

## Dependencies

- Phase 1-3 complete (typed nodes flowing, shim active)
- `Chalk::IR::Graph` exists with `schedule` field (Phase 1, extended)
- Metadata structs exist (Phase 1): Program, ClassInfo, MethodInfo,
  SubInfo, FieldInfo
- New: `Chalk::IR::UseInfo` (created in Phase 4b step 1)
