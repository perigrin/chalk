# Sea of Nodes IR: Node Type Taxonomy

> **Scope:** This document describes an early, 4-node IR used only for
> compiling the BNF meta-grammar. The production IR has ~76 node types;
> see [`architecture/sea-of-nodes-ir.md`](architecture/sea-of-nodes-ir.md)
> for the current taxonomy. For the Chalk project as a whole, see
> [`../README.md`](../README.md).

## Overview

The Chalk::Bootstrap IR uses a "Sea of Nodes" representation where the program is a directed graph of operations with explicit data-flow edges. This document specifies the 4 node types needed for grammar compilation.

## Design Principles

1. **Hash Consing**: Identical nodes (same operation, same inputs) share a single object
2. **Immutability**: Nodes cannot be mutated after construction
3. **Use-Def Chains**: Each node tracks producers (inputs) and consumers (uses)
4. **Explicit Control Flow**: Start/Return nodes mark entry/exit points
5. **Deterministic IDs**: Node IDs derived from content, not creation order

## Node Type Taxonomy

### 1. Start

**Purpose**: Graph entry point. Marks the beginning of grammar compilation.

**Inputs**: None (root node)

**Outputs**: Control edge to first operation

**Attributes**: None

**Example**:
```
Start → Constructor(class='Rule', name="Grammar", ...)
```

### 2. Return

**Purpose**: Graph exit point. Marks the final value produced by compilation.

**Inputs**:
- Control edge from last operation
- Data edge from value to return

**Outputs**: None (sink node)

**Attributes**:
- `value`: The IR node being returned (typically a `Constructor(class='Rule')` or list of rules)

**Example**:
```
Constructor(class='Rule', ...) → Return(value=...)
```

### 3. Constant

**Purpose**: Represents a compile-time constant value (string, number, or enum).

**Inputs**: None

**Outputs**: Data edges to consumers

**Attributes**:
- `type`: 'string', 'integer', or 'enum'
- `value`: The actual constant value

**Example**:
```
Constant(type='string', value='Identifier')
Constant(type='enum', value='reference')
```

**Usage**: Rule names, symbol types, quantifier values, regex patterns.

### 4. Constructor

**Purpose**: Constructs grammar objects (Symbol, Expression, or Rule) with a parameterized class field.

**Attributes**:
- `class`: One of 'Symbol', 'Expression', or 'Rule' (determines which type to construct)

**Inputs** (vary by class):

#### Constructor(class='Symbol')
- `type`: Constant ('reference' or 'terminal')
- `value`: Constant (string)
- `quantifier`: Optional Constant ('*', '+', '?', or undef)

**Outputs**: Symbol object (consumed by Constructor(class='Expression'))

**Example**:
```
Constant('reference') →┐
Constant('Atom')       →├→ Constructor(class='Symbol') → (output)
Constant('+')          →┘
```

**Generated code**:
```perl
Chalk::Grammar::Symbol->new(
    type       => 'reference',
    value      => 'Atom',
    quantifier => '+',
)
```

#### Constructor(class='Expression')
- `elements`: List of Constructor(class='Symbol') nodes (ordered)

**Outputs**: Expression (array of Symbols, consumed by Constructor(class='Rule'))

**Example**:
```
Constructor(class='Symbol', Atom) →┐
Constructor(class='Symbol', Quantifier) →├→ Constructor(class='Expression') → (output)
                                      →┘
```

**Generated code**:
```perl
[$atom_symbol, $quantifier_symbol]
```

#### Constructor(class='Rule')
- `name`: Constant (string)
- `expressions`: List of Constructor(class='Expression') nodes (one per alternative)

**Outputs**: Rule object (consumed by Return or collected into Grammar)

**Example**:
```
Constant('Element') →┐
Constructor(class='Expression', ...) →├→ Constructor(class='Rule') → (output)
Constructor(class='Expression', ...) →┘
```

**Generated code**:
```perl
Chalk::Grammar::Rule->new(
    name        => 'Element',
    expressions => [$expr1, $expr2],
)
```

## Graph Structure Example

For the rule: `Element ::= Atom Quantifier?`

