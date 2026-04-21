# Chalk::MOP — Compile-time Meta Object Protocol

## Overview

`Chalk::MOP` is the compile-time metadata layer for the Chalk
compiler. It owns the structural description of the program being
compiled — classes, methods, fields, subroutines, imports,
and phasers — and provides the protocols for constructing, resolving,
and enumerating them.

`Chalk::MOP` is the layer between the parser (which builds the MOP
incrementally as it processes source) and the backends (which consume
it to emit code). It is also the input and output type for program-
scope optimization passes.

The MOP does not own or replace the Sea of Nodes IR. Expression-level
computation and control flow live in per-method `Chalk::IR::Graph`
instances. The MOP owns those graphs as attributes of their
containing methods/subs/phasers, and provides the hash-consing scope
for constructing graph nodes within them.

## Design principles

### Structure lives outside the graph

Following Cliff Click's Sea of Nodes design, program structure
(classes, methods, fields, declarations) is metadata. The graph holds
computation and control flow. This separation is the central insight
of Phase 4b of Chalk's SoN IR migration and is preserved here: MOP
metaobjects are not IR nodes and do not participate in use-def chains.

### Packages are classes

In traditional Perl, packages and classes are conflated: a class is
just a package that happens to have methods and a constructor. Chalk
inverts this: **packages are classes**. The class is the fundamental
organizational unit. Every subroutine, every `use` declaration, every
piece of code belongs to a class. Code outside any explicit `class`
declaration belongs to an implicit `main` class that the MOP seeds on
construction.

This is a natural consequence of targeting Perl's `feature class`:
the `class` keyword creates a package with lexically-scoped fields,
declared methods, and lifecycle phasers. Chalk treats that as the
universal case, not the special one.

### Closed-world assumption

Chalk compiles a restricted subset of Perl that excludes features
defeating static analysis: `require`, string `eval`, symbolic
references, `bless`, `@INC` hooks, `AUTOLOAD`, runtime class
mutation. The MOP assumes that every class, method, field, and
subroutine in the compilation is known at parse time.

This makes Chalk's MOP structurally analogous to Graal Native Image's
`HostedUniverse` — an AOT closed-world metadata layer — rather than
to runtime-reflective MOPs like Class::MOP or HotSpot's JIT-oriented
ci-layer.

### Responsibility-distributed construction

Metaobjects are declared on the scope that owns them:

```perl
my $mop    = Chalk::MOP->new;              # seeds implicit 'main' class
my $main   = $mop->for_class('main');
$main->declare_import('strict');
$main->declare_sub('helper', params => \@p);

my $class  = $mop->declare_class('Point', superclass => $base);
$class->declare_import('Scalar::Util', args => ['refaddr']);
my $field  = $class->declare_field('$x', param_name => 'x');
my $method = $class->declare_method('distance', params => \@p);
```

This is not cosmetic. Placing `declare_field` on `Class` makes it
structurally impossible to declare a field without a class in hand.
`declare_sub` and `declare_import` are on `Class` because every
subroutine and every `use` declaration belongs to a package — even
"top-level" code belongs to `main`. Scope validity is enforced by
the object graph, not by runtime checks in a centralized factory.

### Graph-owner role

Any metaobject that has a body of executable code (methods,
subroutines, ADJUST blocks, field defaults) owns a `Chalk::IR::Graph`.
The hash-consing factory for constructing graph nodes lives on the
**class**, not on each individual graph-owner. Methods, ADJUST blocks,
and field defaults within a class all delegate node construction to
`$class->make()` / `$class->make_cfg()`.

In Perl, the compilation unit is the class: `class Foo { ... }`
creates a discrete bounded scope with its own namespace, fields,
methods, and phasers. Hash-consing scope follows that boundary. Nodes
within a class are deduplicated (methods referencing the same
constants or field-access patterns share nodes naturally). Nodes
across classes are never shared. Consumer lists stay bounded to the
class scope.

Top-level subs and statements (outside any explicit `class`
declaration) belong to the implicit `main` class, which the MOP
seeds on construction. There is no code outside a class; `main` is
always present.

`Chalk::IR::NodeFactory` as a standalone class is replaced by this
per-class ownership.

### Resolved references, not symbolic names

Graph nodes that reference structural entities (method calls, field
accesses) carry resolved `Chalk::MOP::Method` or `Chalk::MOP::Field`
handles rather than string names. Resolution happens at construction
time through the MOP's lookup protocols. This matches how SoN
compilers universally handle cross-scope references: HotSpot's call
nodes carry `ciMethod*`, Graal's carry `HostedMethod`, TurboFan's
carry `SharedFunctionInfoRef`.

