<!-- ABOUTME: Architecture of Chalk's Sea of Nodes intermediate representation. -->
<!-- ABOUTME: Covers node types, hash consing, use-def chains, Graph container, and program structure. -->

# Sea of Nodes IR Architecture

## Overview

Chalk uses a Sea of Nodes intermediate representation (IR) to model Perl programs between the parsing stage and code generation. The design follows the principles described by Cliff Click and Michael Paleczny in "A Simple Graph-Based Intermediate Representation" (1995), adapted for the needs of a Perl-to-Perl/C compiler.

In a Sea of Nodes representation, the program is a directed graph of value and control operations. Unlike a basic-block IR where instructions belong to a fixed sequence within a block, data nodes in a Sea of Nodes IR float freely. Their only ordering constraints come from explicit data-flow and control-flow edges. This gives optimization passes latitude to move computations without tracking block membership.

The key properties of Chalk's Sea of Nodes IR are:

- **Explicit data flow.** Every value consumed by a node is named by an edge from the producing node. There are no implicit operand stacks or register allocations at this level.
- **Hash consing for data nodes.** Two data nodes with identical operations and identical inputs are guaranteed to be the same object. This eliminates redundant subexpressions structurally rather than as a separate pass.
- **Immutability.** Once a node is constructed through `NodeFactory`, its operation and inputs are never changed. (The Loop node is the single exception: it exposes `set_backedge_ctrl` to wire in the back edge after the loop body is built, because the loop body cannot be constructed without a reference to the loop header.)
- **Bidirectional use-def chains.** Each node records both its inputs (producers) and its consumers (users), making it straightforward to traverse the graph in either direction.
- **Stable content-based IDs.** Data node IDs are derived from the node's operation and its inputs' IDs, not from a creation counter. This makes IDs deterministic across runs, which is required for byte-identical code generation.

---

## Node Architecture

### Base Class: `Chalk::IR::Node`

All IR nodes extend `Chalk::IR::Node`. The base class holds the fields common to every node:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable content-based identifier. For data nodes, derived from `content_hash()`. For CFG nodes, assigned by `NodeFactory` as `"OpName#N"`. |
| `inputs` | arrayref of nodes | The producer nodes whose values this node consumes. Nested arrayrefs are permitted (e.g., when a node takes a list-valued input). |
| `consumers` | arrayref of nodes | The nodes that consume the value produced by this node. Populated by `NodeFactory._register_consumers` at construction time. |
| `stamp` | any | Optional annotation recording parse-origin or generation context. Not used in graph traversal. |
| `compat_class` | string | Optional override for the value returned by `class()`. Used by `Chalk::IR::Shim` to present legacy constructor class names to code-generation passes while the underlying node type is the canonical IR type. |

The `operation()` method is abstract. Every concrete subclass overrides it to return the operation name string (e.g., `'Add'`, `'Call'`, `'Start'`).

The `content_hash()` method constructs the canonical hash key for the node. The default implementation concatenates `operation()` with the IDs of all inputs. Nodes that carry additional scalar fields (such as `Constant`, `Call`, `Proj`) override `content_hash()` to include those fields.

The `class()` method returns `compat_class` if set, otherwise delegates to `operation()`. Callers that need the IR operation type should call `operation()`; callers that need the legacy constructor class name (for code-generation dispatch tables built before the IR migration) should call `class()`.

### Concrete Field Overrides in `content_hash()`

Nodes that carry non-input scalar fields must include those fields in `content_hash()` to ensure hash-consing correctness. The following table lists the fields incorporated by each such node:

| Node | Additional hash fields |
|------|----------------------|
| `Constant` | `const_type`, `value` |
| `Call` | `dispatch_kind`, `name` |
| `Phi` | `region` (as node ID) |
| `Proj` | `index` |
| `PadAccess` | `targ`, `varname` |
| `FieldAccess` | `field_index`, `field_stash` |
| `StashAccess` | `stash_name`, `var_name` |
| `CompoundAssign` | `op` |
| `PostfixDeref` | `sigil` |
| `RegexMatch` (via `Regex`) | `pattern`, `flags` |
| `RegexSubst` (via `Regex`) | `pattern`, `flags` |
| `VarDecl` | `scope` |
| `AnonSub` | `anon_id` (sequential counter) |

