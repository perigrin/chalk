<!-- ABOUTME: Architecture of Chalk's compile-time MOP (Meta-Object Protocol). -->
<!-- ABOUTME: Covers Class/Method/Sub/Field/Phaser containers and per-parse factory ownership. -->

# Chalk MOP Layer

**Source**: `lib/Chalk/MOP.pm`, `lib/Chalk/MOP/*.pm`

## Overview

The MOP is a compile-time meta-object protocol — a layer of typed
containers that sits between the SemanticAction semiring and the code
generators. SemanticAction builds MOP instances as a side effect of
parsing; codegen consumes them.

The MOP exists for two reasons:

1. To give the compiler a typed structural view of the program (which
   classes exist, what their fields and methods are, what each method's
   IR graph is) rather than a soup of metadata structs.
2. To carry the per-parse IR. Each `MOP::Method` and `MOP::Sub`
   declares its own `Chalk::IR::Graph` field and a `$factory` field
   (`Chalk::IR::NodeFactory`); today production code uses a single
   per-Actions `NodeFactory` injected via `SemanticAction::set_factory`
   for hash-consing across the parse, and the per-method `$factory`
   field is currently unused scaffolding. The per-method
   `MOP::Method->graph` *is* populated and is the source of truth for
   each method's IR. True per-method hash-cons isolation is a future
   migration (the per-method `$factory` field is the hook); today's
   reality is per-parse factory ownership with per-method graph
   ownership.

```
SemanticAction semiring
        |
        v                    set_mop($mop), set_factory($f)
  +-----------+              +-----------------------------+
  | MOP layer | <----- read/write ----- Actions, _one_ctx, _complete_sa
  |  Class    |
  |   |- Field|
  |   |- Method --> Graph + NodeFactory
  |   |- Sub    --> Graph + NodeFactory
  |   |- Phaser --> Graph
  |   |- Import|
  +-----------+
        |
        v
  Codegen (Target/Perl, Target/C, ...)
```

## Class structure

`Chalk::MOP` is the root container — a per-parse instance that owns the
class registry. It is constructed once at parse start (along with the
implicit `main` class) and threaded through the parse via the Context
`mop` field.

```perl
my $mop = Chalk::MOP->new;
$mop->declare_class('MyClass', parent_name => 'Base');
my $cls  = $mop->for_class('MyClass');
my $main = $mop->for_class('main');     # implicit, seeded in ADJUST
$mop->find_method('foo');               # cross-class method lookup
```

Each registered class is a `Chalk::MOP::Class` instance. A class owns:

| Field | Description |
|-------|-------------|
| `name` | The class name. |
| `parent_name` | Parent class name as a string (resolution is deferred). |
| `superclass` | Resolved parent `MOP::Class` instance once available. |
| `fields` | Ordered list of `MOP::Field` instances. |
| `methods` | Ordered list of `MOP::Method` instances. |
| `subs` | Ordered list of `MOP::Sub` instances. |
| `imports` | Ordered list of `MOP::Import` instances. |
| `adjust_blocks` | Ordered list of `MOP::Phaser::Adjust` instances. |

Constructors are `declare_field`, `declare_method`, `declare_sub`,
`declare_import`, and `declare_adjust`. Each returns the new MOP
instance so Actions code can hold on to it for further population (e.g.
to attach a graph to a method that is still being built).

Two ergonomic methods on `MOP::Class`:

- `find_method($name)` — walks the superclass chain.
- `resolve_adjust_blocks()` — returns ADJUST blocks in base-class-first,
  source-order-within-class order (the MRO order they actually run in).

## Method and Sub structure

`Chalk::MOP::Method` and `Chalk::MOP::Sub` are nearly identical. Both
own:

| Field | Description |
|-------|-------------|
| `name` | The method or sub name. |
| `class` | The owning `MOP::Class`. |
| `params` | Parameter list (arrayref of parameter records). |
| `return_type` | Resolved return type (when known). |
| `graph` | A `Chalk::IR::Graph` containing this body's IR. Source of truth for this method's/sub's nodes. |
| `factory` | A `Chalk::IR::NodeFactory` field reserved for future per-method hash-cons isolation. Currently unused — production code constructs nodes through the per-Actions `NodeFactory` injected via `SemanticAction::set_factory`. |
| `body` | An arrayref of statement IR nodes in parser-observed source order. See "Relationship to metadata structs" below. |

The distinction between `Method` and `Sub`:

- `Method` has an implicit `$self` parameter and is dispatched via the
  class. `Sub` is a free subroutine declared lexically inside a class.
- `Method` additionally tracks `lexical_bindings` — `VarDecl` IR nodes
  declared in the method body, used during scope analysis.

Node construction today happens through `$ctx->factory->make($op, %a)`
in action methods, where `$ctx->factory` is the per-parse factory
seeded by `_one_ctx`. The constructed node is then attached to a
specific method/sub's graph via `$ctx->graph->merge($node)`. There is
no MOP-level node-*construction* API today; the `MOP::Method->factory`
field is reserved for a future migration that would route construction
through the owning method/sub.

For node *membership* in a graph, `MOP::Method` and `MOP::Sub`
expose two delegators that go through their owned `$graph`:

```perl
$method->merge($node)    # delegates to $method->graph->merge($node)
$method->next_cfg_id     # delegates to $method->graph->next_cfg_id
```

These are honest: the per-method `$graph` IS the source of truth
for which nodes belong to which method. Two methods with
structurally identical body content produce distinct membership
even though hash-cons identity is shared (per-parse), because each
method's `$graph` has its own cache. See
`t/bootstrap/mop/per-graph-hash-cons.t` for the regression guard.

## Field structure

`Chalk::MOP::Field` records a class field declaration:

| Field | Description |
|-------|-------------|
| `name` | The field name (with sigil stripped). |
| `sigil` | The sigil character (`$`, `@`, `%`). |
| `class` | The owning `MOP::Class`. |
| `fieldix` | Declaration index within the class (used for slot assignment). |
| `param_name` | The `:param` name when the field is constructor-parameterised, else undef. |
| `has_default` | Whether the field has a default expression. |
| `default_value` | The default expression's IR (when present). |
| `type` | The field's declared type (when known). |
| `attributes` | Raw attribute list as written. |

Fields do not own a graph — they are not executable. The default
expression's IR lives in the owning class's construction graph (or on
the relevant phaser).

## Phaser structure

`Chalk::MOP::Phaser` is the abstract base for phaser metaobjects
(lifecycle hooks with executable bodies). It owns:

| Field | Description |
|-------|-------------|
| `graph` | A `Chalk::IR::Graph` containing the phaser body's IR. |
| `source_position` | The source-order index of this phaser within its class (used for stable ordering). |

`Chalk::MOP::Phaser::Adjust` is the only concrete subclass today — it
represents an `ADJUST { ... }` block. It adds a `class` back-reference
so the phaser can be reached from either direction.

Phasers run in MRO order across the class hierarchy
(`MOP::Class::resolve_adjust_blocks()`) and in source order within each
class.

## Import structure

`Chalk::MOP::Import` records a `use Foo` or `use Foo qw(bar baz)`
declaration on a class. Deduplication is enforced by `declare_import` —
the same module is registered only once per class, even if Earley parse
ambiguity causes the semantic action to fire multiple times.

## Per-parse ownership

The MOP and every factory it transitively owns are **per-parse**:

1. **Actions ADJUST** allocates a fresh `Chalk::IR::NodeFactory`,
   binding it to both `$typed` and `$factory` fields on the actions
   instance, and calls
   `Chalk::Bootstrap::Semiring::SemanticAction::set_factory($typed)`.
2. **`SemanticAction::_one_ctx`** reads the injected factory and seeds
   the parse's root Context with it. The Context's initial Start node
   is constructed through that same factory.
