# Chapter 4 Native Bool, TypeTuple, and @ARGV Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bring Chalk into full compliance with Simple compiler Chapter 4 by implementing native Bool type, TypeTuple for multi-return nodes, and @ARGV support.

**Architecture:** Extend the IR type lattice with TypeBool (using `builtin::true`/`builtin::false`), TypeTuple (for multi-return nodes like Start), and TypeCtrl (control token). Start becomes a MultiNode returning `(ctrl, arg)` tuple. Proj extracts elements from tuples. All comparison nodes return native booleans.

**Tech Stack:** Perl 5.42.0, `builtin` package for native booleans, existing IR type lattice pattern.

**Design Reference:** See `docs/plans/2025-11-30-chapter04-native-bool-tuple-design.md` for detailed design decisions.

---

## Task 1: Create TypeBool Type

**Files:**
- Create: `lib/Chalk/IR/Type/TypeBool.pm`
- Test: `t/sea-of-nodes/ir-type-bool.t`

**Step 1: Write the failing test**

Create `t/sea-of-nodes/ir-type-bool.t`:

```perl
# ABOUTME: Unit tests for TypeBool IR type
# ABOUTME: Tests native bool type using builtin::true/builtin::false

use lib 'lib';
use v5.42;
use Test::More;
use builtin qw(true false is_bool);
use Scalar::Util qw(refaddr);

use_ok('Chalk::IR::Type::TypeBool');

subtest 'TypeBool TRUE singleton' => sub {
    my $true1 = Chalk::IR::Type::TypeBool->TRUE;
    my $true2 = Chalk::IR::Type::TypeBool->TRUE;

    ok($true1, 'TRUE returns a value');
    is(refaddr($true1), refaddr($true2), 'TRUE returns same singleton');
    ok($true1 isa Chalk::IR::Type::TypeBool, 'TRUE is a TypeBool');
    ok($true1->is_constant, 'TRUE is constant');
    ok(is_bool($true1->value), 'TRUE value is native bool');
    ok($true1->value, 'TRUE value is truthy');
};

subtest 'TypeBool FALSE singleton' => sub {
    my $false1 = Chalk::IR::Type::TypeBool->FALSE;
    my $false2 = Chalk::IR::Type::TypeBool->FALSE;

    ok(defined($false1), 'FALSE returns a value');
    is(refaddr($false1), refaddr($false2), 'FALSE returns same singleton');
    ok($false1 isa Chalk::IR::Type::TypeBool, 'FALSE is a TypeBool');
    ok($false1->is_constant, 'FALSE is constant');
    ok(is_bool($false1->value), 'FALSE value is native bool');
    ok(!$false1->value, 'FALSE value is falsy');
};

subtest 'TypeBool constant() factory' => sub {
    my $from_true = Chalk::IR::Type::TypeBool->constant(1);
    my $from_false = Chalk::IR::Type::TypeBool->constant(0);

    is(refaddr($from_true), refaddr(Chalk::IR::Type::TypeBool->TRUE), 'constant(1) returns TRUE');
    is(refaddr($from_false), refaddr(Chalk::IR::Type::TypeBool->FALSE), 'constant(0) returns FALSE');
};

subtest 'TypeBool inherits from Chalk::IR::Type' => sub {
    my $bool = Chalk::IR::Type::TypeBool->TRUE;
    ok($bool isa Chalk::IR::Type, 'TypeBool inherits from Type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/ir-type-bool.t`
Expected: FAIL with "Can't locate Chalk/IR/Type/TypeBool.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type/TypeBool.pm`:

```perl
# ABOUTME: TypeBool represents a constant boolean value in IR
# ABOUTME: Uses builtin::true/builtin::false for native Perl booleans

use 5.42.0;
use experimental qw(class);
use builtin qw(true false);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeBool :isa(Chalk::IR::Type) {
    field $value :param :reader;

    method is_constant() { return 1; }

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

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/ir-type-bool.t`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/TypeBool.pm t/sea-of-nodes/ir-type-bool.t
git commit -m "feat(ir): add TypeBool with native builtin::true/false"
```

---

## Task 2: Create TypeCtrl Type

**Files:**
- Create: `lib/Chalk/IR/Type/TypeCtrl.pm`
- Modify: `t/sea-of-nodes/ir-type-bool.t` (add TypeCtrl tests)

**Step 1: Write the failing test**

Append to `t/sea-of-nodes/ir-type-bool.t` (rename later to `ir-types.t`):

```perl
use_ok('Chalk::IR::Type::TypeCtrl');

