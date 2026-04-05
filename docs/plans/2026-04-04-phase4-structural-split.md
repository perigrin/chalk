# Phase 4: Structural Split + Braun-Style SSA

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
3. The single-tree output couples parser to codegen format

## Goal

1. Actions.pm emits metadata structs (Program, ClassInfo, MethodInfo,
   FieldInfo, SubInfo, UseInfo) directly during parsing
2. Each method/sub body becomes a self-contained `Chalk::IR::Graph`
   with a schedule (control flow context for each node)
3. Phi nodes are created lazily during parsing via Braun et al.'s
   algorithm adapted for Sea of Nodes, eliminating the post-hoc pass
4. Codegen walks metadata for program structure, reads per-method
   graphs for method body emission

## Part A: Braun-Style Scope

### Current State

`Chalk::Bootstrap::Scope` is a name→value immutable map. Variable
definitions and lookups are simple:

```perl
$scope = $scope->define('$x', $node);
my $val = $scope->lookup('$x');
```

Phi insertion happens after the fact in `Program()`:
- Walk statements looking for Loop nodes
- For each loop, check which variables were defined before the loop
- Create Phi nodes connecting pre-loop value to loop-body value

This only handles loops. Variables that differ across if/else branches
don't get Phis — they rely on the Earley parser's merge semantics.

### Target State

Scope becomes region-aware. Each scope knows which control flow Region
(or Loop) it belongs to. Variable reads at merge points create Phis
lazily.

```perl
# Write: variable defined at current region
$scope->write_variable($name, $value);

# Read: may create Phi at current region if values differ
my $val = $scope->read_variable($name);
```

### Braun Algorithm (SoN adaptation)

```
read_variable($name, $region):
  if $region has local definition for $name:
    return it
  if $region has single control predecessor:
    return read_variable($name, predecessor_region)
  # Merge point: region has multiple control inputs
  create Phi at $region
  record Phi (break cycles for loops)
  for each control input of $region:
    add Phi operand: read_variable($name, input's region)
  return remove_trivial_phi(Phi)

remove_trivial_phi($phi):
  $same = undef
  for each operand:
    skip if operand is $phi itself (self-reference)
    skip if operand is undef (unfilled backedge)
    if !defined $same: $same = operand
    elsif $same != operand: return $phi  # non-trivial
  # All operands are the same value
  replace all uses of $phi with $same
  return $same
```

In SoN terms:
- "Block" → Region or Loop node
- "Predecessor" → control input of the Region/Loop
- "Local definition" → write_variable recorded at this region

### Scope Class Changes

`Chalk::Bootstrap::Scope` gains:
- `field $region` — the current control flow Region/Loop node
- `method read_variable($name)` — Braun lookup with lazy Phi
- `method write_variable($name, $value)` — record definition at current region
- `method with_region($new_region)` — create child scope at a new region

The existing `define()` and `lookup()` methods are replaced by
`write_variable()` and `read_variable()`.

### Program() Simplification

Current Program() (~80 lines) does:
1. Collect statements
2. Fix postfix chains
3. Phi insertion for loops (the bulk of the code)
4. Wrap in Constructor:Program

After Braun, Program() does:
1. Collect metadata items (UseInfo, ClassInfo, SubInfo)
2. Wrap in Chalk::IR::Program
3. No Phi pass needed

## Part B: Per-Method Graph Construction

### MethodDecl Action

Currently produces:
```perl
$factory->make('Constructor',
    class       => 'MethodDecl',
    name        => $name_node,
    params      => $params,
    body        => $body_nodes,
    return_type => $return_type,
);
```

After Phase 4:
```perl
my $graph = Chalk::IR::Graph->new(
    start    => $start_node,
    returns  => \@return_nodes,
    schedule => $method_schedule,
);
Chalk::IR::MethodInfo->new(
    name        => $name_str,         # plain string, not Constant node
    params      => \@param_strs,      # plain strings
    return_type => $return_type_str,
    graph       => $graph,
);
```

### Schedule

The schedule maps node IDs to their control flow context. It's the
per-method extract of the current global `cfg_state` side table.

```perl
# In Chalk::IR::Graph
field $schedule :param :reader = {};
# Keys: node ID strings
# Values: { region => $region_node, if_node => ..., loop => ..., etc. }
```

During parsing, semantic actions already build cfg_state entries. The
MethodDecl action collects the cfg_state entries for nodes in its body
and packages them as the graph's schedule.

Future: a Click-style scheduler derives the schedule from graph structure,
replacing the parse-time schedule. The Graph interface stays the same.

### SubDecl Action