`AnonSub` is a special case. Each anonymous subroutine has a distinct closure body, so two `AnonSub` nodes with the same inputs are not semantically identical. A sequential counter (`anon_id`) is included in the hash key to prevent incorrect deduplication.

---

## Node Categories

Chalk's nodes fall into three categories: CFG (control-flow graph) nodes that carry control tokens, data nodes that carry values, and aggregate nodes that construct compound values.

### CFG Nodes

CFG nodes model the control flow of a method. They are created exclusively through `NodeFactory.make_cfg()` and are never hash-consed — each call produces a new node with a unique sequential ID. This reflects the fact that two `If` nodes with the same condition are semantically different control points.

| Node | Description |
|------|-------------|
| `Start` | Entry point of a computation graph. Has no inputs. Produces the initial control token. Every `Graph` has exactly one `Start`. |
| `Return` | Normal exit. Takes a control input and a value input. Represents a function `return`. A `Graph` may have multiple `Return` nodes. |
| `Unwind` | Exceptional exit. Represents control reaching a `die` or unhandled exception. Takes a control input. |
| `If` | Conditional branch. Takes a control input and a boolean condition. Produces two control outputs accessed via `Proj` nodes (index 0 = false, index 1 = true). |
| `Proj` | Projection. Selects one control output from a multi-output node such as `If`. Carries an integer `index` field. |
| `Region` | Merge point. Joins two or more control-flow paths into a single control token. Used for the merge after an `if`/`else`. |
| `Loop` | Loop header. Holds the entry control edge in `inputs->[0]` and the back-edge control in `inputs->[1]`. The back edge is set after the loop body is constructed via `set_backedge_ctrl()`. |

The `Phi` node is classified as a data node by `NodeFactory` (it is hash-consed via `make()`) but it is semantically tied to a `Region` or `Loop` node recorded in its `region` field. A `Phi` node merges two values from different incoming control paths at a join point. Like `Loop`, it supports `set_backedge()` to wire the loop-iteration value after the body is built.

### Data Nodes

Data nodes model computations that produce values. They are hash-consed by `NodeFactory.make()`.

#### Variable Access

| Node | Description |
|------|-------------|
| `PadAccess` | Reads a lexical variable by pad slot index (`targ`) and name (`varname`). Represents `$x`, `@arr`, `%hash`. |
| `FieldAccess` | Reads a Perl 5.42 class field by slot index (`field_index`) and package name (`field_stash`). Represents `$self->{field}` in class context. |
| `StashAccess` | Reads a package global by stash name and variable name. Represents `$Foo::bar` or `%Foo::`. |
| `Subscript` | Array or hash subscript. `inputs->[0]` is the container; `inputs->[1]` is the index or key. |
| `PostfixDeref` | Postfix dereference (`$ref->@*`, `$ref->%*`). Carries the `sigil` field indicating dereference kind. |

`PadAccess`, `FieldAccess`, `StashAccess`, and `Subscript` share the intermediate base class `Chalk::IR::Node::Access`. This base class adds no fields; it exists to allow type-based dispatch in optimization and code-generation passes.

#### Arithmetic and Logic

Binary operators extend `BinOp`, which provides `left()` and `right()` as named fields with `:param :reader`, initialized from `inputs` in an `ADJUST` block. All binary operator nodes delegate `operation()` to their concrete subclass name.

