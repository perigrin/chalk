# Phase 7c-prep Design — MOP::Class gains class-body shape

**Date:** 2026-05-25
**Status:** Design approved, ready for implementation plan.
**Branch:** `fixup-audit-baseline` (will commit on this branch).
**Predecessor:** `docs/plans/2026-05-24-phase-7c-blocker.md`
**Successor:** Phase 7c-proper (Target::C consumes new MOP entities).

## Purpose

Phase 7c per the audit (`docs/plans/2026-05-24-target-c-migration-audit.md`
§9) called for migrating Target::C's `_analyze_class` and its helpers
off `Chalk::IR::ClassInfo` and onto `Chalk::MOP::Class`. The 7c blocker
doc identified that Chalk::MOP::Class lacks entity lists for class-scope
`my $x = ...;` declarations and `use constant { ... };` declarations
— so Target::C cannot stop iterating the legacy body arrayref without
something to iterate on the MOP side first.

This prep commit expands MOP::Class so 7c-proper has a real target.
It does NOT touch Target::C.

## Framing: a class body is a graph

A method body is a Sea-of-Nodes graph in MOP::Method: VarDecl nodes
pinned to a control chain, a Scope tracking variable bindings, a
NodeFactory for hash-consed construction. Method codegen walks the
graph or its schedule to emit code.

A class body has the same structure. `my $ZERO = []; use constant
FOO => 42; field $x; method bar { ... }` is a sequence of side-effect-
shaped statements pinned to a control chain. The class-scope
`Scope` is the lexical environment that method bodies close over.
Class-scope VarDecls and use-constants are bindings in that Scope;
field/method/sub declarations are values bound into it.

MOP::Class should expose this graph the same way MOP::Method does.

This prep commit puts the SSA scaffolding in place (graph, scope,
factory fields) AND ships the two typed entity lists that 7c-proper
actually consumes. The graph/scope fields stay populated but
under-used until later optimization passes need them.

## What ships

### MOP::Class new fields (parallel to MOP::Method)

- `field $graph   :param :reader = Chalk::IR::Graph->new;`
- `field $factory :param :reader = Chalk::IR::NodeFactory->new;`
- `field $scope   :param :reader = Chalk::Bootstrap::Scope->new;`

These default-construct on every MOP::Class instance — consistent
with MOP::Method's unconditional default-construction. Empty classes
pay the same allocation cost methods already pay.

### MOP::Class new typed entity lists

- `field @class_scope_vars;` — VarDecl IR nodes from class body
  `my $x = ...;` declarations.
- `field @use_constants;` — hashref entities `{name => 'FOO', value
  => $const_ir_node}` for `use constant { K => V };` declarations.

Accessor methods follow MOP::Class convention: `class_scope_vars()`
and `use_constants()` return lists (not arrayrefs) so callers can
`scalar @list`.

### MOP::Class new declare_* methods

```perl
method declare_class_scope_var($vardecl_node) {
    # $vardecl_node is a Chalk::IR::Node::VarDecl already constructed
    # by Actions.pm. Merge into $graph (for future SSA passes), record
    # in @class_scope_vars (for codegen iteration), and add the
    # binding to $scope.
    $graph->merge($vardecl_node);
    push @class_scope_vars, $vardecl_node;
    my $name = $vardecl_node->name->value;
    $scope = $scope->define($name, $vardecl_node);
    return $vardecl_node;
}

method declare_use_constant($name, $value_node) {
    # $name is the constant name (string, no sigil).
    # $value_node is a Chalk::IR::Node::Constant (or similar IR node).
    my $entry = { name => $name, value => $value_node };
    push @use_constants, $entry;
    return $entry;
}
```

Both methods return the registered entity, matching the pattern of
`declare_field` / `declare_method` / `declare_sub`.

### Actions.pm population

In the ClassBlock action (lib/Chalk/Bootstrap/Perl/Actions.pm around
line 670), the body-item loop gains two more branches:

```perl
} elsif ($item isa Chalk::IR::Node::VarDecl) {
    $mop_class->declare_class_scope_var($item);
} elsif ($item isa Chalk::IR::UseInfo
        && $item->name eq 'constant') {
    # use constant { K => V, ... }
    # Extract the hash literal from args[0], walk its pairs,
    # call declare_use_constant once per pair.
    my $args = $item->args;
    if (ref($args) eq 'ARRAY' && @$args) {
        my $hash = $args->[0];
        if (defined $hash && $hash isa Chalk::IR::Node::HashRef) {
            my $pairs = $hash->inputs->[0];
            if (ref($pairs) eq 'ARRAY') {
                for (my $i = 0; $i < @$pairs; $i += 2) {
                    my $key_node = $pairs->[$i];
                    my $val_node = $pairs->[$i + 1];
                    next unless $key_node isa Chalk::IR::Node::Constant;
                    next unless $val_node isa Chalk::IR::Node::Constant;
                    $mop_class->declare_use_constant(
                        $key_node->value, $val_node);
                }
            }
        }
    }
    # Do NOT also declare_import — `use constant` is not a
    # module import; routing it through declare_import was a prior
    # conflation. (See Target::C's `_analyze_class` which had to
    # walk the body again to recover the distinction.)
} elsif ($item isa Chalk::IR::UseInfo) {
    $mop_class->declare_import($item->name(),
        args => [$item->args->@*],
    );
}
```

Note the existing `UseInfo` → `declare_import` branch becomes the
else-arm of the `use constant` check, so non-constant `use` decls
keep their current routing.

### What this commit explicitly does NOT do

- **Does not touch Target::C.** All of `_analyze_class`,
  `_build_field_index_map`, `_scan_class_methods`,
  `_class_scope_vars`, `_use_constants` keep their current ClassInfo
  body-arrayref iteration. 7c-proper is the commit that migrates
  Target::C; it depends on this commit but is a separate effort.
- **Does not wire method scope ← class scope.** Methods compiled
  inside the class continue to get a fresh Scope at method-body
  entry. Lexical capture of class-scope vars by method bodies stays
  a Target::C-side concern (via `_class_scope_vars` hash) for now.
  Wiring lexical capture is a separate decision with its own tests
  and its own risk; deferred to a later commit.
- **Does not migrate Target::Perl.** Target::Perl already consumes
  MOP through `_generate_from_schedule` and does not iterate class-
  body arrayrefs for class-scope statements (it processes
  fields/methods/subs and treats other body items as legacy
  ClassInfo state). If Target::Perl ever needs class-scope vars or
  use-constants, this commit's MOP additions make that read-only
  consumption available; no Target::Perl change required now.

## Test plan

### Unit tests (new files)

**`t/bootstrap/mop/class-scope-vars.t`** — MOP-level structural tests:

- An empty `Chalk::MOP::Class` has zero `class_scope_vars` and an
  empty `$scope` (defined, but `lookup` returns undef for any key).
- After `declare_class_scope_var(make_vardecl('$x', $init))`:
  - `class_scope_vars` returns a one-element list.
  - The element is the same VarDecl node passed in (identity test).
  - `$graph->nodes` contains the VarDecl.
  - `$scope->lookup('$x')` returns the VarDecl.
- After three `declare_class_scope_var` calls with distinct names,
  the list ordering matches insertion order; all three are findable
  via `$scope->lookup`.

**`t/bootstrap/mop/use-constants.t`** — MOP-level structural tests:

- An empty class has zero `use_constants`.
- After `declare_use_constant('FOO', $const_node)`:
  - `use_constants` returns a one-element list.
  - The element is `{name => 'FOO', value => $const_node}` (deep
    structural match).
- Two `declare_use_constant` calls preserve insertion order.

### Integration test (extension to existing file)

**`t/bootstrap/mop/parse-integration.t`** gains assertions on a real
parse:

- Parse `lib/Chalk/Bootstrap/Semiring/Boolean.pm` (chosen because it
  has a class-scope `my $ZERO = []`).
