# Chapter 4 Compliance: Native Bool, TypeTuple, and @ARGV Support

**Date:** 2025-11-30
**Status:** Design Complete
**Reference:** https://github.com/SeaOfNodes/Simple/tree/main/chapter04

## Overview

This design brings Chalk into full compliance with Simple compiler Chapter 4 by implementing:

1. **Native Bool Type** - Comparison nodes return `builtin::true`/`builtin::false`
2. **TypeTuple** - Multi-return type for nodes that produce multiple values
3. **Start as MultiNode** - Returns `(ctrl, arg)` tuple
4. **@ARGV Support** - Single `$arg` parameter from `@ARGV[0]`

## Design Decisions

- **Single arg (like Simple)**: Start returns `(ctrl, arg)` where arg is `@ARGV[0]`
- **Native Booleans**: Comparisons return `builtin::true`/`builtin::false` that coerce appropriately
- **Full Chapter 4 Compliance**: TypeBool + TypeTuple + MultiNode Start

## IR Type Lattice Extension

The IR type lattice (used by `compute()` for optimization) will be extended:

```
         Top (unknown)
        /   |   \
  TypeTuple TypeBool TypeInteger
        \   |   /
       Bottom (error)
```

### TypeBool (`lib/Chalk/IR/Type/TypeBool.pm`)

```perl
use 5.42.0;
use experimental qw(class);
use builtin qw(true false);

class Chalk::IR::Type::TypeBool :isa(Chalk::IR::Type) {
    field $value :param :reader;

    method is_constant() { return 1; }

    # Singletons for constant true/false
    sub TRUE {
        state $singleton = __PACKAGE__->new(value => true);
        return $singleton;
    }

    sub FALSE {
        state $singleton = __PACKAGE__->new(value => false);
        return $singleton;
    }

    sub constant {
        my ($class, $val) = @_;
        return $val ? $class->TRUE : $class->FALSE;
    }
}
```

### TypeTuple (`lib/Chalk/IR/Type/TypeTuple.pm`)

```perl
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Type::TypeTuple :isa(Chalk::IR::Type) {
    field $types :param :reader;  # ArrayRef of types

    method is_constant() {
        for my $t ($types->@*) {
            return 0 unless $t->is_constant;
        }
        return 1;
    }

    method value() {
        return [ map { $_->value } $types->@* ];
    }

    method at($index) {
        return $types->[$index];
    }

    sub of {
        my ($class, @types) = @_;
        return $class->new(types => \@types);
    }
}
```

### TypeCtrl (`lib/Chalk/IR/Type/TypeCtrl.pm`)

```perl
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Type::TypeCtrl :isa(Chalk::IR::Type) {
    method is_constant() { return 1; }
    method value() { return undef; }  # Control has no data value

    sub CTRL {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }
}
```

## Start as MultiNode

### Start Node Changes (`lib/Chalk/IR/Node/Start.pm`)

```perl
class Chalk::IR::Node::Start {
    field $arg_value :param :reader = undef;  # @ARGV[0] passed at construction
    field $label :param :reader = undef;

    method op() { 'Start' }
    method is_multi() { return 1; }

    method compute() {
        use Chalk::IR::Type::TypeTuple;
        use Chalk::IR::Type::TypeCtrl;
        use Chalk::IR::Type::TypeInteger;

        my $arg_type = defined($arg_value)
            ? Chalk::IR::Type::TypeInteger->constant($arg_value)
            : Chalk::IR::Type::Top->top();  # Unknown if no arg provided

        return Chalk::IR::Type::TypeTuple->of(
            Chalk::IR::Type::TypeCtrl->CTRL,
            $arg_type
        );
    }
}
```

### Proj Node Update (`lib/Chalk/IR/Node/Proj.pm`)

```perl
method compute() {
    my $source_type = $source->compute();

    # Extract type at index from tuple
    if ($source_type->can('at')) {
        return $source_type->at($index);
    }

    return Chalk::IR::Type::Top->top();
}
```

### Program.pm Integration

```perl
# Create Start with @ARGV[0]
my $start = Chalk::IR::Node::Start->new(
    label => 'main',
    arg_value => $ARGV[0]
);

# Create Proj nodes to extract ctrl and arg
my $ctrl = Chalk::IR::Node::Proj->new(
    source => $start,
    index => 0,
    label => 'ctrl'
);
my $arg = Chalk::IR::Node::Proj->new(
    source => $start,
    index => 1,
    label => 'arg'
);

# Bind $arg to initial scope
$scope = $scope->with_binding('$arg', $arg);
$scope = $scope->with_control($ctrl);
```

## Comparison Nodes with Native Bool

All comparison nodes (GT, LT, EQ, NE, LE, GE) will return native booleans:

### Example: GT Node Update