| Category | Nodes |
|----------|-------|
| Arithmetic | `Add`, `Subtract`, `Multiply`, `Divide`, `Modulo`, `Power` |
| String | `Concat` (`'.'`), `Repeat` (`'x'`) |
| Numeric comparison | `NumEq`, `NumNe`, `NumLt`, `NumGt`, `NumLe`, `NumGe`, `NumCmp` |
| String comparison | `StrEq`, `StrNe`, `StrLt`, `StrGt`, `StrLe`, `StrGe`, `StrCmp` |
| Boolean | `And` (`&&`/`and`), `Or` (`||`/`or`), `Xor` (`xor`) |
| Bitwise | `BitAnd`, `BitOr`, `BitXor`, `LeftShift`, `RightShift` |
| Assignment | `Assign` (`=`), `CompoundAssign` (`+=`, `-=`, `.=`, etc.) |
| Pattern | `Match` (`=~`), `NotMatch` (`!~`) |
| Other binary | `DefinedOr` (`//`), `Range` (`..`), `Yada` (`...`), `IsaOp` (`isa`) |

Unary operators extend `UnaryOp`, which provides `operand()` as a named field with `:param :reader`, initialized from `inputs` in an `ADJUST` block.

| Category | Nodes |
|----------|-------|
| Logic | `Not` (`!`/`not`) |
| Arithmetic | `Negate` (`-`), `UnaryPlus` (`+`) |
| Bitwise | `Complement` (`~`) |
| Other unary | `Defined` (`defined`), `Ref` (`\\`) |

#### Calls

| Node | Description |
|------|-------------|
| `Call` | Unified call node for method calls, subroutine calls, and builtin calls. Carries `dispatch_kind` (`'method'`, `'sub'`, `'builtin'`) and `name`. The invocant or first argument appears in `inputs`. |

`Chalk::IR::Shim` maps legacy constructor classes (`MethodCallExpr`, `BuiltinCall`) to `Call` nodes with appropriate `dispatch_kind` and a `compat_class` override for backward-compatible dispatch.

#### Regex

| Node | Description |
|------|-------------|
| `RegexMatch` | Pattern match (`m//`). Extends `Regex` base, which carries `pattern` and `flags` fields. `inputs->[0]` is the target expression. |
| `RegexSubst` | Substitution (`s///`). Extends `Regex` base. Carries `pattern`, `replacement`, and `flags`. |

#### Control and Special

| Node | Description |
|------|-------------|
| `TernaryExpr` | Ternary conditional (`cond ? a : b`). `inputs->[0]` is the condition, `inputs->[1]` is the true branch, `inputs->[2]` is the false branch. Intended to be lowered to `If`+`Proj`+`Region`+`Phi` in a future optimization pass. |
| `TryCatch` | Try/catch statement. `inputs->[0]` is the try body, `inputs->[1]` is the catch variable, `inputs->[2]` is the catch body. |
| `AnonSub` | Anonymous subroutine (closure). Carries a nested `Chalk::IR::Graph` in its `graph` field for the sub body. |
| `VarDecl` | Variable declaration. Carries a `scope` field (`'my'`, `'our'`, `'state'`). |
| `Constant` | Compile-time constant. Carries `const_type` (`'string'`, `'integer'`, `'undef'`, etc.) and `value`. |
| `Stringify` | Explicit string coercion. |
| `BacktickExpr` | Backtick command execution. `inputs->[0]` is the command expression. |

#### Struct Promotion Nodes

These nodes are produced by the StructPromotion optimizer, which promotes hash references with known schemas into typed structs for XS code generation.

| Node | Description |
|------|-------------|
| `StructRef` | Promoted hash reference with a named schema. `inputs->[0]` is the schema name, `inputs->[1]` is the field values. |
| `StructFieldAccess` | Field access on a promoted struct, distinct from class `FieldAccess`. |

### Aggregate Nodes

Aggregate nodes construct compound values from a list of sub-expressions. They extend the intermediate base class `Chalk::IR::Node::Aggregate`.

| Node | Description |
|------|-------------|
| `HashRef` | Constructs a hash reference from a list of key/value pairs. |
| `ArrayRef` | Constructs an array reference from a list of elements. |
| `Interpolate` | Constructs a double-quoted string from an ordered list of literal and variable parts. |

---

## NodeFactory: Hash Consing Protocol

`Chalk::IR::NodeFactory` is the single factory through which all nodes must be created. It maintains an internal cache keyed by `content_hash()` and enforces the two-class discipline.