subtest 'TypeCtrl CTRL singleton' => sub {
    my $ctrl1 = Chalk::IR::Type::TypeCtrl->CTRL;
    my $ctrl2 = Chalk::IR::Type::TypeCtrl->CTRL;

    ok($ctrl1, 'CTRL returns a value');
    is(refaddr($ctrl1), refaddr($ctrl2), 'CTRL returns same singleton');
    ok($ctrl1 isa Chalk::IR::Type::TypeCtrl, 'CTRL is a TypeCtrl');
    ok($ctrl1->is_constant, 'CTRL is constant');
    ok(!defined($ctrl1->value), 'CTRL value is undef (control has no data)');
};

subtest 'TypeCtrl inherits from Chalk::IR::Type' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    ok($ctrl isa Chalk::IR::Type, 'TypeCtrl inherits from Type');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/ir-type-bool.t`
Expected: FAIL with "Can't locate Chalk/IR/Type/TypeCtrl.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type/TypeCtrl.pm`:

```perl
# ABOUTME: TypeCtrl represents a control token in IR
# ABOUTME: Singleton type for control flow (has no data value)

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeCtrl :isa(Chalk::IR::Type) {
    method is_constant() { return 1; }
    method value() { return undef; }

    sub CTRL {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/ir-type-bool.t`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/TypeCtrl.pm t/sea-of-nodes/ir-type-bool.t
git commit -m "feat(ir): add TypeCtrl singleton for control tokens"
```

---

## Task 3: Create TypeTuple Type

**Files:**
- Create: `lib/Chalk/IR/Type/TypeTuple.pm`
- Create: `t/sea-of-nodes/ir-type-tuple.t`

**Step 1: Write the failing test**

Create `t/sea-of-nodes/ir-type-tuple.t`:

```perl
# ABOUTME: Unit tests for TypeTuple IR type
# ABOUTME: Tests multi-return type for nodes like Start

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);

use_ok('Chalk::IR::Type::TypeTuple');
use_ok('Chalk::IR::Type::TypeCtrl');
use_ok('Chalk::IR::Type::TypeInteger');
use_ok('Chalk::IR::Type::Top');

subtest 'TypeTuple::of() construction' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $int = Chalk::IR::Type::TypeInteger->constant(42);

    my $tuple = Chalk::IR::Type::TypeTuple->of($ctrl, $int);

    ok($tuple, 'of() returns a value');
    ok($tuple isa Chalk::IR::Type::TypeTuple, 'of() returns TypeTuple');
};

subtest 'TypeTuple at() extraction' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $int = Chalk::IR::Type::TypeInteger->constant(42);

    my $tuple = Chalk::IR::Type::TypeTuple->of($ctrl, $int);

    is(refaddr($tuple->at(0)), refaddr($ctrl), 'at(0) returns first element');
    is(refaddr($tuple->at(1)), refaddr($int), 'at(1) returns second element');
};

subtest 'TypeTuple is_constant when all elements constant' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $int = Chalk::IR::Type::TypeInteger->constant(42);

    my $tuple = Chalk::IR::Type::TypeTuple->of($ctrl, $int);

    ok($tuple->is_constant, 'Tuple of constants is constant');
};

subtest 'TypeTuple not constant when any element non-constant' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $top = Chalk::IR::Type::Top->top;

    my $tuple = Chalk::IR::Type::TypeTuple->of($ctrl, $top);

    ok(!$tuple->is_constant, 'Tuple with Top element is not constant');
};

subtest 'TypeTuple value() returns array of values' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $int = Chalk::IR::Type::TypeInteger->constant(42);

    my $tuple = Chalk::IR::Type::TypeTuple->of($ctrl, $int);

    my $values = $tuple->value;
    ok(ref($values) eq 'ARRAY', 'value() returns arrayref');
    is(scalar(@$values), 2, 'value() has 2 elements');
    ok(!defined($values->[0]), 'First value is undef (ctrl)');
    is($values->[1], 42, 'Second value is 42');
};

subtest 'TypeTuple types() accessor' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $int = Chalk::IR::Type::TypeInteger->constant(42);

    my $tuple = Chalk::IR::Type::TypeTuple->of($ctrl, $int);

    my $types = $tuple->types;
    ok(ref($types) eq 'ARRAY', 'types() returns arrayref');
    is(scalar(@$types), 2, 'types() has 2 elements');
};

