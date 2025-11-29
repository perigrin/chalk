# compute() Method Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add compute() method to IR nodes enabling compile-time type analysis and constant folding via peephole().

**Architecture:** Create minimal IR-level type system (Top, Bottom, TypeInteger) separate from semantic types. Each IR node implements compute() returning an IR Type. Arithmetic nodes use compute() in peephole() to fold constants.

**Tech Stack:** Perl 5.42.0 class syntax, TAP testing with Test::More

---

## Task 1: Create IR Type Base Class

**Files:**
- Create: `lib/Chalk/IR/Type.pm`
- Test: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Create `t/sea-of-nodes/ir-type.t`:

```perl
# ABOUTME: Unit tests for IR-level type system used by compute()
# ABOUTME: Tests Type base class and is_constant/value interface

use lib 'lib';
use v5.42;
use Test::More;

use_ok('Chalk::IR::Type');

subtest 'Type base class interface' => sub {
    my $type = Chalk::IR::Type->new();
    ok($type, 'Can create base Type');
    is($type->is_constant, 0, 'Base type is not constant');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL with "Can't locate Chalk/IR/Type.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type.pm`:

```perl
# ABOUTME: Base class for IR-level types used by compute() for optimization
# ABOUTME: Part of type lattice: Top -> constants -> Bottom

use 5.42.0;
use experimental qw(class);

class Chalk::IR::Type {
    method is_constant() { return 0; }

    method value() {
        die "Cannot get value from non-constant type";
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add Type base class for compute() type lattice"
```

---

## Task 2: Create IR Type Top (Unknown)

**Files:**
- Create: `lib/Chalk/IR/Type/Top.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Type::Top');

subtest 'Top type (unknown value)' => sub {
    my $top1 = Chalk::IR::Type::Top->TOP;
    my $top2 = Chalk::IR::Type::Top->TOP;

    ok($top1, 'Can get TOP singleton');
    ok($top1 isa Chalk::IR::Type, 'TOP isa Type');
    is($top1->is_constant, 0, 'TOP is not constant');
    is(refaddr($top1), refaddr($top2), 'TOP is singleton');
};
```

Also add `use Scalar::Util qw(refaddr);` at the top.

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL with "Can't locate Chalk/IR/Type/Top.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type/Top.pm`:

```perl
# ABOUTME: Top type representing unknown/unanalyzed values in IR
# ABOUTME: Singleton - use Chalk::IR::Type::Top->TOP to access

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::Top :isa(Chalk::IR::Type) {
    my $TOP;

    sub TOP ($class = __CLASS__) {
        $TOP //= $class->new();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/Top.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add Top type singleton for unknown values"
```

---

## Task 3: Create IR Type Bottom (Error)

**Files:**
- Create: `lib/Chalk/IR/Type/Bottom.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Type::Bottom');

subtest 'Bottom type (error state)' => sub {
    my $bot1 = Chalk::IR::Type::Bottom->BOTTOM;
    my $bot2 = Chalk::IR::Type::Bottom->BOTTOM;

    ok($bot1, 'Can get BOTTOM singleton');
    ok($bot1 isa Chalk::IR::Type, 'BOTTOM isa Type');
    is($bot1->is_constant, 0, 'BOTTOM is not constant');
    is(refaddr($bot1), refaddr($bot2), 'BOTTOM is singleton');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL with "Can't locate Chalk/IR/Type/Bottom.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type/Bottom.pm`:

```perl
# ABOUTME: Bottom type representing error states in IR (e.g., division by zero)
# ABOUTME: Singleton - use Chalk::IR::Type::Bottom->BOTTOM to access

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::Bottom :isa(Chalk::IR::Type) {
    my $BOTTOM;

    sub BOTTOM ($class = __CLASS__) {
        $BOTTOM //= $class->new();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/Bottom.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add Bottom type singleton for error states"
```

---

## Task 4: Create IR TypeInteger (Constant)