### `make($op_name, %args)`

Creates or retrieves a hash-consed data node.

1. Looks up the target class in `%DATA_CLASSES` by `$op_name`. Dies if unknown.
2. Constructs a temporary node with `id => '_tmp'` to invoke `content_hash()` without permanently registering the node.
3. If the cache already holds a node with that hash key, returns the cached node.
4. On a cache miss, constructs the real node with `id => $hash`, registers it in the cache, and calls `_register_consumers` to add the new node to the `consumers` list of each input.

This protocol guarantees that any two calls to `make()` with the same operation and the same input nodes return the exact same Perl object.

### `make_cfg($op_name, %args)`

Creates a new, non-deduplicated CFG node.

1. Looks up the target class in `%CFG_CLASSES` by `$op_name`. Dies if unknown.
2. Increments an internal `$cfg_counter`.
3. Constructs the node with `id => "${op_name}#${cfg_counter}"` and calls `_register_consumers`.

Each call to `make_cfg()` produces a distinct node, even if the arguments are identical. This is correct: two `If` nodes in the same graph are different branch points.

### Consumer Registration

`_register_consumers($node, %args)` iterates `args{inputs}`, and for each input node (or each element of a nested arrayref input), calls `$input->add_consumer($node)`. This wires the bidirectional use-def chain at construction time.

When a `Loop` node's back edge is set via `set_backedge_ctrl()`, or a `Phi` node's back value is set via `set_backedge()`, the old input's consumer record is removed via `remove_consumer()` and the new input is registered. This is the only post-construction mutation permitted.

### `reset_for_testing()`

The factory is a regular Perl object; tests that need a clean cache simply instantiate a new `Chalk::IR::NodeFactory` object. There is no global singleton to reset.

### Per-parse ownership

A `NodeFactory` is a per-parse instance. `Chalk::Bootstrap::Perl::Actions` allocates a fresh one in its `ADJUST` and injects it into `SemanticAction` via `set_factory($f)`. `_one_ctx` reads the injected factory and seeds the parse's root `Context` with it; from there, `Context.extend` propagates it to every derived context.

In addition, each `MOP::Method`, `MOP::Sub`, and `MOP::Phaser` owns its own `NodeFactory` — node identity is meaningful only within that owner's body. See `mop-layer.md` for how the MOP carves up factory ownership per method/sub/phaser.

Cross-parse and cross-method comparison is by `content_hash`, not refaddr.

---

## Graph Container

`Chalk::IR::Graph` is the per-method computation graph. It records the graph's entry and exit nodes and provides topological traversal.

### Fields

| Field | Description |
|-------|-------------|
| `%cache` | The hash-cons table for this graph: `node id` (or `content_hash` for data nodes) → node. Populated by `merge()` and the constructor seeding logic. The cache scopes hash consing per-graph: consumer lists cannot leak across graphs because each graph hash-conses its own nodes. |
| `$cfg_counter` | Sequential ID allocator for CFG nodes (`If`, `Proj`, `Region`, `Loop`, `Start`, `Return`, `Unwind`). CFG nodes are never hash-consed; each call to `make_cfg` produces a distinct node with a fresh sequential id. |
| `schedule` | Hashref reserved for scheduling information populated by later optimization passes. Not used by the base graph. |

Legacy callers may pass `start` and `returns` arrayrefs at construction time; the constructor seeds the cache with those nodes and otherwise discards the parameters. New code constructs an empty graph and accumulates via `merge()`.

### `nodes()`

Returns an arrayref of all nodes in the graph in topological order (inputs before consumers).

`nodes()` traverses both edge directions from every node in the graph's `%cache`:

- **Inputs** are followed unconditionally. Transitive inputs of cached nodes appear in the result even if they were not separately merged in — this preserves the legacy input-closure behavior.
- **Consumers** are followed only when the consumer is itself in `%cache`. This is a membership filter: a node's `consumers` list can reach nodes that were built by losing Earley alternatives and never merged in, or — historically — nodes that lived in foreign graphs. Both kinds of pointer must not appear in the result.