subtest 'TypeTuple inherits from Chalk::IR::Type' => sub {
    my $tuple = Chalk::IR::Type::TypeTuple->of(
        Chalk::IR::Type::TypeCtrl->CTRL
    );
    ok($tuple isa Chalk::IR::Type, 'TypeTuple inherits from Type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/ir-type-tuple.t`
Expected: FAIL with "Can't locate Chalk/IR/Type/TypeTuple.pm"

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Type/TypeTuple.pm`:

```perl
# ABOUTME: TypeTuple represents multiple types for multi-return nodes
# ABOUTME: Used by Start to return (ctrl, arg) and similar patterns

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

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

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/ir-type-tuple.t`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/TypeTuple.pm t/sea-of-nodes/ir-type-tuple.t
git commit -m "feat(ir): add TypeTuple for multi-return nodes"
```

---

## Task 4: Update Constant Node to Support Bool Type

**Files:**
- Modify: `lib/Chalk/IR/Node/Constant.pm:48-50`
- Modify: `t/sea-of-nodes/compute.t` (add tests)

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/compute.t` after line 45:

```perl
# TypeBool tests for Constant node
use_ok('Chalk::IR::Type::TypeBool');
use builtin qw(true false is_bool);

subtest 'Constant node compute() returns TypeBool for Bool type' => sub {
    my $const_true = Chalk::IR::Node::Constant->new(value => true, type => 'Bool');
    my $const_false = Chalk::IR::Node::Constant->new(value => false, type => 'Bool');

    my $type_true = $const_true->compute();
    ok($type_true isa Chalk::IR::Type::TypeBool, 'compute() returns TypeBool for Bool constant');
    is($type_true->is_constant, 1, 'TypeBool is constant');
    ok(is_bool($type_true->value), 'TypeBool value is native bool');
    ok($type_true->value, 'TypeBool TRUE value is truthy');

    my $type_false = $const_false->compute();
    ok($type_false isa Chalk::IR::Type::TypeBool, 'compute() returns TypeBool for false');
    ok(!$type_false->value, 'TypeBool FALSE value is falsy');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/compute.t`
Expected: FAIL (Constant returns TypeInteger for Bool type)

**Step 3: Write minimal implementation**

Modify `lib/Chalk/IR/Node/Constant.pm`, update `compute()` method (around line 48):

```perl
    # Return type for constant folding - constants always have known type
    method compute() {
        if ($type eq 'Bool') {
            use Chalk::IR::Type::TypeBool;
            return Chalk::IR::Type::TypeBool->constant($value);
        }
        return Chalk::IR::Type::TypeInteger->constant($value);
    }
```

Also add `use Chalk::IR::Type::TypeBool;` at the top of the class (after line 8):

```perl
    use Chalk::IR::Type::TypeInteger;
    use Chalk::IR::Type::TypeBool;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/compute.t`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Constant.pm t/sea-of-nodes/compute.t
git commit -m "feat(ir): Constant node supports Bool type with TypeBool"
```

---

## Task 5: Update GT Node for Native Bool

**Files:**
- Modify: `lib/Chalk/IR/Node/GT.pm`
- Modify: `t/sea-of-nodes/comparison-nodes.t` (add native bool tests)

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/comparison-nodes.t`:

```perl
use builtin qw(true false is_bool);
use_ok('Chalk::IR::Type::TypeBool');

subtest 'GT execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 10,
        "node:" . $right->id => 5,
    );

    my $result = $gt->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'GT execute() returns native bool');
    ok($result, 'GT 10 > 5 is true');
};

subtest 'GT execute() returns native false' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 3,
        "node:" . $right->id => 5,
    );

    my $result = $gt->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'GT execute() returns native bool');
    ok(!$result, 'GT 3 > 5 is false');
};

subtest 'GT compute() returns TypeBool for constant inputs' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my $type = $gt->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'GT compute() returns TypeBool');
    ok($type->is_constant, 'GT result is constant when inputs constant');
    ok($type->value, 'GT 10 > 5 compute() is true');
};