**Files:**
- Create: `lib/Chalk/IR/Type/TypeInteger.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Type::TypeInteger');

subtest 'TypeInteger (constant value)' => sub {
    my $int42 = Chalk::IR::Type::TypeInteger->constant(42);
    my $int0 = Chalk::IR::Type::TypeInteger->constant(0);

    ok($int42, 'Can create TypeInteger');
    ok($int42 isa Chalk::IR::Type, 'TypeInteger isa Type');
    is($int42->is_constant, 1, 'TypeInteger is constant');
    is($int42->value, 42, 'value() returns stored value');
    is($int0->value, 0, 'value() returns 0 for zero constant');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL with "Can't locate Chalk/IR/Type/TypeInteger.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type/TypeInteger.pm`:

```perl
# ABOUTME: TypeInteger represents a constant integer value in IR
# ABOUTME: Used by compute() to enable constant folding in peephole()

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeInteger :isa(Chalk::IR::Type) {
    field $value :param :reader;

    method is_constant() { return 1; }

    sub constant ($class, $val) {
        return $class->new(value => $val);
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/TypeInteger.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add TypeInteger for constant integer values"
```

---

## Task 5: Add compute() to Base Node

**Files:**
- Modify: `lib/Chalk/IR/Node/Base.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Start');

subtest 'Base node compute() returns TOP' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $type = $start->compute();

    ok($type, 'compute() returns a type');
    ok($type isa Chalk::IR::Type::Top, 'Default compute() returns TOP');
    is($type->is_constant, 0, 'TOP is not constant');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL with "Can't locate object method \"compute\""

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Base.pm` after the `use` statements:

```perl
use Chalk::IR::Type::Top;
```

Add method inside the class:

```perl
    # Default compute() returns TOP (unknown)
    # Subclasses override for specific type analysis
    method compute() {
        return Chalk::IR::Type::Top->TOP;
    }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Base.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add default compute() returning TOP to Base node"
```

---

## Task 6: Add compute() to Constant Node

**Files:**
- Modify: `lib/Chalk/IR/Node/Constant.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Constant');

subtest 'Constant node compute() returns TypeInteger' => sub {
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'Int');
    my $type = $const->compute();

    ok($type, 'compute() returns a type');
    ok($type isa Chalk::IR::Type::TypeInteger, 'Constant compute() returns TypeInteger');
    is($type->is_constant, 1, 'TypeInteger is constant');
    is($type->value, 42, 'TypeInteger has correct value');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL (compute returns TOP, not TypeInteger)

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Constant.pm` after the `use` statements:

```perl
use Chalk::IR::Type::TypeInteger;
```

Add method inside the class:

```perl
    method compute() {
        return Chalk::IR::Type::TypeInteger->constant($value);
    }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Constant.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add compute() to Constant returning TypeInteger"
```

---

## Task 7: Add compute() to Add Node

**Files:**
- Modify: `lib/Chalk/IR/Node/Add.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Add');

subtest 'Add node compute() with constants' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $right = Chalk::IR::Node::Constant->new(value => 2, type => 'Int');
    my $add = Chalk::IR::Node::Add->new(
        left => $left,
        right => $right,
        inputs => [$left->id, $right->id],
    );

    my $type = $add->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'Add of constants returns TypeInteger');
    is($type->value, 3, 'Add folds 1+2 to 3');
};

subtest 'Add node compute() with non-constant returns TOP' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $const = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $add = Chalk::IR::Node::Add->new(
        left => $start,
        right => $const,
        inputs => [$start->id, $const->id],
    );

    my $type = $add->compute();
    ok($type isa Chalk::IR::Type::Top, 'Add with non-constant returns TOP');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL (compute returns TOP instead of folded constant)

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Add.pm` after the `use` statements:

```perl
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::TypeInteger;
```

Add method inside the class:

```perl
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        # Propagate BOTTOM
        return Chalk::IR::Type::Bottom->BOTTOM
            if $left_type isa Chalk::IR::Type::Bottom
            || $right_type isa Chalk::IR::Type::Bottom;

        # Fold constants
        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::TypeInteger->constant(
                $left_type->value + $right_type->value
            );
        }

        return Chalk::IR::Type::Top->TOP;
    }
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Add.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add compute() to Add node with constant folding"
```

