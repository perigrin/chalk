# Type Inference Infrastructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add type annotations to IR nodes and implement scalar type inference rules.

**Architecture:** Extend IR nodes with computed `$type` field. Type inference runs during IR construction, using TypeLattice to determine result types from operand types. Numeric ops → Int/Num, string ops → Str, unknown → Any.

**Tech Stack:** Perl 5.42, Object::Pad classes, existing Chalk::IR::Type::* and Chalk::Grammar::Chalk::Type::* hierarchies.

**Related Issues:** #300, #336, #332

---

## Task 1: Add compute_type() to Add Node

**Files:**
- Modify: `lib/Chalk/IR/Node/Add.pm`
- Test: `t/ir/node-types.t` (create)

**Step 1: Write the failing test**

Create `t/ir/node-types.t`:

```perl
# ABOUTME: Tests for IR node type computation
# ABOUTME: Validates that operation nodes can compute their result types

use 5.042;
use Test::More;
use lib 'lib';

use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Type::Integer;

subtest 'Add node computes type from operands' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $add = Chalk::IR::Node::Add->new(
        left  => $left,
        right => $right,
    );

    ok($add->can('compute_type'), 'Add has compute_type method');
    my $result_type = $add->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Integer', 'Add of integers yields Integer');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/node-types.t`
Expected: FAIL - "Add has compute_type method" fails

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Add.pm` after the existing fields:

```perl
use Chalk::IR::Type::Integer;

method compute_type() {
    my $left_type = $left->can('compute_type') ? $left->compute_type() : $left->type;
    my $right_type = $right->can('compute_type') ? $right->compute_type() : $right->type;

    # Integer + Integer = Integer
    if ($left_type isa Chalk::IR::Type::Integer && $right_type isa Chalk::IR::Type::Integer) {
        return Chalk::IR::Type::Integer->TOP();
    }

    # Default to Integer for now
    return Chalk::IR::Type::Integer->TOP();
}
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/node-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add t/ir/node-types.t lib/Chalk/IR/Node/Add.pm
git commit -m "feat(ir): Add compute_type() to Add node