subtest 'GT peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my $result = $gt->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'GT peephole() returns Constant');
    is($result->type, 'Bool', 'GT peephole() returns Bool type');
    ok(is_bool($result->value), 'GT peephole() value is native bool');
    ok($result->value, 'GT peephole() 10 > 5 is true');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: FAIL (GT returns 1/0 integers, not native bools)

**Step 3: Write minimal implementation**

Replace `lib/Chalk/IR/Node/GT.pm` content:

```perl
# ABOUTME: Greater Than comparison node in the IR graph
# ABOUTME: Represents > comparison between two values, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;
use builtin qw(true false);

class Chalk::IR::Node::GT {
    use Chalk::IR::Type::TypeBool;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'GT' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'GT',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);
        return ($left_val > $right_val) ? true : false;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
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

    method record_transform(@args) {
        return;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: PASS (all tests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/GT.pm t/sea-of-nodes/comparison-nodes.t
git commit -m "feat(ir): GT returns native bool with compute/peephole"
```

---

## Task 6: Update LT Node for Native Bool

**Files:**
- Modify: `lib/Chalk/IR/Node/LT.pm`
- Modify: `t/sea-of-nodes/comparison-nodes.t` (add LT tests)

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/comparison-nodes.t`:

```perl
subtest 'LT execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 3,
        "node:" . $right->id => 5,
    );

    my $result = $lt->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'LT execute() returns native bool');
    ok($result, 'LT 3 < 5 is true');
};

subtest 'LT compute() returns TypeBool for constant inputs' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);

    my $type = $lt->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'LT compute() returns TypeBool');
    ok($type->value, 'LT 3 < 5 compute() is true');
};

subtest 'LT peephole() folds to Bool Constant' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);

    my $result = $lt->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'LT peephole() returns Constant');
    is($result->type, 'Bool', 'LT peephole() returns Bool type');
    ok($result->value, 'LT peephole() 3 < 5 is true');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: FAIL (LT returns 1/0 integers)

**Step 3: Write minimal implementation**

Update `lib/Chalk/IR/Node/LT.pm` following the same pattern as GT:

```perl
# ABOUTME: Less Than comparison node in the IR graph
# ABOUTME: Represents < comparison between two values, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;
use builtin qw(true false);

class Chalk::IR::Node::LT {
    use Chalk::IR::Type::TypeBool;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'LT' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'LT',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);
        return ($left_val < $right_val) ? true : false;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $result = $left_type->value < $right_type->value;
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

    method record_transform(@args) {
        return;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/LT.pm t/sea-of-nodes/comparison-nodes.t
git commit -m "feat(ir): LT returns native bool with compute/peephole"
```

---

## Task 7: Update EQ, NE, LE, GE Nodes for Native Bool

**Files:**
- Modify: `lib/Chalk/IR/Node/EQ.pm`
- Modify: `lib/Chalk/IR/Node/NE.pm`
- Modify: `lib/Chalk/IR/Node/LE.pm`
- Modify: `lib/Chalk/IR/Node/GE.pm`
- Modify: `t/sea-of-nodes/comparison-nodes.t`

**Step 1: Write the failing tests**

Add to `t/sea-of-nodes/comparison-nodes.t`:

```perl
# EQ tests
subtest 'EQ execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 5,
    );

    my $result = $eq->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'EQ execute() returns native bool');
    ok($result, 'EQ 5 == 5 is true');
};

subtest 'EQ compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);

    my $type = $eq->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'EQ compute() returns TypeBool');
};

# NE tests
subtest 'NE execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 3,
    );

    my $result = $ne->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'NE execute() returns native bool');
    ok($result, 'NE 5 != 3 is true');
};

subtest 'NE compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');

    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);

    my $type = $ne->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'NE compute() returns TypeBool');
};

# LE tests
subtest 'LE execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 5,
    );

    my $result = $le->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'LE execute() returns native bool');
    ok($result, 'LE 5 <= 5 is true');
};

subtest 'LE compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);

    my $type = $le->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'LE compute() returns TypeBool');
};

# GE tests
subtest 'GE execute() returns native bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);

    my %context = (
        "node:" . $left->id => 5,
        "node:" . $right->id => 5,
    );

    my $result = $ge->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'GE execute() returns native bool');
    ok($result, 'GE 5 >= 5 is true');
};

subtest 'GE compute() returns TypeBool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);

    my $type = $ge->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'GE compute() returns TypeBool');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: FAIL

**Step 3: Write minimal implementation**

Update each comparison node following the GT pattern. For EQ (`lib/Chalk/IR/Node/EQ.pm`):

```perl
# ABOUTME: Equal comparison node in the IR graph
# ABOUTME: Represents == comparison between two values, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;
use builtin qw(true false);