```
Start
  ↓
Constant('Element') ────────────┐
                                ↓
Constant('reference') ──┐     Constructor(class='Rule')
Constant('Atom')       ──┤       ↓
Constant(undef)         ─┴→ Constructor(class='Symbol') ──┐
                                          ↓
Constant('reference')  ──┐            Constructor(class='Expression')
Constant('Quantifier') ──┤               ↓
Constant('?')           ─┴→ Constructor(class='Symbol') ──┘
                                          ↓
                                       Return
```

## Hash Consing Key Design

Hash keys are constructed from:
1. Operation type (node class name)
2. Input node IDs (stable, content-based)
3. Attribute values (for Constants)

**Example keys**:
```perl
"Constant|string|Identifier"
"Constructor|Symbol|$type_id|$value_id|$quant_id"
"Constructor|Expression|$elem1_id|$elem2_id"
"Constructor|Rule|$name_id|$expr1_id|$expr2_id"
```

**Ordering**: Input IDs must be in deterministic order (e.g., sorted for commutative operations, or source order for non-commutative).

## Use-Def Chain Tracking

Each node maintains:

**Producers** (inputs): Nodes that produce values consumed by this node
**Consumers** (uses): Nodes that consume values produced by this node

**Example**:
```perl
my $const = Constant->new(type => 'string', value => 'Atom');
my $symbol = Constructor->new(class => 'Symbol', type => $const, ...);

# Use-def chain:
$const->consumers;  # [$symbol]
$symbol->producers; # [$const, ...]
```

**Usage**: Used by dead code elimination (DCE) to remove unused nodes.

## Code Generation Strategy

### Traversal Order

1. Topological sort from Return nodes backward (reverse postorder)
2. For each node, emit code to construct the value
3. Store intermediate values in lexical variables

### Variable Naming

- Constants: `$const_<ID>`
- Constructor(class='Symbol'): `$sym_<ID>`
- Constructor(class='Expression'): `$expr_<ID>`
- Constructor(class='Rule'): `$rule_<ID>`

Where `<ID>` is the stable content-based node ID.

### Deduplication

Hash consing ensures that identical sub-expressions are computed only once:

```perl
# These two symbols share the same type constant
my $const_type = Constant('reference');
my $sym1 = Constructor(class='Symbol', type=$const_type, ...);
my $sym2 = Constructor(class='Symbol', type=$const_type, ...);

# Generated code computes $const_type once:
my $const_123 = 'reference';
my $sym_456 = make_constructor('Symbol', $const_123, ...);
my $sym_789 = make_constructor('Symbol', $const_123, ...);
```

## Optimization Opportunities

### Peephole Optimizations

- **Constant folding**: Constructor(class='Symbol') with all constant inputs → pre-compute
- **Identity elimination**: Constructor(class='Expression') with single element → unwrap
- **Dead code elimination**: Remove nodes unreachable from Return

### Global Code Motion (GCM)

- **Early scheduling**: Hoist loop-invariant computations (not applicable to grammar compilation)
- **Late scheduling**: Delay computations until needed (reduces register pressure)

**Note**: GCM is less critical for grammar compilation (no loops), but included for completeness.

## Implementation Notes

### Circular References

Grammar rules can reference each other cyclically (e.g., left/right recursion). The IR must handle this:

1. **Forward references**: Use two-pass construction if needed
2. **Hash keys use IDs**: Not object references (avoid infinite loops)
3. **Document cycles**: If optimizer cannot handle cycles, document limitation

### Testing Strategy

Create `t/bootstrap/ir-hash-consing.t`:
- Construct duplicate nodes, verify same reference
- Verify hash keys are deterministic
- Verify use-def chains are bidirectional

Create `t/bootstrap/ir-use-def.t`:
- Build small graphs manually
- Verify producer/consumer tracking
- Test DCE removes unreachable nodes

## References

- **Sea of Nodes**: Cliff Click, "A Simple Graph-Based Intermediate Representation" (1995)
- **Hash Consing**: Filliatre & Conchon, "Type-Safe Modular Hash-Consing" (2006)
- **Global Code Motion**: Click & Cooper, "Combining Analyses, Combining Optimizations" (1995)