Implements type inference for addition - Integer + Integer = Integer.
Part of #300."
```

---

## Task 2: Add Float Type Support to Add

**Files:**
- Modify: `lib/Chalk/IR/Node/Add.pm`
- Modify: `t/ir/node-types.t`

**Step 1: Write the failing test**

Add to `t/ir/node-types.t`:

```perl
subtest 'Add with Float operand yields Float' => sub {
    use Chalk::IR::Type::Float;

    my $int_const = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $float_const = Chalk::IR::Node::Constant->new(
        value => 2.5,
        type  => Chalk::IR::Type::Float->constant(2.5),
    );

    my $add = Chalk::IR::Node::Add->new(
        left  => $int_const,
        right => $float_const,
    );

    my $result_type = $add->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Int + Float yields Float');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/node-types.t`
Expected: FAIL - result is Integer, not Float

**Step 3: Update implementation**

Update `compute_type()` in `lib/Chalk/IR/Node/Add.pm`:

```perl
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

method compute_type() {
    my $left_type = $left->can('compute_type') ? $left->compute_type() : $left->type;
    my $right_type = $right->can('compute_type') ? $right->compute_type() : $right->type;

    # If either operand is Float, result is Float
    if ($left_type isa Chalk::IR::Type::Float || $right_type isa Chalk::IR::Type::Float) {
        return Chalk::IR::Type::Float->TOP();
    }

    # Integer + Integer = Integer
    if ($left_type isa Chalk::IR::Type::Integer && $right_type isa Chalk::IR::Type::Integer) {
        return Chalk::IR::Type::Integer->TOP();
    }

    # Default to Float for numeric operations
    return Chalk::IR::Type::Float->TOP();
}
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/node-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Add.pm t/ir/node-types.t
git commit -m "feat(ir): Add Float type support to Add.compute_type()

Int + Float = Float, following Perl numeric coercion rules.
Part of #300."
```

---

## Task 3: Add compute_type() to Subtract, Multiply, Divide

**Files:**
- Modify: `lib/Chalk/IR/Node/Subtract.pm`
- Modify: `lib/Chalk/IR/Node/Multiply.pm`
- Modify: `lib/Chalk/IR/Node/Divide.pm`
- Modify: `t/ir/node-types.t`

**Step 1: Write failing tests**

Add to `t/ir/node-types.t`:

```perl
subtest 'Arithmetic nodes compute types' => sub {
    use Chalk::IR::Node::Subtract;
    use Chalk::IR::Node::Multiply;
    use Chalk::IR::Node::Divide;

    my $int1 = Chalk::IR::Node::Constant->new(
        value => 10,
        type  => Chalk::IR::Type::Integer->constant(10),
    );
    my $int2 = Chalk::IR::Node::Constant->new(
        value => 3,
        type  => Chalk::IR::Type::Integer->constant(3),
    );

    my $sub = Chalk::IR::Node::Subtract->new(left => $int1, right => $int2);
    ok($sub->can('compute_type'), 'Subtract has compute_type');
    isa_ok($sub->compute_type(), 'Chalk::IR::Type::Integer', 'Int - Int = Int');

    my $mul = Chalk::IR::Node::Multiply->new(left => $int1, right => $int2);
    ok($mul->can('compute_type'), 'Multiply has compute_type');
    isa_ok($mul->compute_type(), 'Chalk::IR::Type::Integer', 'Int * Int = Int');

    my $div = Chalk::IR::Node::Divide->new(left => $int1, right => $int2);
    ok($div->can('compute_type'), 'Divide has compute_type');
    # Division always produces Float (may have remainder)
    isa_ok($div->compute_type(), 'Chalk::IR::Type::Float', 'Int / Int = Float');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/node-types.t`
Expected: FAIL - nodes don't have compute_type

**Step 3: Implement compute_type for each node**

Add to `lib/Chalk/IR/Node/Subtract.pm`:

```perl
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

method compute_type() {
    my $left_type = $left->can('compute_type') ? $left->compute_type() : $left->type;
    my $right_type = $right->can('compute_type') ? $right->compute_type() : $right->type;

    if ($left_type isa Chalk::IR::Type::Float || $right_type isa Chalk::IR::Type::Float) {
        return Chalk::IR::Type::Float->TOP();
    }
    if ($left_type isa Chalk::IR::Type::Integer && $right_type isa Chalk::IR::Type::Integer) {
        return Chalk::IR::Type::Integer->TOP();
    }
    return Chalk::IR::Type::Float->TOP();
}
```

Add to `lib/Chalk/IR/Node/Multiply.pm`:

```perl
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

method compute_type() {
    my $left_type = $left->can('compute_type') ? $left->compute_type() : $left->type;
    my $right_type = $right->can('compute_type') ? $right->compute_type() : $right->type;

    if ($left_type isa Chalk::IR::Type::Float || $right_type isa Chalk::IR::Type::Float) {
        return Chalk::IR::Type::Float->TOP();
    }
    if ($left_type isa Chalk::IR::Type::Integer && $right_type isa Chalk::IR::Type::Integer) {
        return Chalk::IR::Type::Integer->TOP();
    }
    return Chalk::IR::Type::Float->TOP();
}
```

Add to `lib/Chalk/IR/Node/Divide.pm`:

```perl
use Chalk::IR::Type::Float;

method compute_type() {
    # Division always produces Float (may have fractional result)
    return Chalk::IR::Type::Float->TOP();
}
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/node-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Subtract.pm lib/Chalk/IR/Node/Multiply.pm lib/Chalk/IR/Node/Divide.pm t/ir/node-types.t
git commit -m "feat(ir): Add compute_type() to Subtract, Multiply, Divide

- Subtract/Multiply: Int op Int = Int, Float involved = Float
- Divide: Always Float (may have fractional result)
Part of #300."
```

---

## Task 4: Add compute_type() to Comparison Nodes

**Files:**
- Modify: `lib/Chalk/IR/Node/GT.pm`
- Modify: `lib/Chalk/IR/Node/LT.pm`
- Modify: `lib/Chalk/IR/Node/EQ.pm`
- Modify: `t/ir/node-types.t`

**Step 1: Write failing test**

Add to `t/ir/node-types.t`:

```perl
subtest 'Comparison nodes yield Bool type' => sub {
    use Chalk::IR::Node::GT;
    use Chalk::IR::Node::LT;
    use Chalk::IR::Node::EQ;
    use Chalk::IR::Type::Bool;

    my $int1 = Chalk::IR::Node::Constant->new(
        value => 5,
        type  => Chalk::IR::Type::Integer->constant(5),
    );
    my $int2 = Chalk::IR::Node::Constant->new(
        value => 3,
        type  => Chalk::IR::Type::Integer->constant(3),
    );

    my $gt = Chalk::IR::Node::GT->new(left => $int1, right => $int2);
    ok($gt->can('compute_type'), 'GT has compute_type');
    isa_ok($gt->compute_type(), 'Chalk::IR::Type::Bool', 'GT yields Bool');

    my $lt = Chalk::IR::Node::LT->new(left => $int1, right => $int2);
    isa_ok($lt->compute_type(), 'Chalk::IR::Type::Bool', 'LT yields Bool');

    my $eq = Chalk::IR::Node::EQ->new(left => $int1, right => $int2);
    isa_ok($eq->compute_type(), 'Chalk::IR::Type::Bool', 'EQ yields Bool');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/ir/node-types.t`
Expected: FAIL

**Step 3: Implement compute_type for comparison nodes**

Add to `lib/Chalk/IR/Node/GT.pm`, `LT.pm`, `EQ.pm` (same pattern):

```perl
use Chalk::IR::Type::Bool;

method compute_type() {
    return Chalk::IR::Type::Bool->new();
}
```

**Step 4: Run test to verify it passes**

Run: `./prove t/ir/node-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/GT.pm lib/Chalk/IR/Node/LT.pm lib/Chalk/IR/Node/EQ.pm t/ir/node-types.t
git commit -m "feat(ir): Add compute_type() to comparison nodes (GT, LT, EQ)

Comparison operations always yield Bool type.
Part of #300."
```

---

## Task 5: Create TypeInference Module in Grammar Namespace

**Files:**
- Create: `lib/Chalk/Grammar/Chalk/TypeInference.pm`
- Test: `t/types/grammar-type-inference.t` (create)

**Step 1: Write failing test**

Create `t/types/grammar-type-inference.t`:

```perl
# ABOUTME: Tests for Chalk-specific type inference rules
# ABOUTME: Validates inference from operations and usage patterns

use 5.042;
use Test::More;
use lib 'lib';

use_ok('Chalk::Grammar::Chalk::TypeInference');

subtest 'Infer type from arithmetic operation' => sub {
    my $inferencer = Chalk::Grammar::Chalk::TypeInference->new();

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $result = $inferencer->infer_binary_op('+', $int_type, $int_type);

    isa_ok($result, 'Chalk::Grammar::Chalk::Type::Int', 'Int + Int = Int');
};

subtest 'Infer type from mixed numeric operation' => sub {
    my $inferencer = Chalk::Grammar::Chalk::TypeInference->new();

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $num_type = Chalk::Grammar::Chalk::Type::Num->new();
    my $result = $inferencer->infer_binary_op('+', $int_type, $num_type);

    isa_ok($result, 'Chalk::Grammar::Chalk::Type::Num', 'Int + Num = Num');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `./prove t/types/grammar-type-inference.t`
Expected: FAIL - module doesn't exist

**Step 3: Create the module**

Create `lib/Chalk/Grammar/Chalk/TypeInference.pm`:

```perl
# ABOUTME: Chalk-specific type inference rules
# ABOUTME: Infers types from operations and usage patterns per Perl semantics

use 5.42.0;
use experimental qw(class);
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Boolean;
use Chalk::Grammar::Chalk::Type::Any;

class Chalk::Grammar::Chalk::TypeInference {

    # Infer result type from binary operation
    method infer_binary_op($op, $left_type, $right_type) {
        # Arithmetic operators
        if ($op =~ /^[+\-*]$/) {
            return $self->_infer_arithmetic($left_type, $right_type);
        }

        # Division always yields Num
        if ($op eq '/') {
            return Chalk::Grammar::Chalk::Type::Num->new();
        }

        # String concatenation
        if ($op eq '.') {
            return Chalk::Grammar::Chalk::Type::Str->new();
        }

        # Comparison operators yield Boolean
        if ($op =~ /^(==|!=|<|>|<=|>=|eq|ne|lt|gt|le|ge)$/) {
            return Chalk::Grammar::Chalk::Type::Boolean->new();
        }

        # Unknown operator - return Any
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    method _infer_arithmetic($left_type, $right_type) {
        # If either is Num, result is Num
        if ($left_type isa Chalk::Grammar::Chalk::Type::Num ||
            $right_type isa Chalk::Grammar::Chalk::Type::Num) {
            return Chalk::Grammar::Chalk::Type::Num->new();
        }

        # Int op Int = Int
        if ($left_type isa Chalk::Grammar::Chalk::Type::Int &&
            $right_type isa Chalk::Grammar::Chalk::Type::Int) {
            return Chalk::Grammar::Chalk::Type::Int->new();
        }

        # Default to Num for other numeric contexts
        return Chalk::Grammar::Chalk::Type::Num->new();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/types/grammar-type-inference.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/Grammar/Chalk/TypeInference.pm t/types/grammar-type-inference.t
git commit -m "feat(types): Create Chalk::Grammar::Chalk::TypeInference

Chalk-specific type inference rules for binary operations.
- Arithmetic: Int op Int = Int, Num involved = Num
- Division: Always Num
- Comparison: Always Boolean
- Concatenation: Always Str
Part of #300."
```

---

## Task 6: Add String Operation Inference

**Files:**
- Modify: `lib/Chalk/Grammar/Chalk/TypeInference.pm`
- Modify: `t/types/grammar-type-inference.t`

**Step 1: Write failing test**

Add to `t/types/grammar-type-inference.t`:

```perl
subtest 'String concatenation yields Str' => sub {
    my $inferencer = Chalk::Grammar::Chalk::TypeInference->new();

    my $str_type = Chalk::Grammar::Chalk::Type::Str->new();
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();

    my $result = $inferencer->infer_binary_op('.', $str_type, $int_type);
    isa_ok($result, 'Chalk::Grammar::Chalk::Type::Str', 'Str . Int = Str');

    $result = $inferencer->infer_binary_op('.', $int_type, $int_type);
    isa_ok($result, 'Chalk::Grammar::Chalk::Type::Str', 'Int . Int = Str (stringifies)');
};

subtest 'Comparison operations yield Boolean' => sub {
    my $inferencer = Chalk::Grammar::Chalk::TypeInference->new();

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();

    for my $op (qw(== != < > <= >=)) {
        my $result = $inferencer->infer_binary_op($op, $int_type, $int_type);
        isa_ok($result, 'Chalk::Grammar::Chalk::Type::Boolean', "$op yields Boolean");
    }

    my $str_type = Chalk::Grammar::Chalk::Type::Str->new();
    for my $op (qw(eq ne lt gt le ge)) {
        my $result = $inferencer->infer_binary_op($op, $str_type, $str_type);
        isa_ok($result, 'Chalk::Grammar::Chalk::Type::Boolean', "$op yields Boolean");
    }
};
```

**Step 2: Run test to verify it passes**

Run: `./prove t/types/grammar-type-inference.t`
Expected: PASS (already implemented in Task 5)

**Step 3: Commit**

```bash
git add t/types/grammar-type-inference.t
git commit -m "test(types): Add string and comparison operation tests

Validates concatenation → Str and comparison → Boolean.
Part of #300."
```

---

## Task 7: Run Full Test Suite

**Step 1: Run all tests**

Run: `./prove -j4`
Expected: All tests pass

**Step 2: If failures, fix and recommit**

Address any regressions before proceeding.

**Step 3: Final commit for #300**

```bash
git add -A
git commit -m "feat(ir): Complete type inference infrastructure (#300)

- IR nodes have compute_type() method
- Chalk::Grammar::Chalk::TypeInference for Perl-specific rules
- Arithmetic, comparison, and string operations typed correctly

Closes #300."
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Add compute_type() to Add | Add.pm, node-types.t |
| 2 | Float support in Add | Add.pm, node-types.t |
| 3 | compute_type for Sub/Mul/Div | 3 node files, tests |
| 4 | compute_type for comparisons | GT/LT/EQ.pm, tests |
| 5 | TypeInference grammar module | TypeInference.pm, tests |
| 6 | String/comparison tests | tests |
| 7 | Full test suite verification | all |

**Next:** After completing this plan, proceed to #336 (Chapter 14: Narrow primitive types) for sub-word integer support.