class Chalk::IR::Node::EQ {
    use Chalk::IR::Type::TypeBool;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'EQ' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'EQ',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);
        return ($left_val == $right_val) ? true : false;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $result = $left_type->value == $right_type->value;
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

    method record_transform(@args) {
        return;
    }
}

1;
```

Apply same pattern to NE (using `!=`), LE (using `<=`), GE (using `>=`).

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/EQ.pm lib/Chalk/IR/Node/NE.pm lib/Chalk/IR/Node/LE.pm lib/Chalk/IR/Node/GE.pm t/sea-of-nodes/comparison-nodes.t
git commit -m "feat(ir): EQ/NE/LE/GE return native bool with compute/peephole"
```

---

## Task 8: Update Not Node for Native Bool

**Files:**
- Modify: `lib/Chalk/IR/Node/Not.pm`
- Modify: `t/sea-of-nodes/comparison-nodes.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/comparison-nodes.t`:

```perl
# Not tests
subtest 'Not execute() returns native bool' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 0, type => 'Integer');

    my $not = Chalk::IR::Node::Not->new(operand => $operand);

    my %context = (
        "node:" . $operand->id => 0,
    );

    my $result = $not->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'Not execute() returns native bool');
    ok($result, 'Not !0 is true');
};

subtest 'Not execute() negates truthy value' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');

    my $not = Chalk::IR::Node::Not->new(operand => $operand);

    my %context = (
        "node:" . $operand->id => 1,
    );

    my $result = $not->execute(sub { $context{$_[0]} });
    ok(is_bool($result), 'Not execute() returns native bool');
    ok(!$result, 'Not !1 is false');
};

subtest 'Not compute() returns TypeBool' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 0, type => 'Integer');

    my $not = Chalk::IR::Node::Not->new(operand => $operand);

    my $type = $not->compute();
    ok($type isa Chalk::IR::Type::TypeBool, 'Not compute() returns TypeBool');
    ok($type->is_constant, 'Not result is constant when input constant');
    ok($type->value, 'Not !0 compute() is true');
};

subtest 'Not peephole() folds to Bool Constant' => sub {
    my $operand = Chalk::IR::Node::Constant->new(value => 0, type => 'Integer');

    my $not = Chalk::IR::Node::Not->new(operand => $operand);

    my $result = $not->peephole();
    ok($result isa Chalk::IR::Node::Constant, 'Not peephole() returns Constant');
    is($result->type, 'Bool', 'Not peephole() returns Bool type');
    ok($result->value, 'Not peephole() !0 is true');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: FAIL

**Step 3: Write minimal implementation**

Update `lib/Chalk/IR/Node/Not.pm`:

```perl
# ABOUTME: Logical negation node in the IR graph
# ABOUTME: Represents boolean negation of a single operand, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;
use builtin qw(true false);

class Chalk::IR::Node::Not {
    use Chalk::IR::Type::TypeBool;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $operand :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $operand->id ];
    }

    method op() { 'Not' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Not',
            inputs => $self->inputs,
            attributes => {
                operand_id => $operand->id,
            },
        };
    }

    method execute($context) {
        my $operand_val = $context->("node:" . $operand->id);
        return $operand_val ? false : true;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $operand_type = $operand->compute();
        if ($operand_type->is_constant) {
            my $result = $operand_type->value ? false : true;
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

    method record_transform(@args) {
        return;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/comparison-nodes.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Not.pm t/sea-of-nodes/comparison-nodes.t
git commit -m "feat(ir): Not returns native bool with compute/peephole"
```

---

## Task 9: Update Start Node as MultiNode

**Files:**
- Modify: `lib/Chalk/IR/Node/Start.pm`
- Create: `t/sea-of-nodes/chapter04.t`

**Step 1: Write the failing test**

Create `t/sea-of-nodes/chapter04.t`:

```perl
# ABOUTME: Test for Sea of Nodes IR generation - Chapter 4: Bool, Tuple, @ARGV
# ABOUTME: Validates TypeBool, TypeTuple, Start as MultiNode, and $arg binding

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);
use builtin qw(true false is_bool);

use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Type::TypeTuple');
use_ok('Chalk::IR::Type::TypeCtrl');
use_ok('Chalk::IR::Type::TypeInteger');
use_ok('Chalk::IR::Type::Top');

subtest 'Start is_multi() returns true' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    ok($start->can('is_multi'), 'Start has is_multi() method');
    ok($start->is_multi, 'Start is_multi() returns true');
};

subtest 'Start compute() returns TypeTuple' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $type = $start->compute();
    ok($type isa Chalk::IR::Type::TypeTuple, 'Start compute() returns TypeTuple');
};