Same as MethodDecl but produces `Chalk::IR::SubInfo` with a `scope`
field ('my', 'our', 'package').

## Part C: Structural Metadata Emission

### New Type: Chalk::IR::UseInfo

```perl
class Chalk::IR::UseInfo {
    field $name :param :reader;
    field $args :param :reader = [];
}
```

### Actions.pm Changes

| Semantic Action | Old Output | New Output |
|---|---|---|
| UseDecl | Constructor:UseDecl | Chalk::IR::UseInfo |
| FieldDecl | Constructor:FieldDecl | Chalk::IR::FieldInfo |
| MethodDecl | Constructor:MethodDecl | Chalk::IR::MethodInfo |
| SubDecl | Constructor:SubDecl | Chalk::IR::SubInfo |
| ClassDecl | Constructor:ClassDecl | Chalk::IR::ClassInfo |
| Program | Constructor:Program | Chalk::IR::Program |
| _Attribute | Constructor:_Attribute | plain hashref {name => $str} |

### What Gets Deleted

- Constructor:Program, ClassDecl, MethodDecl, SubDecl, FieldDecl, UseDecl,
  _Attribute entries from NodeFactory's %INPUT_SPECS
- The Phi insertion logic in Program()
- The `$_loop_body_var_refs` side table in Actions.pm

## Part D: Codegen Restructuring

### Entry Points

```perl
# Target/Perl.pm
method generate($program) {
    # $program is Chalk::IR::Program
    return $self->_emit_program($program);
}

method generate_with_cfg($program, $sa, $ctx) {
    $self->_build_cfg_lookup($sa, $ctx);
    return $self->_emit_program($program);
}
```

### New _emit Methods for Metadata

```perl
method _emit_program($program) {
    my @lines;
    push @lines, $self->_emit_use_info($_) for $program->use_decls()->@*;
    push @lines, $self->_emit_class_info($_) for $program->classes()->@*;
    push @lines, $self->_emit_sub_info($_) for $program->top_level_subs()->@*;
    return join("\n", @lines) . "\n";
}

method _emit_class_info($class_info) {
    my $decl = "class " . $class_info->name();
    $decl .= " :isa(" . $class_info->parent() . ")" if defined $class_info->parent();
    $decl .= " {";
    my @lines = ($decl);
    push @lines, "    " . $self->_emit_field_info($_) for $class_info->fields()->@*;
    push @lines, map { "    $_" } split(/\n/, $self->_emit_method_info($_))
        for $class_info->methods()->@*;
    push @lines, map { "    $_" } split(/\n/, $self->_emit_sub_info($_))
        for $class_info->subs()->@*;
    push @lines, "}";
    return join("\n", @lines);
}

method _emit_method_info($method_info) {
    my $sig = '(' . join(', ', $method_info->params()->@*) . ')';
    my $graph = $method_info->graph();
    return $self->_emit_body_from_graph(
        "method " . $method_info->name() . "$sig {", $graph);
}
```

### _emit_body_from_graph

Reads the graph's schedule to emit the method body. Uses the same
`_emit_node` / `_emit_expr` dispatch as today for computation nodes.
The schedule tells it which nodes go inside if-branches, loop bodies, etc.

### Target/C.pm

Same restructuring as Target/Perl.pm. Both inherit from EmitHelpers,
so shared metadata emission methods can live there.

## Ordering

1. **Part A first** — Braun scope is independently testable
2. **Part B next** — per-method graphs need Braun scope
3. **Parts C + D atomic** — Actions.pm output and codegen input change together
4. Verify: 16 green files, all IR tests, no regressions

## Risks

1. **Braun scope + Earley parser interaction**: The Earley parser explores
   multiple parse paths simultaneously. The scope must handle ambiguity
   correctly — each parse alternative carries its own scope state via the
   comonad Context. Braun's algorithm assumes a single forward pass, but
   the Context threading should provide the right scope at each point.

2. **cfg_state extraction**: The current cfg_state is built by walking
   the Context tree after parsing. Extracting per-method schedules
   requires partitioning cfg_state entries by which method they belong to.

3. **Atomic C+D**: Changing Actions.pm output and codegen input
   simultaneously is high-risk. Mitigation: comprehensive tests on the
   16 green files before and after.

## Dependencies

- Phase 1-3 complete (typed nodes flowing, shim active)
- `Chalk::IR::Graph` exists (Phase 1)
- Metadata structs exist (Phase 1): Program, ClassInfo, MethodInfo,
  SubInfo, FieldInfo
- New: `Chalk::IR::UseInfo` (created in this phase)
