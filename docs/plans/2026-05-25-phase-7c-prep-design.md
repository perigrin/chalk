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

## Framing: a class body has a lexical environment

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

This prep commit ships the **lexical-environment** half of that
framing — `$scope` and the two typed entity lists 7c-proper needs.
The graph-shaped half (a per-class `$graph` walked the way method
codegen walks a method graph) is deferred until 7d-or-later
provides a consumer; see "Why no `$graph` or `$factory`" below.

## What ships

### MOP::Class new field (lexical environment only)

- `field $scope :param :reader = Chalk::Bootstrap::Scope->new;`

This is the lexical environment of the class body — the scope that
class-scope `my $x = ...;` and `use constant` declarations extend,
and that method/sub bodies will eventually close over (deferred
wiring; see sub-decision 3a).

**What reads `$scope` in 7c-proper.** Nothing. 7c-proper consumes
`@class_scope_vars` and `@use_constants` as list iterators; it does
not need to look up bindings by name. `$scope` is populated by this
commit but unread until a later commit (the one wiring method
bodies to close over the class scope, or any commit that wants
name-resolution against the class's lexical environment).

**Why ship `$scope` now anyway.** Three reasons:

1. `declare_class_scope_var` has to bind the VarDecl into *something*
   representing the lexical environment. Binding into `$scope` is
   the model that matches how method scopes work today — the
   alternative (skip the binding entirely, recover the lex-env
   later by re-walking `@class_scope_vars`) duplicates information
   and creates the same dual-source-of-truth pattern this prep
   commit is trying to avoid.
2. The cost is minimal: one field, one Scope allocation per class.
3. The consumer is *known* (Phase 7d-or-later) and *near-term*, not
   a hypothetical future need. Adding `$scope` now defers a
   guaranteed future touch of MOP::Class; the alternative pays the
   re-touch cost without saving anything.

This is the YAGNI line we're drawing: ship the lexical-env field
because its producer (`declare_class_scope_var`) needs a destination
and the consumer is known. Do not ship `$graph` / `$factory`
because no producer needs them yet (Risk #2) and no consumer exists
until 7d at earliest.

**Why no `$graph` or `$factory` field in this commit.** The original
design (per the brainstorming sketch) proposed `$graph` and
`$factory` here, paralleling MOP::Method's structure. The spec
review surfaced two problems with that:

1. **Cross-graph ownership risk** — VarDecl IR nodes are constructed
   by Actions.pm *before* the ClassBlock action runs. By VarDecl
   construction time (Actions.pm:1751, 1757), the VarDecl has
   already been merged into `$ctx->graph()`. Calling
   `$mop_class->graph->merge($vardecl_node)` later either no-ops
   (same graph) or cross-claims the node into a second graph,
   potentially corrupting use-def chains.

2. **No consumer in 7c-proper.** Phase 7c-proper consumes the two
   typed entity lists (`@class_scope_vars`, `@use_constants`) and
   `$scope`. It does NOT walk `$mop_class->graph`. Shipping
   `$graph`/`$factory` now puts unread fields on every MOP::Class
   instance until some later phase (7d at earliest) provides a
   consumer.

YAGNI applies: ship only `$scope` now. The graph-shaped framing of
class bodies (the original SSA framing that motivated this prep)
returns when 7d-or-later actually needs to walk the class body as
a graph. At that point, the resolution of the cross-graph ownership
question is also part of that commit's contract, not a deferred
landmine in this one.

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
    # by Actions.pm (already merged into $ctx->graph() upstream).
    # Record in @class_scope_vars (for codegen iteration in 7c-proper)
    # and bind the name in $scope (for the lexical environment).
    # Do NOT merge into a per-class graph in this commit — no class
    # graph exists yet, and Risk #2 (cross-graph ownership) is
    # explicitly avoided by not duplicating the merge.
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

- Parse `lib/Chalk/Bootstrap/Semiring/Structural.pm` (chosen because
  line 36 has an initialized class-scope `my $ZERO = -1;`, the
  simplest real-world class with class-scope state in the corpus).
- Assert `$mop->for_class('Chalk::Bootstrap::Semiring::Structural')
  ->class_scope_vars` has at least one entry whose VarDecl name is
  `'$ZERO'`.
- For `use_constants`, scan the corpus for an existing `use constant
  { ... }` declaration. If none exists at class scope (most likely
  the case; `use constant` in the Chalk codebase tends to live at
  module scope), hand-construct a tiny synthetic class string and
  parse it. Assert `use_constants` is populated correctly.

Note: uninitialized `my $x;` declarations (e.g., Boolean.pm:14
`my $ZERO_CTX;`) also produce VarDecl IR nodes — Actions.pm:1743
constructs VarDecl unconditionally with `init` set to undef when no
initializer is present. So Boolean.pm would also work as a target;
Structural.pm is chosen for the simpler single-init case.

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
   regress.

   Verified during spec review: 6 test files touch `->imports`
   (class.t, parse-integration.t, hand-constructed.t, import.t,
   plus class-all-nodes.t and class.t which match `Constant` IR
   ops, not `'constant'` use-decls). No site asserts the literal
   string `'constant'` as a module name. Risk is low-to-zero in
   practice; document the semantic change in the commit message
   anyway in case a future test asserts the old conflation.

2. **Cross-graph ownership — resolved by scope reduction.** The
   original design proposed merging the VarDecl into a new
   `$mop_class->graph`. Actions.pm:1751, 1757 already merges
   VarDecls into `$ctx->graph()` at construction time, so a second
   merge in `declare_class_scope_var` would either no-op or cross-
   claim the node into two graphs.

   Resolved: this commit ships only `$scope` (no `$graph` field on
   MOP::Class). `declare_class_scope_var` does not merge into any
   class-side graph. The VarDecl stays in its single upstream graph
   (the per-method/per-class-body graph allocated by
   `$ctx->graph()` during parsing). Future commits that want a
   class-body graph as a first-class concept will reconcile the
   ownership at that time, with a real consumer in scope.

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

- All four sub-question resolutions (1a; 2a + 2d; 3a; 4b) are reflected
  above with their reasoning.
- Risks are identified with mitigations.
- Out-of-scope items are explicit so 7c-proper has a clear
  contract.
- The commit-sequence note matches what the implementation plan
  will execute.

User approval gate passed at brainstorming time (2026-05-25).
Implementation plan to follow via the writing-plans skill.