subtest 'Start compute() tuple has (ctrl, arg)' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main', arg_value => 42);

    my $type = $start->compute();

    my $ctrl_type = $type->at(0);
    ok($ctrl_type isa Chalk::IR::Type::TypeCtrl, 'Tuple[0] is TypeCtrl');

    my $arg_type = $type->at(1);
    ok($arg_type isa Chalk::IR::Type::TypeInteger, 'Tuple[1] is TypeInteger');
    is($arg_type->value, 42, 'Tuple[1] value is 42');
};

subtest 'Start compute() with no arg returns Top for arg' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    my $type = $start->compute();

    my $arg_type = $type->at(1);
    ok($arg_type isa Chalk::IR::Type::Top, 'Tuple[1] is Top when no arg');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/chapter04.t`
Expected: FAIL (Start doesn't have is_multi or correct compute)

**Step 3: Write minimal implementation**

Update `lib/Chalk/IR/Node/Start.pm`:

```perl
# ABOUTME: Start node representing function entry point in the IR graph
# ABOUTME: MultiNode that returns (ctrl, arg) tuple for Chapter 4 compliance
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Start {
    use Chalk::IR::Type::TypeTuple;
    use Chalk::IR::Type::TypeCtrl;
    use Chalk::IR::Type::TypeInteger;
    use Chalk::IR::Type::Top;

    field $function_name :param :reader = undef;
    field $params        :param :reader = undef;
    field $label :param :reader = undef;
    field $function :param = undef;
    field $arg_value :param :reader = undef;  # @ARGV[0] passed at construction
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    ADJUST {
        $function_name //= $label // $function;
        $label //= $function_name;
    }

    method inputs() { return []; }

    method op() { 'Start' }

    method is_multi() { return 1; }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Start',
            inputs => [],
            attributes => {
                function_name => $function_name,
                label         => $label,
                params        => $params,
                arg_value     => $arg_value,
            },
        };
    }

    method execute() {
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $arg_type = defined($arg_value)
            ? Chalk::IR::Type::TypeInteger->constant($arg_value)
            : Chalk::IR::Type::Top->top();

        return Chalk::IR::Type::TypeTuple->of(
            Chalk::IR::Type::TypeCtrl->CTRL,
            $arg_type
        );
    }

    method peephole($graph = undef) {
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/chapter04.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Start.pm t/sea-of-nodes/chapter04.t
git commit -m "feat(ir): Start as MultiNode returning (ctrl, arg) tuple"
```

---

## Task 10: Update Proj Node to Extract from Tuple

**Files:**
- Modify: `lib/Chalk/IR/Node/Proj.pm`
- Modify: `t/sea-of-nodes/chapter04.t`

**Step 1: Write the failing test**

Add to `t/sea-of-nodes/chapter04.t`:

```perl
subtest 'Proj compute() extracts from Start tuple' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main', arg_value => 42);

    my $ctrl_proj = Chalk::IR::Node::Proj->new(
        source => $start,
        index => 0,
        label => 'ctrl',
        inputs => [$start->id],
    );

    my $arg_proj = Chalk::IR::Node::Proj->new(
        source => $start,
        index => 1,
        label => 'arg',
        inputs => [$start->id],
    );

    my $ctrl_type = $ctrl_proj->compute();
    ok($ctrl_type isa Chalk::IR::Type::TypeCtrl, 'Proj[0] compute() returns TypeCtrl');

    my $arg_type = $arg_proj->compute();
    ok($arg_type isa Chalk::IR::Type::TypeInteger, 'Proj[1] compute() returns TypeInteger');
    is($arg_type->value, 42, 'Proj[1] value is 42');
};