A consumer is considered "in cache" when either its `id` or its `content_hash` appears as a key in the graph's `%cache`. The dual-key check handles both CFG nodes (registered by sequential id) and data nodes (registered by content hash).

This bidirectional traversal is what gives `nodes()` its completeness guarantee for a correctly constructed graph: data dependencies feeding the exits are reached via `inputs` from `returns`, and side-effect nodes whose values are unused (`VarDecl`, `Assign`, `Call`, ...) are reached via `consumers` from `Start` along the control-token chain.

**DFS post-order.** A recursive DFS collects nodes in post-order, visiting `inputs` first and then the cache-filtered `consumers`. Because post-order places each node after all of its predecessors, the result is a valid topological ordering: if A is an input to B, A appears before B.

**Per-parse correctness.** The membership filter is load-bearing because hash consing is per-factory but a node may be reachable from multiple factories. The Bootstrap singleton's process-wide cache (now retired) made this concrete: shared constants like `Start` accumulated consumers from every parse. With per-parse factory ownership (see `mop-layer.md`) the filter still matters — losing Earley alternatives produce orphan nodes that share a factory with surviving alternatives, and only the survivors' nodes belong in the result.

The `Chalk::IR::Serialize::JSON` module uses a refined version of this traversal (`_all_nodes_topo`) that also ensures `Region` nodes referenced by `Phi.region` appear before their `Phi` nodes, since `Phi.region` is not an `inputs` edge.

---

## Program Structure

A parsed Perl program has two parallel structural views:

1. **Metadata structs** (this section). A hierarchy rooted at `Chalk::IR::Program` with `ClassInfo`, `MethodInfo`, `SubInfo`, `UseInfo`, `FieldInfo` records. These structs are still produced during parsing and are still what the code generators consume today.
2. **MOP layer.** A parallel hierarchy rooted at `Chalk::MOP` with `MOP::Class`, `MOP::Method`, `MOP::Sub`, `MOP::Field`, `MOP::Phaser` instances. Each method/sub/phaser owns its own `Graph` and `NodeFactory`. See `mop-layer.md`.

The MOP is the canonical post-parse representation; migration of codegen to read from it directly is tracked in `docs/plans/2026-04-21-chalk-mop-migration-plan.md`. Until that lands, both representations coexist by design and are populated in parallel by the SemanticAction pass.

The remainder of this section describes the metadata struct shape. These structs are not hash-consed and do not participate in the use-def chain. They provide an `id()` method and a no-op `add_consumer()` method so that they can appear as inputs inside hash-consed constructor nodes without breaking the factory protocol.

### `Chalk::IR::Program`

The top-level container.

| Field | Description |
|-------|-------------|
| `use_decls` | Ordered list of `UseInfo` objects for `use`/`no` declarations. |
| `classes` | Ordered list of `ClassInfo` objects for class declarations. |
| `top_level_subs` | Ordered list of `SubInfo` objects for top-level subroutines. |
| `other_stmts` | Bare computation nodes at the top level. In well-formed production programs this is always empty; present to accommodate test snippets. |

### `Chalk::IR::ClassInfo`

Metadata for a single class declaration.

| Field | Description |
|-------|-------------|
| `name` | Class name string. |
| `parent` | Parent class name string, or `undef`. |
| `fields` | Ordered list of `FieldInfo` objects. |
| `methods` | Ordered list of `MethodInfo` objects. |
| `subs` | Ordered list of `SubInfo` objects for lexically-scoped subs inside the class. |
| `body` | All body items in source order (union of `fields`, `methods`, `subs`, and ADJUST blocks). **Transitional**: parallel state to the typed collections above, scheduled for removal once the program-level graph (D3) preserves source order via graph edges. See `docs/plans/2026-04-04-son-ir-polymorphic-migration.md`. |

### `Chalk::IR::MethodInfo`

Metadata for a method declaration, with an optional per-method computation graph.