---

## Task 8: Update peephole() in Add Node

**Files:**
- Modify: `lib/Chalk/IR/Node/Add.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
subtest 'Add peephole() folds constants' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $right = Chalk::IR::Node::Constant->new(value => 2, type => 'Int');
    my $add = Chalk::IR::Node::Add->new(
        left => $left,
        right => $right,
        inputs => [$left->id, $right->id],
    );

    my $result = $add->peephole(undef);
    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant');
    is($result->value, 3, 'peephole() folds 1+2 to Constant(3)');
};

subtest 'Add peephole() returns self for non-constants' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $const = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $add = Chalk::IR::Node::Add->new(
        left => $start,
        right => $const,
        inputs => [$start->id, $const->id],
    );

    my $result = $add->peephole(undef);
    is(refaddr($result), refaddr($add), 'peephole() returns self when not foldable');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL (peephole returns $self, not Constant)

**Step 3: Write minimal implementation**

Update `peephole()` method in `lib/Chalk/IR/Node/Add.pm`:

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

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Add.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): update Add peephole() to use compute() for constant folding"
```

---

## Task 9: Add compute() and peephole() to Subtract

**Files:**
- Modify: `lib/Chalk/IR/Node/Subtract.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Subtract');

subtest 'Subtract compute() and peephole()' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Int');
    my $right = Chalk::IR::Node::Constant->new(value => 3, type => 'Int');
    my $sub = Chalk::IR::Node::Subtract->new(
        left => $left,
        right => $right,
        inputs => [$left->id, $right->id],
    );

    my $type = $sub->compute();
    is($type->value, 2, 'Subtract compute() folds 5-3 to 2');

    my $result = $sub->peephole(undef);
    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant');
    is($result->value, 2, 'peephole() folds to Constant(2)');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Subtract.pm`:

```perl
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::TypeInteger;
use Chalk::IR::Node::Constant;

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        return Chalk::IR::Type::Bottom->BOTTOM
            if $left_type isa Chalk::IR::Type::Bottom
            || $right_type isa Chalk::IR::Type::Bottom;

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::TypeInteger->constant(
                $left_type->value - $right_type->value
            );
        }

        return Chalk::IR::Type::Top->TOP;
    }

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

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Subtract.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add compute() and peephole() to Subtract node"
```

---

## Task 10: Add compute() and peephole() to Multiply

**Files:**
- Modify: `lib/Chalk/IR/Node/Multiply.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Multiply');

subtest 'Multiply compute() and peephole()' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 6, type => 'Int');
    my $right = Chalk::IR::Node::Constant->new(value => 7, type => 'Int');
    my $mul = Chalk::IR::Node::Multiply->new(
        left => $left,
        right => $right,
        inputs => [$left->id, $right->id],
    );

    my $type = $mul->compute();
    is($type->value, 42, 'Multiply compute() folds 6*7 to 42');

    my $result = $mul->peephole(undef);
    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant');
    is($result->value, 42, 'peephole() folds to Constant(42)');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Multiply.pm`:

```perl
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::TypeInteger;
use Chalk::IR::Node::Constant;

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        return Chalk::IR::Type::Bottom->BOTTOM
            if $left_type isa Chalk::IR::Type::Bottom
            || $right_type isa Chalk::IR::Type::Bottom;

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::TypeInteger->constant(
                $left_type->value * $right_type->value
            );
        }

        return Chalk::IR::Type::Top->TOP;
    }

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

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Multiply.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add compute() and peephole() to Multiply node"
```

---

## Task 11: Add compute() and peephole() to Divide