subtest 'Proj compute() returns Top when source not tuple' => sub {
    # Use a non-MultiNode source
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'Integer');

    my $proj = Chalk::IR::Node::Proj->new(
        source => $const,
        index => 0,
        label => 'test',
        inputs => [$const->id],
    );

    my $type = $proj->compute();
    ok($type isa Chalk::IR::Type::Top, 'Proj compute() returns Top for non-tuple source');
};
```

**Step 2: Run test to verify it fails**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/chapter04.t`
Expected: FAIL (Proj doesn't have compute that extracts from tuple)

**Step 3: Write minimal implementation**

Update `lib/Chalk/IR/Node/Proj.pm` to add `compute()`:

```perl
# ABOUTME: Projection node in the IR graph
# ABOUTME: Represents extraction of a specific control or data path from a multi-way node
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Proj :isa(Chalk::IR::Node::Base) {
    use Chalk::IR::Type::Top;

    field $index  :param :reader;
    field $label  :param :reader;
    field $source :param :reader = undef;
    field $early_returns :param :reader = undef;

    method op() { 'Proj' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Proj',
            inputs => $self->inputs,
            attributes => {
                index => $index,
                label => $label,
            },
        };
    }

    method execute($context) {
        my $source_id = $self->inputs->[0];
        my $if_result = $context->("node:$source_id");

        my $if_bool = $if_result ? 1 : 0;
        return ($if_bool == $index) ? 0 : 1;
    }

    method compute() {
        return Chalk::IR::Type::Top->top() unless $source;

        my $source_type = $source->compute();

        # Extract type at index from tuple
        if ($source_type->can('at')) {
            return $source_type->at($index);
        }

        return Chalk::IR::Type::Top->top();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/chapter04.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Proj.pm t/sea-of-nodes/chapter04.t
git commit -m "feat(ir): Proj compute() extracts from TypeTuple"
```

---

## Task 11: Run Full Test Suite

**Files:**
- None (verification only)

**Step 1: Run all Sea of Nodes tests**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/*.t`
Expected: All tests PASS

**Step 2: Run full test suite**

Run: `PLENV_VERSION=5.42.0 plenv exec prove t/*.t t/**/*.t`
Expected: All tests PASS

**Step 3: Commit any fixes if needed**

Only if tests revealed issues.

---

## Task 12: Integration Test - Chapter 4 Canonical Example

**Files:**
- Modify: `t/sea-of-nodes/chapter04.t`

**Step 1: Write integration test**

Add to `t/sea-of-nodes/chapter04.t`:

```perl
# Chapter 4 canonical test case from design doc
use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Grammar::Chalk');
use_ok('Chalk::Semiring::ChalkIR');

sub make_parser {
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkIR->new(
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    return $parser;
}

# Note: Full integration with $arg binding requires Program.pm changes
# which are deferred to a future task. This test validates the type system.

subtest 'Comparison with constant folding returns Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $right = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);

    my $folded = $gt->peephole();
    ok($folded isa Chalk::IR::Node::Constant, 'GT peephole folds to Constant');
    is($folded->type, 'Bool', 'Folded type is Bool');
    ok(is_bool($folded->value), 'Folded value is native bool');
    ok($folded->value, '10 > 5 is true');
};
```

**Step 2: Run test**

Run: `PLENV_VERSION=5.42.0 plenv exec prove -v t/sea-of-nodes/chapter04.t`
Expected: PASS

**Step 3: Commit**

```bash
git add t/sea-of-nodes/chapter04.t
git commit -m "test: add Chapter 4 integration tests"
```

---

## Task 13: Final Verification and Branch Cleanup

**Step 1: Run full test suite one more time**

Run: `PLENV_VERSION=5.42.0 plenv exec prove t/*.t t/**/*.t`
Expected: All tests PASS

**Step 2: Review all commits**

Run: `git log --oneline pu..HEAD`
Verify all commits are clean and have good messages.

**Step 3: Ready for PR**

The branch `chapter04-native-bool-tuple` is ready to be merged or submitted as a PR to `pu`.

---

## Future Work (Not in This Plan)

The following items are documented but deferred:

1. **Program.pm Integration** - Creating Proj nodes and binding `$arg` to initial scope requires more extensive changes to Program.pm and how it interacts with the parser. This should be a separate follow-up task.

2. **@ARGV Runtime Integration** - Actually passing `@ARGV[0]` to Start requires changes to the CLI entry point.

3. **Chapter 5+ Features** - These build on the foundation laid here.
