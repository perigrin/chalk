# compute() Method Design for Sea of Nodes Chapter 2 Parity

## Overview

Add `compute()` method to IR nodes enabling compile-time type analysis and constant folding via `peephole()`. This achieves parity with SeaOfNodes/Simple chapter02.

## Background

Simple's chapter02 introduces:
- Type lattice: TOP (unknown) -> constants -> BOTTOM (error)
- `compute()` method on nodes returning Type
- `peephole()` using compute() for constant folding
- Example: `Add(Constant(1), Constant(2))` folds to `Constant(3)`

Chalk currently has:
- Semantic-level types (`Chalk::Grammar::Chalk::Type::*`) - NOT for IR
- `peephole($graph)` stub returning `$self` - NOT IMPLEMENTED
- No `compute()` method

## Design Decision

**Approach:** Minimal Simple-match - create IR-level type system separate from semantic types.

**Rationale:** Chalk::Type objects are semantic-level (language types). IR optimization needs its own type lattice for compile-time analysis.

## IR Type System

### New Classes

**`lib/Chalk/IR/Type.pm`** - Base class
```perl
class Chalk::IR::Type {
    method is_constant() { return 0; }
    method value() { die "Not a constant"; }
}
```

**`lib/Chalk/IR/Type/Top.pm`** - Unknown value (e.g., function parameter)
```perl
class Chalk::IR::Type::Top :isa(Chalk::IR::Type) {
    my $TOP;
    sub TOP { $TOP //= __CLASS__->new() }
}
```

**`lib/Chalk/IR/Type/Bottom.pm`** - Error state (e.g., division by zero)
```perl
class Chalk::IR::Type::Bottom :isa(Chalk::IR::Type) {
    my $BOTTOM;
    sub BOTTOM { $BOTTOM //= __CLASS__->new() }
}
```

**`lib/Chalk/IR/Type/TypeInteger.pm`** - Constant integer
```perl
class Chalk::IR::Type::TypeInteger :isa(Chalk::IR::Type) {
    field $value :param :reader;
    method is_constant() { return 1; }
    sub constant($class, $val) { $class->new(value => $val) }
}
```

## compute() Method

### Base Implementation

**In `Chalk::IR::Node::Base`:**
```perl
method compute() {
    return Chalk::IR::Type::Top->TOP;  # Unknown by default
}
```

### Constant Node

**In `Chalk::IR::Node::Constant`:**
```perl
method compute() {
    return Chalk::IR::Type::TypeInteger->constant($value);
}
```

### Arithmetic Nodes

**Pattern for Add, Subtract, Multiply, Divide:**
```perl
method compute() {
    my $left_type  = $left->compute();
    my $right_type = $right->compute();

    # Propagate BOTTOM
    return Chalk::IR::Type::Bottom->BOTTOM
        if $left_type isa Chalk::IR::Type::Bottom
        || $right_type isa Chalk::IR::Type::Bottom;

    # Fold constants
    if ($left_type->is_constant && $right_type->is_constant) {
        return Chalk::IR::Type::TypeInteger->constant(
            $left_type->value + $right_type->value  # operator varies
        );
    }

    return Chalk::IR::Type::Top->TOP;
}
```

**Divide special case:** Return BOTTOM if right operand is constant 0.

**Negate (unary):**
```perl
method compute() {
    my $operand_type = $operand->compute();

    return Chalk::IR::Type::Bottom->BOTTOM
        if $operand_type isa Chalk::IR::Type::Bottom;

    if ($operand_type->is_constant) {
        return Chalk::IR::Type::TypeInteger->constant(-$operand_type->value);
    }

    return Chalk::IR::Type::Top->TOP;
}
```

## peephole() Integration

**Pattern for arithmetic nodes:**
```perl
method peephole($graph) {
    my $type = $self->compute();

    if ($type->is_constant) {
        return Chalk::IR::Node::Constant->new(
            value => $type->value,
            type  => 'Int',
        );
    }

    return $self;
}
```

## Files to Create

| File | Purpose |
|------|---------|
| `lib/Chalk/IR/Type.pm` | Base class with is_constant(), value() |
| `lib/Chalk/IR/Type/Top.pm` | TOP singleton for unknown values |
| `lib/Chalk/IR/Type/Bottom.pm` | BOTTOM singleton for errors |
| `lib/Chalk/IR/Type/TypeInteger.pm` | Constant integers with value |
| `t/sea-of-nodes/ir-type.t` | Unit tests for IR Type classes |

## Files to Modify

| File | Changes |
|------|---------|
| `lib/Chalk/IR/Node/Base.pm` | Add default compute() returning TOP |
| `lib/Chalk/IR/Node/Constant.pm` | Add compute() returning TypeInteger |
| `lib/Chalk/IR/Node/Add.pm` | Add compute(), update peephole() |
| `lib/Chalk/IR/Node/Subtract.pm` | Add compute(), update peephole() |
| `lib/Chalk/IR/Node/Multiply.pm` | Add compute(), update peephole() |
| `lib/Chalk/IR/Node/Divide.pm` | Add compute(), update peephole(), div-by-zero |
| `lib/Chalk/IR/Node/Negate.pm` | Add compute(), update peephole() |
| `t/sea-of-nodes/chapter02.t` | Remove TODO markers from constant folding tests |

## Testing Strategy

1. **Unit tests for IR Types** (`t/sea-of-nodes/ir-type.t`):
   - TOP/BOTTOM singletons work
   - TypeInteger.constant() creates correct instances
   - is_constant() returns correct values
   - value() returns stored value

2. **compute() tests** (in chapter02.t):
   - Constant nodes return TypeInteger
   - Add/Sub/Mul/Div with constants return folded TypeInteger
   - Mixed constant/non-constant returns TOP
   - Division by zero returns BOTTOM

3. **peephole() integration tests** (in chapter02.t):
   - `Add(Const(1), Const(2)).peephole()` returns `Const(3)`
   - Non-constant expressions return self unchanged

## Success Criteria

- [ ] All existing tests pass
- [ ] `t/sea-of-nodes/ir-type.t` passes
- [ ] `t/sea-of-nodes/chapter02.t` constant folding tests pass (remove TODO)
- [ ] `1 + 2` parsed and peepholed produces `Constant(3)`