| Field | Description |
|-------|-------------|
| `name` | Method name string. |
| `params` | Ordered list of parameter names. |
| `return_type` | Optional declared return type string. |
| `body` | Ordered list of statement IR nodes. **Transitional**: scheduled for removal once codegen migrates to walking the `graph` instead; see `docs/plans/2026-04-04-son-ir-polymorphic-migration.md` Outstanding Work. |
| `graph` | `Chalk::IR::Graph` for the method body. Once `body` is removed, this is the sole representation. |

### `Chalk::IR::SubInfo`

Metadata for a subroutine declaration. Similar to `MethodInfo` but adds a `scope` field.

| Field | Description |
|-------|-------------|
| `name` | Subroutine name string. |
| `params` | Ordered list of parameter names. |
| `scope` | One of `'my'`, `'our'`, or `'package'`. |
| `body` | Ordered list of statement IR nodes. |
| `graph` | Optional `Chalk::IR::Graph` for the sub body. |

### `Chalk::IR::FieldInfo`

Metadata for a class field declaration.

| Field | Description |
|-------|-------------|
| `name` | Field name string (including sigil, e.g., `$count`). |
| `attributes` | Ordered list of attribute descriptors. Each entry is either a plain string (e.g., `'reader'`) or a hashref with attribute parameters. |
| `default_value` | Optional default value node or scalar. |

### `Chalk::IR::UseInfo`

Metadata for a `use` or `no` declaration.

| Field | Description |
|-------|-------------|
| `name` | Module name string. |
| `args` | List of import arguments. Entries may be node objects or plain scalars. |
| `keyword` | Either `'use'` or `'no'`. Defaults to `'use'`. |

### Structure Diagram

```
Program
  |- use_decls: [UseInfo, ...]
  |- classes: [ClassInfo, ...]
  |    |- name, parent
  |    |- fields:  [FieldInfo, ...]
  |    |- methods: [MethodInfo, ...]
  |    |    |- name, params, return_type
  |    |    |- graph: Graph
  |    |         |- start: Start
  |    |         |- returns: [Return, ...]
  |    |         |- (nodes floating in the sea)
  |    |- subs: [SubInfo, ...]
  |         |- name, params, scope
  |         |- graph: Graph
  |- top_level_subs: [SubInfo, ...]
```

---

## JSON Serialization

`Chalk::IR::Serialize::JSON` provides `to_json(\%named_graphs)` and `from_json($json_string)` for serializing and deserializing named sets of `Chalk::IR::Graph` objects. The serialized format is compatible with the `perl5-son` B::SoN JSON schema.

### Schema

The top-level JSON object has three keys:

```json
{
  "version": 1,
  "source": null,
  "methods": {
    "method_name": { ... },
    ...
  }
}
```

Each method value is a graph object:

```json
{
  "nodes": [ ... ],
  "start": 0,
  "returns": [3]
}
```

Each node entry:

```json
{
  "id": 0,
  "op": "Start",
  "inputs": [],
  "cfg": true
}
```

```json
{
  "id": 2,
  "op": "Constant",
  "inputs": [],
  "fields": { "const_type": "string", "value": "hello" }
}
```

The `"cfg"` key is present and `true` only on CFG nodes. The `"fields"` key is present only on nodes that carry extra scalar fields beyond their inputs.

### Positional ID Remapping

Node IDs in the serialized format are positional integers (0, 1, 2, ...) assigned in topological order, not the internal content-hash strings. This keeps the serialized representation compact and stable. The remapping is computed during serialization and used for all input references and for the `Phi.region` field reference.

During deserialization, nodes are reconstructed in the same positional order. Each node's inputs are resolved by indexing into the already-built node array. The positional scheme ensures forward references are never needed (inputs always have smaller indices than their consumers in topological order).

### Phi Region Ordering