### MOP as a compile-time coordination surface

The MOP is not a SemanticAction-private concern. It is the
compile-time coordination surface for every layer of the compiler:
the parser builds it, semirings enrich it, optimizer passes consume
and transform it, code generators read it.

Reachability reflects this. The MOP is accessible via Context
(`$ctx->mop()`) during parsing, so semirings beyond SemanticAction
— TypeInference, Structural, and any future layer — can reach
metaobjects and enrich them directly. TypeInference, for example,
can record an inferred return type on `Chalk::MOP::Method::return_type`
during parsing rather than leaving the information in a transient
Context annotation for codegen to re-derive.

Chalk::MOP is in the AMOP tradition (Kiczales, Stevan Little).
Metaobjects are live objects in the language's own object system,
and meta-circularity — the MOP describing itself — is a correctness
property of self-hosting, not a separate feature. After self-hosting
closes, Chalk's runtime IS a target runtime: the distinction between
"compile-time MOP" and "target-runtime class system" collapses
because the target program IS Chalk. The MOP is not an analog of
HotSpot's ci-layer; it is the object system itself. The
metaobject types specified below cover class-scope structure
(Class, Method, Field, Sub, Import, Phaser::Adjust). The MOP is
extensible downward — `Chalk::MOP::LocalVar`, `Chalk::MOP::Scope`,
per-expression type metaobjects, and other compile-time entities
that multiple layers coordinate on are structurally admissible.
Downward extension is out of scope for the initial MOP and will be
specified separately when the coordination benefit justifies the
new metaobjects.

## Metaobject types

### `Chalk::MOP`

The compilation-unit owner. Holds the class registry and provides
cross-class resolution protocols. Seeds an implicit `main` class on
construction — all code belongs to a class, including top-level
subroutines and `use` declarations.

```
class Chalk::MOP {
    # Construction
    method declare_class($name, %opts)     → Chalk::MOP::Class

    # Enumeration (closed-world)
    method classes()                        �� list of Chalk::MOP::Class

    # Lookup
    method for_class($name)                 → Chalk::MOP::Class | undef
}
```

`for_class('main')` always succeeds — the implicit `main` class is
present from construction.


### `Chalk::MOP::Class`

A class declaration. Owns fields, methods, subs, imports,
and ADJUST blocks declared directly on this class (not inherited).
Also owns the hash-cons factory shared by all graph-owners within
the class. The implicit `main` class is a `Chalk::MOP::Class` like
any other — it just has no fields, no superclass, and no ADJUST
blocks.

```
class Chalk::MOP::Class {
    # Identity
    method name()              → string
    method superclass()        → Chalk::MOP::Class | undef
    method mop()               → Chalk::MOP

    # Direct-declared contents
    method fields()            → list of Chalk::MOP::Field
    method methods()           → list of Chalk::MOP::Method
    method subs()              → list of Chalk::MOP::Sub
    method imports()              → list of Chalk::MOP::Import
    method adjust_blocks()     → list of Chalk::MOP::Phaser::Adjust

    # Construction
    method declare_field($name, %opts)     → Chalk::MOP::Field
    method declare_method($name, %opts)    → Chalk::MOP::Method
    method declare_sub($name, %opts)       → Chalk::MOP::Sub
    method declare_import($module, %opts)     → Chalk::MOP::Import
    method declare_adjust(%opts)           → Chalk::MOP::Phaser::Adjust

    # Resolution (walks ancestor chain — single inheritance)
    method find_method($name)  → Chalk::MOP::Method | undef
    method ancestors()         → list of Chalk::MOP::Class
    method resolve_adjust_blocks() → list of Chalk::MOP::Phaser::Adjust

    # Node factory (hash-cons scope for the class compilation unit)
    method make($op, %args)    → Chalk::IR::Node      # hash-consed data nodes
    method make_cfg($op, %args)→ Chalk::IR::Node      # unique-id CFG nodes
}
```

`fields()` / `methods()` / `adjust_blocks()` return direct-declared
metaobjects only, following `B::MOP`'s convention.

`find_method($name)` walks the ancestor chain (single inheritance —
`superclass()` until `undef`) checking each class's direct `methods()`
list. `ancestors()` returns the full chain. `resolve_adjust_blocks()`
returns ADJUST blocks in base-class-first, source-order-within-class
order — the sequence a constructor must execute.

### `Chalk::MOP::Field`

A field declaration within a class. Vocabulary aligned with
`B::MOP::Field`.