**Files:**
- Modify: `lib/Chalk/IR/Node/Divide.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Divide');

subtest 'Divide compute() and peephole()' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Int');
    my $right = Chalk::IR::Node::Constant->new(value => 2, type => 'Int');
    my $div = Chalk::IR::Node::Divide->new(
        left => $left,
        right => $right,
        inputs => [$left->id, $right->id],
    );

    my $type = $div->compute();
    is($type->value, 5, 'Divide compute() folds 10/2 to 5');

    my $result = $div->peephole(undef);
    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant');
    is($result->value, 5, 'peephole() folds to Constant(5)');
};

subtest 'Divide by zero returns BOTTOM' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Int');
    my $right = Chalk::IR::Node::Constant->new(value => 0, type => 'Int');
    my $div = Chalk::IR::Node::Divide->new(
        left => $left,
        right => $right,
        inputs => [$left->id, $right->id],
    );

    my $type = $div->compute();
    ok($type isa Chalk::IR::Type::Bottom, 'Division by zero returns BOTTOM');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Divide.pm`:

```perl
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::TypeInteger;
use Chalk::IR::Node::Constant;

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        return Chalk::IR::Type::Bottom->BOTTOM
            if $left_type isa Chalk::IR::Type::Bottom
            || $right_type isa Chalk::IR::Type::Bottom;

        if ($left_type->is_constant && $right_type->is_constant) {
            # Division by zero returns BOTTOM
            return Chalk::IR::Type::Bottom->BOTTOM
                if $right_type->value == 0;

            return Chalk::IR::Type::TypeInteger->constant(
                int($left_type->value / $right_type->value)
            );
        }

        return Chalk::IR::Type::Top->TOP;
    }

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

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Divide.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add compute() and peephole() to Divide with div-by-zero check"
```

---

## Task 12: Add compute() and peephole() to Negate

**Files:**
- Modify: `lib/Chalk/IR/Node/Negate.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/ir-type.t` before `done_testing()`:

```perl
use_ok('Chalk::IR::Node::Negate');

subtest 'Negate compute() and peephole()' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 42, type => 'Int');
    my $neg = Chalk::IR::Node::Negate->new(
        operand => $operand,
        inputs => [$operand->id],
    );

    my $type = $neg->compute();
    is($type->value, -42, 'Negate compute() folds -42');

    my $result = $neg->peephole(undef);
    ok($result isa Chalk::IR::Node::Constant, 'peephole() returns Constant');
    is($result->value, -42, 'peephole() folds to Constant(-42)');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: FAIL

**Step 3: Write minimal implementation**

Add to `lib/Chalk/IR/Node/Negate.pm`:

```perl
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::TypeInteger;
use Chalk::IR::Node::Constant;

    method compute() {
        my $operand_type = $operand->compute();

        return Chalk::IR::Type::Bottom->BOTTOM
            if $operand_type isa Chalk::IR::Type::Bottom;

        if ($operand_type->is_constant) {
            return Chalk::IR::Type::TypeInteger->constant(
                -$operand_type->value
            );
        }

        return Chalk::IR::Type::Top->TOP;
    }

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

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Negate.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(ir): add compute() and peephole() to Negate node"
```

---

## Task 13: Run Full Test Suite

**Files:**
- None (verification only)

**Step 1: Run all tests**

Run: `PLENV_VERSION=5.42.0 plenv exec ./prove`
Expected: All tests PASS

**Step 2: Run sea-of-nodes tests specifically**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -l t/sea-of-nodes/*.t`
Expected: All tests PASS

**Step 3: Commit final state**

```bash
git add -A
git commit -m "chore: verify all tests pass with compute() implementation"
```

---

## Task 14: Create PR

**Step 1: Push branch**

```bash
git push origin HEAD:compute-method
```

**Step 2: Create PR**

```bash
gh pr create --title "feat(ir): Add compute() method for Sea of Nodes chapter02 parity" --body "$(cat <<'EOF'
## Summary
- Add IR-level type system (Top, Bottom, TypeInteger)
- Add compute() method to IR nodes for type lattice analysis
- Update peephole() to use compute() for constant folding
- Enables `Add(Const(1), Const(2))` to fold to `Const(3)`

## Test plan
- [x] All existing tests pass
- [x] New ir-type.t tests pass
- [x] Constant folding verified in tests

Related: Sea of Nodes chapter02 parity
EOF
)"
```