```perl
use builtin qw(true false);

method execute($context) {
    my $left_val = $context->("node:" . $left->id);
    my $right_val = $context->("node:" . $right->id);
    return ($left_val > $right_val) ? true : false;
}

method compute() {
    my $left_type = $left->compute();
    my $right_type = $right->compute();

    if ($left_type->is_constant && $right_type->is_constant) {
        my $result = $left_type->value > $right_type->value;
        return Chalk::IR::Type::TypeBool->constant($result);
    }

    return Chalk::IR::Type::Top->top();
}

method peephole($graph = undef) {
    my $type = $self->compute();
    if ($type->is_constant) {
        return Chalk::IR::Node::Constant->new(
            value => $type->value,
            type  => 'Bool',
        );
    }
    return $self;
}
```

### Not Node Update

```perl
use builtin qw(true false);

method execute($context) {
    my $operand_val = $context->("node:" . $operand->id);
    return $operand_val ? false : true;
}

method compute() {
    my $operand_type = $operand->compute();
    if ($operand_type->is_constant) {
        my $result = $operand_type->value ? false : true;
        return Chalk::IR::Type::TypeBool->constant($result);
    }
    return Chalk::IR::Type::Top->top();
}
```

### Constant Node Enhancement

Support `type => 'Bool'` with `builtin::true`/`builtin::false` values:

```perl
method compute() {
    if ($type eq 'Bool') {
        return Chalk::IR::Type::TypeBool->constant($value);
    }
    return Chalk::IR::Type::TypeInteger->constant($value);
}
```

## Files to Create

| File | Purpose |
|------|---------|
| `lib/Chalk/IR/Type/TypeBool.pm` | Bool type with `builtin::true`/`builtin::false` |
| `lib/Chalk/IR/Type/TypeTuple.pm` | Tuple type for multi-return nodes |
| `lib/Chalk/IR/Type/TypeCtrl.pm` | Control token type (singleton) |
| `t/sea-of-nodes/ir-type-bool.t` | TypeBool unit tests |
| `t/sea-of-nodes/ir-type-tuple.t` | TypeTuple unit tests |
| `t/sea-of-nodes/chapter04.t` | Chapter 4 integration tests |

## Files to Modify

| File | Changes |
|------|---------|
| `lib/Chalk/IR/Type.pm` | Add abstract `meet()` method |
| `lib/Chalk/IR/Node/Start.pm` | Add `arg_value`, `is_multi()`, update `compute()` |
| `lib/Chalk/IR/Node/Proj.pm` | Update `compute()` to extract from tuple |
| `lib/Chalk/IR/Node/Constant.pm` | Support `type => 'Bool'` |
| `lib/Chalk/IR/Node/GT.pm` | Return native bool, TypeBool compute |
| `lib/Chalk/IR/Node/LT.pm` | Same |
| `lib/Chalk/IR/Node/EQ.pm` | Same |
| `lib/Chalk/IR/Node/NE.pm` | Same |
| `lib/Chalk/IR/Node/LE.pm` | Same |
| `lib/Chalk/IR/Node/GE.pm` | Same |
| `lib/Chalk/IR/Node/Not.pm` | Return native bool, TypeBool compute |
| `lib/Chalk/Grammar/Chalk/Rule/Program.pm` | Create Proj nodes, bind `$arg` |
| `t/sea-of-nodes/comparison-nodes.t` | Add native bool tests |
| `t/sea-of-nodes/compute.t` | Add TypeBool tests |

## Testing Strategy

### New Test Files

1. **`t/sea-of-nodes/ir-type-bool.t`**
   - `TypeBool->TRUE` and `TypeBool->FALSE` singletons
   - `is_constant()` returns true
   - `value()` returns `builtin::true`/`builtin::false`

2. **`t/sea-of-nodes/ir-type-tuple.t`**
   - `TypeTuple->of($type1, $type2)` construction
   - `at($index)` extraction
   - `is_constant()` only when all elements constant

3. **`t/sea-of-nodes/chapter04.t`**
   - Start returns tuple `(ctrl, arg)`
   - Proj extracts ctrl (index 0) and arg (index 1)
   - `$arg` available in initial scope
   - Comparison nodes return native booleans
   - Constant folding: `$arg > 5` with known arg folds to bool constant

### Test Data

```perl
# Chapter 4 canonical test case
my $code = 'return $arg > 5;';
# With $arg = 10: folds to Constant(true)
# With $arg = 3:  folds to Constant(false)
# With $arg unknown: GT node remains
```

## Benefits

1. **Full Chapter 4 Compliance** - Matches Simple compiler design exactly
2. **Native Perl Booleans** - `builtin::is_bool()` returns true, natural coercion
3. **Future-Proof** - TypeTuple enables multi-return functions later
4. **@ARGV Integration** - Programs can accept command-line input

## Related Issues

- Enables future implementation of Chapter 5+ features
- Aligns with `docs/perl-types-practical.md` Bool documentation