```
class Chalk::MOP::Field {
    method name()              → string           # with sigil: '$x', '@items'
    method sigil()             → '$' | '@' | '%'
    method fieldix()           → int              # position in object's field array
    method class()             → Chalk::MOP::Class
    method param_name()        → string | undef   # :param attribute value
    method has_default()       → bool
    method default_graph()     → Chalk::IR::Graph | undef
    method type()              → ChalkType        # from TypeInference
    method attributes()        → list             # raw attribute descriptors
}
```

`fieldix` is the field's offset in the object's internal array —
load-bearing for C-target codegen. `param_name` exposes the `:param`
attribute, a first-class concept in Perl's `feature class`.
`default_graph` is Chalk-specific: `B::MOP` exposes only
`has_default` because it cannot see the expression body.

When a field has a default expression, the field is a graph-owner
(it has `make()` / `make_cfg()` for constructing its default graph).

### `Chalk::MOP::Method`

A method declaration within a class. Graph-owner: owns the method's
`Chalk::IR::Graph`. Node construction delegates to the owning class's
factory (`$self->class->make(...)`) so that hash-consing is per-class.

```
class Chalk::MOP::Method {
    method name()              → string
    method class()             → Chalk::MOP::Class
    method params()            → list of param descriptors
    method return_type()       → ChalkType | undef
    method graph()             → Chalk::IR::Graph
}
```

### `Chalk::MOP::Sub`

A subroutine declaration within a class. Distinguished from a method
by having no implicit `$self` and not participating in method
dispatch. Graph-owner: node construction delegates to the owning
class's factory.

```
class Chalk::MOP::Sub {
    method name()              → string
    method class()             → Chalk::MOP::Class
    method params()            → list of param descriptors
    method return_type()       → ChalkType | undef
    method graph()             → Chalk::IR::Graph
}
```

### `Chalk::MOP::Import`

Records an import set up by a `use` statement within a class. Tracks
which names were imported from which module, so that method resolution
can recognize imported symbols, codegen can emit the corresponding
`use` lines, and dependency analysis can order compilation. Not a
graph-owner.

```
class Chalk::MOP::Import {
    method module()            → string
    method args()              → list
    method class()             → Chalk::MOP::Class
}
```

### `Chalk::MOP::Phaser`

Abstract base for phaser metaobjects. A phaser is a lifecycle hook
with a body of executable code, ordered by source position and (for
class-scope phasers) by MRO. Graph-owner.

```
class Chalk::MOP::Phaser {
    method graph()             → Chalk::IR::Graph
    method source_position()   → int
}
```

Node construction for phaser bodies delegates to the owning class's
factory, same as methods.

### `Chalk::MOP::Phaser::Adjust`

The only phaser Chalk currently implements. Runs during instance
construction: base-class ADJUST blocks first (MRO order), then
derived-class blocks, source order within each class. No name, no
signature, no return value.

```
class Chalk::MOP::Phaser::Adjust :isa(Chalk::MOP::Phaser) {
    method class()             → Chalk::MOP::Class
}
```

The `Chalk::MOP::Phaser` namespace is structured for extensibility
should future class-lifecycle phasers land (e.g., DEMOLISH).

### `Chalk::MOP::Role` (reserved)

Namespace reserved for future Perl role-composition support. Chalk's
grammar does not currently accept `role` declarations. When it does,
`Chalk::MOP::Role` would parallel `B::MOP::Role`: name, fields,
methods, required_methods, roles.

## Prior art

The design draws from two traditions.

### SoN compiler metadata layers

Every mature Sea of Nodes compiler separates computation (in the
graph) from program structure (in a metadata wrapper layer).

- **HotSpot C2** (`src/hotspot/share/ci/`): `ciMethod`, `ciKlass`,
  `ciField` — compile-time wrappers around runtime VM metadata,
  needed for GC safety. Per-method graphs. Call nodes carry
  `ciMethod*` attributes. Classes appear in the graph only as typed
  constant nodes (`TypeKlassPtr`) when runtime semantics require it.

- **Graal Native Image** (`com.oracle.svm.hosted.*`):
  `HostedUniverse` with `HostedType`, `HostedMethod`, `HostedField`.
  AOT closed-world compilation. Points-to analysis determines
  reachability; unreachable types are dropped. Per-method
  `StructuredGraph` instances. The closest structural precedent for
  Chalk.

- **TurboFan** (`src/compiler/js-heap-broker.h`): `JSHeapBroker`
  with `MapRef`, `JSFunctionRef`, `SharedFunctionInfoRef`. Off-thread
  compilation safety via snapshotted refs. Maps (V8 hidden classes)
  are broker refs, not graph nodes.

