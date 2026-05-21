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
2. To localise hash-consing and node identity. Each `MOP::Method` and
   `MOP::Sub` owns its own `Chalk::IR::Graph` and
   `Chalk::IR::NodeFactory`, so two methods with structurally identical
   bodies still produce distinct node objects with bounded consumer
   lists.

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
| `graph` | A `Chalk::IR::Graph` containing this body's IR. |
| `factory` | A `Chalk::IR::NodeFactory` whose hash-cons cache is scoped to this body. |
| `body` | A legacy arrayref of statement IR nodes — see "Relationship to metadata structs" below. |

The distinction between `Method` and `Sub`:

- `Method` has an implicit `$self` parameter and is dispatched via the
  class. `Sub` is a free subroutine declared lexically inside a class.
- `Method` additionally tracks `lexical_bindings` — `VarDecl` IR nodes
  declared in the method body, used during scope analysis.

Both classes delegate node construction to their owned factory and
graph:

```perl
$method->make($op, %args)       # delegates to $factory->make
$method->make_cfg($op, %args)   # delegates to $factory->make_cfg
$method->merge($node)           # delegates to $graph->merge
$method->next_cfg_id            # delegates to $graph->next_cfg_id
```

These delegators are what make per-method/per-sub ownership ergonomic in
Actions code: any code path with a handle on the `MOP::Method` can
construct nodes inside that method's graph without reaching for a
sidechannel.

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
   `MOP::Class` allocates a fresh `Graph` and `NodeFactory` for the
   new method/sub/phaser. Identity of nodes is meaningful only within
   that owner's scope.
5. **Context's `extend`** propagates `mop`, `graph`, `scope`, and
   `factory` fields unchanged unless a caller overrides them. See
   `context-comonad.md`.

Tests that need a clean MOP simply allocate a new `Chalk::MOP->new`;
there is no global registry to reset.

This per-parse ownership is what makes the bidirectional traversal in
`Chalk::IR::Graph::nodes()` correct. A node's `consumers` list can
include pointers to nodes that live in a different graph (because hash
consing is per-factory, but a node may be shared across factories if
both happen to construct identical content via independent paths).
`Graph::nodes()` walks consumers only when they are members of the
graph's own cache; otherwise the walk would leak into foreign graphs.

## Relationship to metadata structs

Alongside the MOP, the compiler still maintains a parallel set of
metadata struct types: `Chalk::IR::Program`, `Chalk::IR::ClassInfo`,
`Chalk::IR::MethodInfo`, `Chalk::IR::SubInfo`, `Chalk::IR::UseInfo`,
`Chalk::IR::FieldInfo`. See `sea-of-nodes-ir.md` for their shape.

These structs are still produced during parsing and are still consumed
by the code generators. They are the legacy representation of program
structure. The MOP is the canonical post-parse representation, but
codegen has not yet been migrated to read from it directly.

Specifically:

- `MethodInfo->body` (an arrayref of IR statement nodes) is still the
  source codegen walks. The `MOP::Method->graph` for the same method is
  populated in parallel.
- `MethodInfo->graph()` exists as a delegating accessor that reads from
  the MOP-side graph; this is the bridge while the migration is in
  flight.
- `Chalk::IR::Node->compat_class` still exists as a field on nodes for
  legacy `->class()` test reads. Production setters were stripped during
  Phase 7d.

Codegen migration to walk MOP graphs directly (and the eventual
deletion of the metadata struct layer) is tracked in
`docs/plans/2026-04-21-chalk-mop-migration-plan.md`. Until that lands,
both representations coexist by design.