- Assert `$mop->for_class('Chalk::Bootstrap::Semiring::Boolean')
  ->class_scope_vars` has at least one entry whose VarDecl name is
  `'$ZERO'`.
- Pick a class with `use constant` (if any in the corpus; if none,
  hand-construct a tiny synthetic class string and parse it). Assert
  `use_constants` is populated correctly.

### Existing test gates (must not regress)

- `t/bootstrap/mop/codegen-byte-compat.t` (19/19 today)
- `t/bootstrap/mop/codegen-no-backchannel.t` (2/2)
- `t/bootstrap/c-emit-helpers-inheritance.t` (54/54)
- `t/bootstrap/bnf-target-c.t` (178/178)
- Phase 7 baseline doc's pre-existing failures must not change count.

## Risks

1. **Actions.pm `use constant` route may double-declare.** Today
   every UseInfo lands as `declare_import`. After this commit,
   `use constant` lands only as `declare_use_constant`. If any
   existing test asserted `imports` includes `'constant'`, it will
   regress. Mitigation: grep tests for `->imports` accesses before
   landing; document the semantic change in the commit message;
   adjust any test that asserted the old conflation.

2. **VarDecl IR nodes are already merged into a graph upstream.**
   The class body's VarDecls were constructed by Actions.pm's
   VarDecl handler, which already merges them into *some* graph
   via `$ctx->graph()` or freshly allocated `Chalk::IR::Graph->new`.
   Merging into `$mop_class->graph` may create cross-graph
   ownership. Mitigation: probe before implementation — read the
   VarDecl construction site and confirm whether the existing graph
   is `$mop_class->graph` already (in which case the merge is a
   no-op), or a separate graph (in which case the design needs to
   reconcile: either don't merge in declare_class_scope_var, or
   nominate `$mop_class->graph` as the canonical class-body graph
   from VarDecl construction onward).

3. **Scope contract for empty case.** `Chalk::Bootstrap::Scope->new`
   with no bindings is the empty scope. Confirm this constructor
   shape matches existing call sites in Actions.pm; the design
   above assumes it does.

## Out of scope (explicitly)

- Method-scope-inherits-class-scope wiring (deferred to a later
  commit; documented above).
- Promoting `use_constants` from hashref entries to a typed
  `Chalk::MOP::UseConstant` class (YAGNI; promote when state
  accumulates).
- Target::C migration (= 7c-proper, separate commit cluster).
- Target::Perl migration (= no-op; already MOP-driven).
- StructPromotion `_analyze_mop` body→graph (= 7f, independent).
- Adding `__adjust_body` or `__phaser_block` handling to the new
  entity lists (current declare_adjust path is unchanged).

## Commit sequence

This prep ships as one commit (not two as my brainstorming outline
suggested) because the structural fields and the entity-list +
Actions.pm population are coupled — landing the fields alone with
no producers would put dead code on MOP::Class for an indeterminate
period. One commit:

> feat(mop): Phase 7c-prep — MOP::Class gains class-body shape

containing:
- `lib/Chalk/MOP/Class.pm` — new fields, accessors, declare_*
  methods, `use Chalk::Bootstrap::Scope;` and
  `use Chalk::IR::Graph;` additions.
- `lib/Chalk/Bootstrap/Perl/Actions.pm` — ClassBlock action body-
  loop split for VarDecl and `use constant`.
- `t/bootstrap/mop/class-scope-vars.t` — new MOP unit test.
- `t/bootstrap/mop/use-constants.t` — new MOP unit test.
- `t/bootstrap/mop/parse-integration.t` — extension for real-class
  assertions.

## Acceptance

This design is approved when:

- All four sub-decisions (1a + 2a + 2d + 3a + 4b) are reflected
  above with their reasoning.
- Risks are identified with mitigations.
- Out-of-scope items are explicit so 7c-proper has a clear
  contract.
- The commit-sequence note matches what the implementation plan
  will execute.

User approval gate passed at brainstorming time (2026-05-25).
Implementation plan to follow via the writing-plans skill.