- **Simple** (`SeaOfNodes/Simple`, chapter 24): `CodeGen` holds the
  graph endpoints and a `_linker` function-index table. One graph
  for the whole program. `FunNode extends RegionNode`. Minimal, but
  demonstrates the same pattern: structure lives on a coordination
  object, not in a meta-graph.

The common pattern: a compile-time metadata wrapper layer external to
the graph, with resolved-handle references carried by graph nodes.
Graph granularity varies; the wrapper layer is universal.

### Perl meta-object protocols

- **`B::MOP`** (Stevan Little, `stevan/perl5` commit 445c0589):
  read-only introspection of Perl 5.42 `feature class` classes.
  Four metaobject types (`Class`, `Role`, `Field`, `Method`) with
  vocabulary aligned to `feature class` (`fields`, `methods`,
  `roles`, `adjust_blocks`, `fieldix`, `param_name`, `has_default`).
  Chalk borrows this vocabulary and type split. `B::MOP` reflects
  over a loaded interpreter; Chalk constructs at compile time. The
  metaobject shape transfers; the data-flow direction inverts.

- **Class::MOP / Moose**: the most studied Perl MOP. Classes,
  methods, attributes as first-class metaobjects with introspection
  and mutation protocols. MRO as a protocol. Attribute traits.
  Chalk's MOP is deliberately smaller (no metaclass mutation, no
  method modifiers, no BUILD) because it targets `feature class`'s
  restricted vocabulary, not Moose's full extensibility.

## Scope boundaries

### What the MOP owns

- The catalog of classes (including the implicit `main` class) and
  their contents — fields, methods, subs, imports, and
  ADJUST blocks — for one compilation unit.
- The per-method/sub/phaser `Chalk::IR::Graph` instances.
- The hash-consing scope for each graph-owner's node construction.
- Resolution protocols: class lookup, method lookup (with ancestor
  walk), ADJUST block ordering.

### What the MOP does not own

- `Chalk::IR::Node` and its concrete subclasses. Graph nodes are the
  expression-level representation. There is no parallel
  `Chalk::MOP::Expression` or `Chalk::MOP::Statement` layer.
- `Chalk::IR::Graph`'s internal structure (start, returns, schedule,
  `nodes()` traversal). Graph operations are defined on Graph, not
  on the MOP.
- Parse-time state (Context, semirings). The parser builds the MOP
  incrementally; the MOP does not know about the parser's internal
  machinery.
- Runtime behavior. `Chalk::MOP` is a compile-time construct. A
  runtime introspection facility for compiled Chalk programs is
  separate work.

### Explicit exclusions

- **Metaclass compatibility / metaclass mutation.** The set of
  metaobject types is fixed.
- **Open-world features.** `require`, string `eval`, symbolic
  references, `bless`, `@INC` hooks, `AUTOLOAD`, runtime class
  mutation. The closed-world assumption depends on these exclusions.
- **Multi-unit compilation.** The MOP owns one compilation unit.
  Cross-unit class inheritance is future scope.
- **Non-ADJUST phasers.** `BEGIN`, `INIT`, `CHECK`, `END`,
  `UNITCHECK` are not in scope. They may land in a future design
  with different semantics than runtime Perl (the closed-world
  analog would be CFG placement directives rather than runtime
  hooks).
- **Roles.** Out of scope; namespace reserved.

## Open questions

1. **Namespace.** `Chalk::MOP` is this spec's proposal, aligned with
   `B::MOP`. Alternatives: `Chalk::IR::MOP`, `Chalk::Meta`,
   `Chalk::CompilationUnit`.

2. **Graph traversal with shared nodes.** Per-class hash-consing
   means a shared node (e.g., `Constant 0`) can have consumers from
   multiple methods within the same class. Per-method
   `Graph.nodes()` should follow `inputs()` only (scoped to the
   method's subgraph). A class-level `all_nodes()` traversal can
   safely follow both directions since everything in scope belongs
   to the same compilation unit.

3. **Field default ownership.** Fields with default expressions need
   a graph. This spec makes the field itself a graph-owner when
   defaults are present. A dedicated `Chalk::MOP::FieldDefault`
   sub-metaobject would keep Field simpler.

4. **Graph-owner implementation mechanism.** Parent class, composed
   role, or direct inclusion. Not a spec concern; the contract is
   that graph-owners provide `make()` / `make_cfg()` / `graph()`.