The base `Graph.nodes()` traversal follows `inputs` edges plus cache-filtered `consumers` edges in its DFS. Because `Phi.region` is neither an `inputs` edge nor a `consumers` edge — it is a separate reference field — a `Region` node may appear after its dependent `Phi` in the base traversal. The serializer's `_all_nodes_topo()` function corrects this by collecting all `Phi.region` references, appending any that are not already in the base node list, and re-running a full DFS that treats the `Phi.region` reference as an additional predecessor edge. This guarantees that every `Region` node is assigned a positional ID smaller than the `Phi` nodes that reference it.

### Field Handling Differences from perl5-son

Chalk's `RegexMatch` and `RegexSubst` nodes carry `pattern` and `flags` as node-level fields (not as input edges). The perl5-son schema also includes these fields, so they serialize and deserialize correctly. However, the `from_json` deserializer silently drops unrecognized fields for known operation types, which allows Chalk to load graphs produced by perl5-son that include fields not yet implemented on the Chalk side. Unknown operation types cause `NodeFactory` to raise a fatal error.

---

## Relationship to perl5-son

Chalk's Sea of Nodes IR and the `perl5-son` B::SoN backend have been aligned to enable cross-load validation: a program can be compiled to a `B::SoN` JSON document by perl5-son and loaded as a `Chalk::IR::Graph` by Chalk, and vice versa.

### Node Count Parity

As of the most recent alignment milestone, perl5-son defines 70 operation types and Chalk defines 74 concrete operation types plus 5 intermediate base classes (`BinOp`, `UnaryOp`, `Access`, `Aggregate`, `Regex`) for 79 total `.pm` files under `lib/Chalk/IR/Node/`. The gap against perl5-son consists primarily of Chalk-specific optimization nodes (`StructRef`, `StructFieldAccess`) and the intermediate base classes, which perl5-son folds into broader categories.

### Cross-Load Validation

The cross-load test suite (`t/cross-load/`) validates that:

1. Every operation type emitted by `B::SoN` into a JSON document is recognized by Chalk's `from_json` deserializer.
2. Every `Chalk::IR::Graph` produced by Chalk's parser can be serialized to JSON and deserialized back to an equivalent graph (round-trip identity within the same process).

25 tests in the cross-load suite confirm that B::SoN JSON documents load into Chalk IR with zero unsupported operation types.

### JSON Schema Compatibility

Both Chalk and perl5-son use the same top-level schema (`version`, `source`, `methods`), the same node entry format (`id`, `op`, `inputs`, optional `cfg`, optional `fields`), and the same positional ID scheme. The field names within `fields` objects match between the two implementations for all shared operation types.

---

## Optimization Opportunities

The Sea of Nodes representation supports several optimization passes that operate on the graph before code generation:

**Constant folding.** A `BinOp` node whose both inputs are `Constant` nodes can be replaced by a single `Constant` node at graph construction time. Hash consing ensures the folded constant is shared with any other occurrence of the same value.

**Dead code elimination.** Any data node not reachable backward from a `Return` node's value input contributes no output. Such nodes can be removed. The use-def chains (consumers lists) make reachability straightforward to compute.

**Global Code Motion (GCM).** Because data nodes carry no inherent block membership, they can be moved to any point in the schedule that satisfies their data dependences. GCM (Click 1995b) finds the earliest and latest legal schedule for each node and places it optimally.

**StructPromotion.** Hash references whose keys are statically known can be promoted to typed structs. The `StructRef` and `StructFieldAccess` nodes represent the output of this promotion pass, enabling the XS code generator to emit direct struct field accesses rather than hash lookups.

---

## References

- Click, Cliff and Michael Paleczny. "A Simple Graph-Based Intermediate Representation." ACM SIGPLAN Workshop on Intermediate Representations (IR '95), 1995.
- Click, Cliff. "Global Code Motion / Global Value Numbering." *Proceedings of the ACM SIGPLAN Conference on Programming Language Design and Implementation (PLDI)*, 1995.
- Cliff Click and Keith D. Cooper, "Combining Analyses, Combining Optimizations," ACM TOPLAS 17(2), 1995.
- Jean-Christophe Filliatre and Sylvain Conchon, "Type-Safe Modular Hash-Consing," ML Workshop 2006.
