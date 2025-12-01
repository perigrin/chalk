# TypeInteger Lattice Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enhance TypeInteger to support the full type lattice with IntTop (unknown integer) and IntBot (error state) in addition to constant values.

**Architecture:** Extend TypeInteger with `is_top()` and `is_bottom()` methods, using `undef` value for IntTop and a separate `$is_bottom` flag for IntBot. Provide singleton accessors `TOP()` and `BOTTOM()` alongside the existing `constant()` factory. Update compute() methods in arithmetic nodes to return IntTop when operating on unknown integers (preserving type information) and IntBot for error conditions (e.g., division by zero).

**Tech Stack:** Perl 5.42, Perl OO with `class` keyword, Test::More

---

## Task 1: Add IntTop Support to TypeInteger

**Files:**
- Modify: `lib/Chalk/IR/Type/TypeInteger.pm`
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write failing test for IntTop singleton**

Add to `t/sea-of-nodes/ir-type.t` after the existing TypeInteger subtest:

```perl
subtest 'TypeInteger TOP (unknown integer)' => sub {
    my $top1 = Chalk::IR::Type::TypeInteger->TOP;
    my $top2 = Chalk::IR::Type::TypeInteger->TOP;

    ok($top1, 'Can get IntTop singleton');
    ok($top1 isa Chalk::IR::Type::TypeInteger, 'IntTop isa TypeInteger');
    is($top1->is_constant, 0, 'IntTop is not constant');
    ok($top1->is_top, 'IntTop is_top returns true');
    ok(!$top1->is_bottom, 'IntTop is_bottom returns false');
    is(refaddr($top1), refaddr($top2), 'IntTop is singleton');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/sea-of-nodes/ir-type.t`
Expected: FAIL - `is_top` method not found

**Step 3: Implement IntTop in TypeInteger**

Replace the content of `lib/Chalk/IR/Type/TypeInteger.pm`:

```perl
# ABOUTME: TypeInteger represents integer values in IR type lattice
# ABOUTME: Supports IntTop (unknown), IntBot (error), and constants

use 5.42.0;
use experimental qw(class);
use Chalk::IR::Type;

class Chalk::IR::Type::TypeInteger :isa(Chalk::IR::Type) {
    field $value :param :reader = undef;
    field $is_bottom :param :reader = 0;

    method is_constant() { defined($value) && !$is_bottom }
    method is_top()      { !defined($value) && !$is_bottom }

    sub TOP {
        state $singleton = __PACKAGE__->new();
        return $singleton;
    }

    sub BOTTOM {
        state $singleton = __PACKAGE__->new(is_bottom => 1);
        return $singleton;
    }

    sub constant {
        my $class = shift // __PACKAGE__;
        my $val = shift;
        return $class->new(value => $val);
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `./prove t/sea-of-nodes/ir-type.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/TypeInteger.pm t/sea-of-nodes/ir-type.t
git commit -m "feat(TypeInteger): add IntTop singleton for unknown integers"
```

---

## Task 2: Add IntBot Support to TypeInteger

**Files:**
- Modify: `t/sea-of-nodes/ir-type.t`

**Step 1: Write failing test for IntBot singleton**

Add to `t/sea-of-nodes/ir-type.t` after the IntTop subtest:

```perl
subtest 'TypeInteger BOTTOM (integer error state)' => sub {
    my $bot1 = Chalk::IR::Type::TypeInteger->BOTTOM;
    my $bot2 = Chalk::IR::Type::TypeInteger->BOTTOM;

    ok($bot1, 'Can get IntBot singleton');
    ok($bot1 isa Chalk::IR::Type::TypeInteger, 'IntBot isa TypeInteger');
    is($bot1->is_constant, 0, 'IntBot is not constant');
    ok(!$bot1->is_top, 'IntBot is_top returns false');
    ok($bot1->is_bottom, 'IntBot is_bottom returns true');
    is(refaddr($bot1), refaddr($bot2), 'IntBot is singleton');
};
```

**Step 2: Run test to verify it passes (BOTTOM already implemented in Task 1)**

Run: `./prove t/sea-of-nodes/ir-type.t`
Expected: PASS (BOTTOM was implemented in Task 1)

**Step 3: Commit**

```bash
git add t/sea-of-nodes/ir-type.t
git commit -m "test(TypeInteger): add IntBot singleton tests"
```

---

## Task 3: Update Add Node compute() to Return IntTop

**Files:**
- Modify: `lib/Chalk/IR/Node/Add.pm`
- Modify: `t/sea-of-nodes/compute.t`

**Step 1: Write failing test for Add with unknown integers returning IntTop**

Add to `t/sea-of-nodes/compute.t` after the existing Add subtests:

```perl
subtest 'Add node compute() with unknown integer returns IntTop' => sub {
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    # Create an IntTop type by making a node that returns IntTop
    # We'll use a trick: create a Divide with 0 divisor and then add
    # Actually, let's just verify the current behavior and then update

    # For now, test that when we update Add to return IntTop, it does so
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $add = Chalk::IR::Node::Add->new(left => $const3, right => $unknown);

    my $type = $add->compute();
    # After update, this should return TypeInteger TOP instead of generic Top
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
    ok(!$type->is_constant, 'Result is not constant');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: FAIL - returns generic Top, not TypeInteger

**Step 3: Update Add.pm compute() to return IntTop**

In `lib/Chalk/IR/Node/Add.pm`, change the compute() method:

```perl
    # Type inference for constant folding - if both inputs are constant, compute sum
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            return Chalk::IR::Type::TypeInteger->constant(
                $left_type->value + $right_type->value
            );
        }

        # If either operand is an integer type, result is unknown integer
        if (($left_type isa Chalk::IR::Type::TypeInteger) ||
            ($right_type isa Chalk::IR::Type::TypeInteger)) {
            return Chalk::IR::Type::TypeInteger->TOP;
        }

        return Chalk::IR::Type::Top->top();
    }
```

**Step 4: Run test to verify it passes**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Add.pm t/sea-of-nodes/compute.t
git commit -m "feat(Add): return IntTop for unknown integer addition"
```

---

## Task 4: Update Subtract Node compute() to Return IntTop

**Files:**
- Modify: `lib/Chalk/IR/Node/Subtract.pm`
- Modify: `t/sea-of-nodes/compute.t`

**Step 1: Write failing test for Subtract with unknown integers returning IntTop**

Add to `t/sea-of-nodes/compute.t` after the existing Subtract subtests:

```perl
subtest 'Subtract node compute() with unknown integer returns IntTop' => sub {
    my $const10 = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $sub = Chalk::IR::Node::Subtract->new(left => $const10, right => $unknown);

    my $type = $sub->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: FAIL - returns generic Top, not TypeInteger

**Step 3: Update Subtract.pm compute() to return IntTop**

Read and update `lib/Chalk/IR/Node/Subtract.pm` compute() method similarly to Add.

**Step 4: Run test to verify it passes**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Subtract.pm t/sea-of-nodes/compute.t
git commit -m "feat(Subtract): return IntTop for unknown integer subtraction"
```

---

## Task 5: Update Multiply Node compute() to Return IntTop

**Files:**
- Modify: `lib/Chalk/IR/Node/Multiply.pm`
- Modify: `t/sea-of-nodes/compute.t`

**Step 1: Write failing test for Multiply with unknown integers returning IntTop**

Add to `t/sea-of-nodes/compute.t` after the existing Multiply subtests:

```perl
subtest 'Multiply node compute() with unknown integer returns IntTop' => sub {
    my $const6 = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $mul = Chalk::IR::Node::Multiply->new(left => $const6, right => $unknown);

    my $type = $mul->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: FAIL - returns generic Top, not TypeInteger

**Step 3: Update Multiply.pm compute() to return IntTop**

Read and update `lib/Chalk/IR/Node/Multiply.pm` compute() method similarly to Add.

**Step 4: Run test to verify it passes**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Multiply.pm t/sea-of-nodes/compute.t
git commit -m "feat(Multiply): return IntTop for unknown integer multiplication"
```

---

## Task 6: Update Divide Node compute() to Return IntTop and IntBot

**Files:**
- Modify: `lib/Chalk/IR/Node/Divide.pm`
- Modify: `t/sea-of-nodes/compute.t`

**Step 1: Write failing tests for Divide returning IntTop and IntBot**

Add to `t/sea-of-nodes/compute.t` after the existing Divide subtests:

```perl
subtest 'Divide node compute() with unknown integer returns IntTop' => sub {
    my $const20 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $div = Chalk::IR::Node::Divide->new(left => $const20, right => $unknown);

    my $type = $div->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when one input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
};

subtest 'Divide node compute() with zero divisor returns IntBot' => sub {
    my $const20 = Chalk::IR::Node::Constant->new(value => 20, type => 'Integer');
    my $const0 = Chalk::IR::Node::Constant->new(value => 0, type => 'Integer');
    my $div = Chalk::IR::Node::Divide->new(left => $const20, right => $const0);

    my $type = $div->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger for div by zero');
    ok($type->is_bottom, 'Result is IntBot (error state)');
    ok(!$type->is_constant, 'Result is not constant');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: FAIL - returns generic Top for both cases

**Step 3: Update Divide.pm compute() to return IntTop/IntBot**

In `lib/Chalk/IR/Node/Divide.pm`, change the compute() method:

```perl
    # Type inference for constant folding - if both inputs are constant, compute quotient
    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $divisor = $right_type->value;
            # Division by zero yields IntBot (error state)
            return Chalk::IR::Type::TypeInteger->BOTTOM if $divisor == 0;
            return Chalk::IR::Type::TypeInteger->constant(
                int($left_type->value / $divisor)
            );
        }

        # If either operand is an integer type, result is unknown integer
        if (($left_type isa Chalk::IR::Type::TypeInteger) ||
            ($right_type isa Chalk::IR::Type::TypeInteger)) {
            return Chalk::IR::Type::TypeInteger->TOP;
        }

        return Chalk::IR::Type::Top->top();
    }
```

**Step 4: Run test to verify it passes**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Divide.pm t/sea-of-nodes/compute.t
git commit -m "feat(Divide): return IntBot for div-by-zero, IntTop for unknown"
```

---

## Task 7: Update Negate Node compute() to Return IntTop

**Files:**
- Modify: `lib/Chalk/IR/Node/Negate.pm`
- Modify: `t/sea-of-nodes/compute.t`

**Step 1: Write failing test for Negate with unknown integer returning IntTop**

Add to `t/sea-of-nodes/compute.t` after the existing Negate subtests:

```perl
subtest 'Negate node compute() with unknown integer returns IntTop' => sub {
    my $unknown = Chalk::IR::Node::Base->new(inputs => []);
    my $neg = Chalk::IR::Node::Negate->new(operand => $unknown);

    my $type = $neg->compute();
    ok($type isa Chalk::IR::Type::TypeInteger, 'compute() returns TypeInteger when input is unknown');
    ok($type->is_top, 'Result is IntTop (unknown integer)');
};
```

**Step 2: Run test to verify it fails**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: FAIL - returns generic Top, not TypeInteger

**Step 3: Update Negate.pm compute() to return IntTop**

Read and update `lib/Chalk/IR/Node/Negate.pm` compute() method similarly.

**Step 4: Run test to verify it passes**

Run: `./prove t/sea-of-nodes/compute.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Negate.pm t/sea-of-nodes/compute.t
git commit -m "feat(Negate): return IntTop for unknown integer negation"
```

---

## Task 8: Run Full Test Suite and Create PR

**Files:**
- None (verification only)

**Step 1: Run full test suite**

Run: `./prove`
Expected: All tests PASS

**Step 2: Create Pull Request**

```bash
git push origin HEAD:feature/issue-216-typeinteger-lattice
gh pr create --title "feat: Add IntTop/IntBot to TypeInteger for type lattice completeness (#216)" --body "$(cat <<'EOF'
## Summary
- Enhances TypeInteger to support full type lattice with IntTop (unknown integer) and IntBot (error state)
- Updates arithmetic node compute() methods to return IntTop when operating on unknown integers
- Divide node returns IntBot for division by zero instead of generic Top

## Test plan
- [x] TypeInteger TOP/BOTTOM singleton tests
- [x] Add/Subtract/Multiply return IntTop for unknown inputs
- [x] Divide returns IntBot for division by zero
- [x] Negate returns IntTop for unknown inputs
- [x] All existing tests pass

Closes #216
EOF
)"
```

---

## Summary

This plan implements the TypeInteger lattice enhancement in 8 tasks:

1. **Task 1**: Add IntTop support with `TOP()` singleton and `is_top()` method
2. **Task 2**: Add IntBot tests (implementation done in Task 1)
3. **Task 3**: Update Add node to return IntTop for unknown integers
4. **Task 4**: Update Subtract node to return IntTop for unknown integers
5. **Task 5**: Update Multiply node to return IntTop for unknown integers
6. **Task 6**: Update Divide node to return IntTop/IntBot appropriately
7. **Task 7**: Update Negate node to return IntTop for unknown integers
8. **Task 8**: Full test suite verification and PR creation

Each task follows strict TDD: write failing test, run to confirm failure, implement minimal code, run to confirm pass, commit.