3. **Actions** allocates the `Chalk::MOP` instance and calls
   `SemanticAction::set_mop($mop)`. Subsequent `_one_ctx` calls thread
   it into the root Context as the `mop` field.
4. **Each `declare_method`/`declare_sub`/`declare_adjust`** on a
   `MOP::Class` allocates a fresh `Graph` for the new
   method/sub/phaser. (The per-Method/Sub `factory` field is also
   default-initialized but is currently unused — see "Method and Sub
   structure" above.) Node identity within a method is bounded by
   the method's own `Graph` cache.
5. **Context's `extend`** propagates `mop`, `graph`, `scope`, and
   `factory` fields unchanged unless a caller overrides them. See
   `context-comonad.md`.

Tests that need a clean MOP simply allocate a new `Chalk::MOP->new`;
there is no global registry to reset.

This per-parse ownership is what makes the bidirectional traversal in
`Chalk::IR::Graph::nodes()` correct. The per-parse `NodeFactory`
hash-conses all nodes for the parse; the per-method `Graph` decides
which nodes are *members* of which method. A node's `consumers` list
can include pointers to nodes registered with other methods'
graphs, because the factory shares hash-cons identity across them.
`Graph::nodes()` walks consumers only when they are members of the
graph's own cache; otherwise the walk would leak across method
boundaries.

## Relationship to metadata structs

Alongside the MOP, the compiler still maintains a parallel set of
metadata struct types: `Chalk::IR::Program`, `Chalk::IR::ClassInfo`,
`Chalk::IR::MethodInfo`, `Chalk::IR::SubInfo`, `Chalk::IR::UseInfo`,
`Chalk::IR::FieldInfo`. See `sea-of-nodes-ir.md` for their shape.

These structs are still produced during parsing. They are the legacy
representation of program structure. The MOP is the canonical post-parse
representation; the production Perl target now emits from the MOP +
scheduler (golden parity), but the migration is not complete (see
`docs/plans/2026-06-10-mop-migration-reaudit.md` for the audited state).

Specifically:

- `MethodInfo->body` (an arrayref of IR statement nodes) is still
  DUAL-WRITTEN alongside the graph, but the production Perl emission
  path no longer walks it (schedule-driven since the scheduler campaign).
  Remaining `->body` readers: the legacy Perl path, StructPromotion, and
  the Actions dual-write itself.
- The graph bridge is value-level sharing, not delegation:
  `MethodDefinition` builds the graph and stores it on `MethodInfo`
  (Actions.pm); `ClassBlock` then copies `$item->graph()` into
  `declare_method(graph => ...)`. The same `Graph` object lives on both
  sides — the MOP side reads FROM `MethodInfo`, not the other way
  around.
- `Chalk::IR::Node->compat_class` still exists as a field on nodes for
  legacy `->class()` test reads. Production setters were stripped during
  Phase 7d.

Codegen migration to walk MOP graphs directly (and the eventual
deletion of the metadata struct layer) is tracked in
`docs/plans/2026-04-21-chalk-mop-migration-plan.md`. Until that lands,
both representations coexist by design.

### The LLVM backend consumes class structure via ClassInfo (2026-06)

The IR-taxonomy reconciliation (R3) converged the LLVM backend's class
handling onto this layer: there are no in-graph `ClassDecl`/`MethodDef`/
`FieldDef`/`AdjustBlock` nodes. Class structure rides into a graph as an
immutable `Chalk::IR::ClassInfo` (carrying `MethodInfo` objects — extended
with `body_node`/`return_repr` for lowering — plus `Chalk::MOP::Field` and
`Chalk::MOP::Phaser::Adjust` members), and `Chalk::Target::LLVM` builds its
per-class vtable + object struct + ADJUST order from that read surface
(`_scan_class_registry`/`_populate_registry_from_classinfo`). Only the
immutable readers are consumed — the mutable `MOP::Class` declare-API and the
stalled codegen-reads-MOP migration above are untouched by it. See
`sea-of-nodes-ir.md` "LLVM lowering of the canonical MOP and aggregate
vocabulary".
