# Type System Stage 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add flow-sensitive type tracking through all expressions, enabling type-aware optimization and future XS code generation.

**Architecture:** Eager type caching on nodes (default Top) with lazy `compute_type()` for authoritative inference. Flow-sensitive typing where variable type = most recent assignment. Union types at control flow merge (Phi nodes).

**Tech Stack:** Perl 5.42, Object::Pad-style classes, existing Type lattice (Integer, Float, Bool, Top, Bottom)

**Design Doc:** `docs/plans/2025-12-17-type-system-stage1-design.md`

**Related Issues:** #367, #368, #369, #370, #313

---

## Task 1: Add Type Field to Node Base Class

**Files:**
- Modify: `lib/Chalk/IR/Node.pm:39-45`
- Test: `t/ir/node-type-field.t` (create)

**Step 1: Write the failing test**

Create `t/ir/node-type-field.t`:

```perl
# ABOUTME: Test that IR nodes have a type field with proper default
# ABOUTME: Validates type field infrastructure for type system integration

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Integer;

# Test 1: Node has type field defaulting to Top
subtest 'Node type field defaults to Top' => sub {
    my $node = Chalk::IR::Node->new(
        id => 'test_1',
        op => 'TestOp',
        inputs => [],
        attributes => {},
    );

    ok($node->can('type'), 'Node has type accessor');
    my $type = $node->type;
    ok($type isa Chalk::IR::Type::Top, 'Default type is Top');
};

# Test 2: Node accepts explicit type parameter
subtest 'Node accepts type parameter' => sub {
    my $int_type = Chalk::IR::Type::Integer->TOP();
    my $node = Chalk::IR::Node->new(
        id => 'test_2',
        op => 'TestOp',
        inputs => [],
        attributes => {},
        type => $int_type,
    );

    my $type = $node->type;
    ok($type isa Chalk::IR::Type::Integer, 'Explicit type preserved');
};

# Test 3: compute_type returns cached type by default
subtest 'compute_type returns cached type' => sub {
    my $int_type = Chalk::IR::Type::Integer->constant(42);
    my $node = Chalk::IR::Node->new(
        id => 'test_3',
        op => 'TestOp',
        inputs => [],
        attributes => {},
        type => $int_type,
    );

    ok($node->can('compute_type'), 'Node has compute_type method');
    my $computed = $node->compute_type;
    is($computed, $int_type, 'compute_type returns cached type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/node-type-field.t`
Expected: FAIL - Node doesn't have type field yet

**Step 3: Add type field to Node.pm**

In `lib/Chalk/IR/Node.pm`, add after line 44 (`field $transform_chain`):

```perl
    field $type           :param :reader = Chalk::IR::Type::Top->top();
```

Add at top of file (after existing use statements):

```perl
use Chalk::IR::Type::Top;
```

Add method after `get_deps()`:

```perl
    # Return type for this node - subclasses override for inference
    method compute_type() {
        return $type;
    }
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/node-type-field.t`
Expected: PASS (3 subtests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node.pm t/ir/node-type-field.t
git commit -m "feat(types): Add type field to Node base class (#367)

- Add \$type field with default Top
- Add compute_type() method returning cached type
- Subclasses will override compute_type() for inference"
```

---

## Task 2: Create Union Type Class

**Files:**
- Create: `lib/Chalk/IR/Type/Union.pm`
- Test: `t/ir/type-union.t` (create)

**Step 1: Write the failing test**

Create `t/ir/type-union.t`:

```perl
# ABOUTME: Test for Union type representing multiple possible types
# ABOUTME: Used at control flow merge points (Phi nodes)

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Type::Union;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

# Test 1: Union creation with multiple types
subtest 'Union creation' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();

    my $union = Chalk::IR::Type::Union->new(members => [$int, $float]);

    ok($union isa Chalk::IR::Type::Union, 'Union created');
    is(scalar($union->members->@*), 2, 'Union has 2 members');
};

# Test 2: Union contains check
subtest 'Union contains' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();
    my $union = Chalk::IR::Type::Union->new(members => [$int, $float]);

    ok($union->contains($int), 'Union contains Integer');
    ok($union->contains($float), 'Union contains Float');

    my $top = Chalk::IR::Type::Top->top();
    ok(!$union->contains($top), 'Union does not contain Top');
};

# Test 3: Union meet (intersection)
subtest 'Union meet' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();
    my $union1 = Chalk::IR::Type::Union->new(members => [$int, $float]);

    # Meet with one of its members narrows to that member
    my $result = $union1->meet($int);
    ok($result isa Chalk::IR::Type::Integer, 'Meet with member narrows');
};

# Test 4: Union of unions flattens
subtest 'Union flattening' => sub {
    my $int = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->TOP();
    my $union1 = Chalk::IR::Type::Union->new(members => [$int]);
    my $union2 = Chalk::IR::Type::Union->new(members => [$float]);

    my $combined = Chalk::IR::Type::Union->new(members => [$union1, $union2]);
    # Should flatten: Union(Union(Int), Union(Float)) -> Union(Int, Float)
    is(scalar($combined->members->@*), 2, 'Nested unions flatten');
};

# Test 5: is_constant returns false
subtest 'Union is not constant' => sub {
    my $const_int = Chalk::IR::Type::Integer->constant(42);
    my $const_float = Chalk::IR::Type::Float->constant(3.14);
    my $union = Chalk::IR::Type::Union->new(members => [$const_int, $const_float]);

    ok(!$union->is_constant, 'Union is never constant');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/type-union.t`
Expected: FAIL - Can't locate Chalk/IR/Type/Union.pm

**Step 3: Create Union.pm**

Create `lib/Chalk/IR/Type/Union.pm`:

```perl
# ABOUTME: Union type representing multiple possible types at a program point
# ABOUTME: Used at control flow merge points (Phi nodes) and uncertain contexts

use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Type::Union {
    field @members :param :reader;

    ADJUST {
        # Flatten nested unions
        my @flat;
        for my $member (@members) {
            if ($member isa Chalk::IR::Type::Union) {
                push @flat, $member->members->@*;
            } else {
                push @flat, $member;
            }
        }

        # Deduplicate by ref (same type object)
        my %seen;
        @members = grep { !$seen{refaddr($_)}++ } @flat;
    }

    # Check if this union contains a specific type
    method contains($type) {
        for my $member (@members) {
            return 1 if refaddr($member) == refaddr($type);
            # Also check if types are equivalent by class
            return 1 if ref($member) eq ref($type);
        }
        return 0;
    }

    # Meet operation - intersection with another type
    method meet($other) {
        # If other is one of our members, narrow to it
        if ($self->contains($other)) {
            return $other;
        }

        # If other is a union, find common members
        if ($other isa Chalk::IR::Type::Union) {
            my @common;
            for my $my_member (@members) {
                push @common, $my_member if $other->contains($my_member);
            }
            return Chalk::IR::Type::Bottom->bottom() if @common == 0;
            return $common[0] if @common == 1;
            return Chalk::IR::Type::Union->new(members => \@common);
        }

        # No overlap
        return Chalk::IR::Type::Bottom->bottom();
    }

    # Join operation - union with another type
    method join($other) {
        if ($other isa Chalk::IR::Type::Union) {
            return Chalk::IR::Type::Union->new(
                members => [@members, $other->members->@*]
            );
        }
        return Chalk::IR::Type::Union->new(members => [@members, $other]);
    }

    # Union is never constant (even if all members are)
    method is_constant() { return 0; }

    # Union is never top or bottom
    method is_top() { return 0; }
    method is_bottom() { return 0; }

    # String representation for debugging
    method to_string() {
        my @names = map { ref($_) =~ s/.*:://r } @members;
        return join(' | ', @names);
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/type-union.t`
Expected: PASS (5 subtests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/Union.pm t/ir/type-union.t
git commit -m "feat(types): Add Union type for control flow merges (#367)

- Union represents multiple possible types (Int | String)
- Flatten nested unions automatically
- meet() narrows to common types
- join() combines types
- Used by Phi nodes at branch merge points"
```

---

## Task 3: Add compute_type() to Comparison Nodes

**Files:**
- Modify: `lib/Chalk/IR/Node/GT.pm`
- Modify: `lib/Chalk/IR/Node/LT.pm`
- Modify: `lib/Chalk/IR/Node/EQ.pm`
- Modify: `lib/Chalk/IR/Node/NE.pm`
- Modify: `lib/Chalk/IR/Node/GE.pm`
- Modify: `lib/Chalk/IR/Node/LE.pm`
- Test: `t/ir/comparison-types.t` (create)

**Step 1: Write the failing test**

Create `t/ir/comparison-types.t`:

```perl
# ABOUTME: Test that comparison operators return Bool type
# ABOUTME: Part of type inference for expressions (#370)

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::GT;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

# Create test constants
my $const5 = Chalk::IR::Node::Constant->new(
    value => 5,
    type => Chalk::IR::Type::Integer->constant(5),
);
my $const3 = Chalk::IR::Node::Constant->new(
    value => 3,
    type => Chalk::IR::Type::Integer->constant(3),
);

# Test: GT returns Bool
subtest 'GT compute_type returns Bool' => sub {
    my $gt = Chalk::IR::Node::GT->new(left => $const5, right => $const3);
    ok($gt->can('compute_type'), 'GT has compute_type');
    my $type = $gt->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'GT returns Bool type');
};

# Test: LT returns Bool
subtest 'LT compute_type returns Bool' => sub {
    my $lt = Chalk::IR::Node::LT->new(left => $const5, right => $const3);
    my $type = $lt->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'LT returns Bool type');
};

# Test: EQ returns Bool
subtest 'EQ compute_type returns Bool' => sub {
    my $eq = Chalk::IR::Node::EQ->new(left => $const5, right => $const3);
    my $type = $eq->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'EQ returns Bool type');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/comparison-types.t`
Expected: FAIL - compute_type not implemented or returns wrong type

**Step 3: Add compute_type to comparison nodes**

For each comparison node (GT.pm, LT.pm, EQ.pm, NE.pm, GE.pm, LE.pm), add:

```perl
use Chalk::IR::Type::Bool;

# After existing methods, add:
method compute_type() {
    return Chalk::IR::Type::Bool->TOP();
}
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/comparison-types.t`
Expected: PASS (3 subtests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/GT.pm lib/Chalk/IR/Node/LT.pm \
        lib/Chalk/IR/Node/EQ.pm lib/Chalk/IR/Node/NE.pm \
        lib/Chalk/IR/Node/GE.pm lib/Chalk/IR/Node/LE.pm \
        t/ir/comparison-types.t
git commit -m "feat(types): Add compute_type to comparison nodes (#370)

All comparison operators (GT, LT, EQ, NE, GE, LE) now return
Bool type from compute_type(), enabling type-aware optimization."
```

---

## Task 4: Add compute_type() to Remaining Arithmetic Nodes

**Files:**
- Modify: `lib/Chalk/IR/Node/Subtract.pm`
- Modify: `lib/Chalk/IR/Node/Divide.pm`
- Modify: `lib/Chalk/IR/Node/Negate.pm`
- Test: `t/ir/arithmetic-types.t` (create)

**Step 1: Write the failing test**

Create `t/ir/arithmetic-types.t`:

```perl
# ABOUTME: Test type inference for arithmetic operations
# ABOUTME: Part of Operation Type Preservation (#370)

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

my $int5 = Chalk::IR::Node::Constant->new(
    value => 5, type => Chalk::IR::Type::Integer->constant(5));
my $int3 = Chalk::IR::Node::Constant->new(
    value => 3, type => Chalk::IR::Type::Integer->constant(3));
my $float2 = Chalk::IR::Node::Constant->new(
    value => 2.0, type => Chalk::IR::Type::Float->constant(2.0));

# Test: Subtract int - int = int
subtest 'Subtract int-int returns Integer' => sub {
    my $sub = Chalk::IR::Node::Subtract->new(left => $int5, right => $int3);
    ok($sub->can('compute_type'), 'Subtract has compute_type');
    my $type = $sub->compute_type;
    ok($type isa Chalk::IR::Type::Integer, 'Int - Int = Integer');
};

# Test: Divide (always returns Float for safety)
subtest 'Divide returns Float' => sub {
    my $div = Chalk::IR::Node::Divide->new(left => $int5, right => $int3);
    my $type = $div->compute_type;
    ok($type isa Chalk::IR::Type::Float, 'Divide returns Float');
};

# Test: Negate preserves type
subtest 'Negate preserves operand type' => sub {
    my $neg = Chalk::IR::Node::Negate->new(operand => $int5);
    my $type = $neg->compute_type;
    ok($type isa Chalk::IR::Type::Integer, 'Negate Int = Integer');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/arithmetic-types.t`
Expected: FAIL - compute_type not implemented

**Step 3: Add compute_type to arithmetic nodes**

In `lib/Chalk/IR/Node/Subtract.pm`, add (similar pattern to Add.pm):

```perl
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

method compute_type() {
    my $left_type = $left->can('compute_type') ? $left->compute_type() : $left->type;
    my $right_type = $right->can('compute_type') ? $right->compute_type() : $right->type;

    my $widened_left = $left_type->can('widen') ? $left_type->widen($right_type) : $left_type;
    my $widened_right = $right_type->can('widen') ? $right_type->widen($left_type) : $right_type;
    return $widened_left->meet($widened_right);
}
```

In `lib/Chalk/IR/Node/Divide.pm`:

```perl
use Chalk::IR::Type::Float;

method compute_type() {
    # Division always returns Float (even 6/2 = 3.0 in type system)
    return Chalk::IR::Type::Float->TOP();
}
```

In `lib/Chalk/IR/Node/Negate.pm`:

```perl
method compute_type() {
    return $operand->can('compute_type') ? $operand->compute_type() : $operand->type;
}
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/arithmetic-types.t`
Expected: PASS (3 subtests)

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Subtract.pm lib/Chalk/IR/Node/Divide.pm \
        lib/Chalk/IR/Node/Negate.pm t/ir/arithmetic-types.t
git commit -m "feat(types): Add compute_type to Subtract, Divide, Negate (#370)

- Subtract uses widen+meet like Add
- Divide always returns Float (safe for division)
- Negate preserves operand type"
```

---

## Task 5: Add compute_type() to Logical Nodes

**Files:**
- Modify: `lib/Chalk/IR/Node/Not.pm`
- Test: `t/ir/logical-types.t` (create)

**Step 1: Write the failing test**

Create `t/ir/logical-types.t`:

```perl
# ABOUTME: Test type inference for logical operations
# ABOUTME: Part of Operation Type Preservation (#370)

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Not;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

my $int5 = Chalk::IR::Node::Constant->new(
    value => 5, type => Chalk::IR::Type::Integer->constant(5));

# Test: Not returns Bool
subtest 'Not returns Bool' => sub {
    my $not = Chalk::IR::Node::Not->new(operand => $int5);
    ok($not->can('compute_type'), 'Not has compute_type');
    my $type = $not->compute_type;
    ok($type isa Chalk::IR::Type::Bool, 'Not returns Bool');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/logical-types.t`
Expected: FAIL

**Step 3: Add compute_type to Not.pm**

```perl
use Chalk::IR::Type::Bool;

method compute_type() {
    return Chalk::IR::Type::Bool->TOP();
}
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/logical-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Not.pm t/ir/logical-types.t
git commit -m "feat(types): Add compute_type to Not node (#370)

Logical Not always returns Bool type."
```

---

## Task 6: Phi Node Union Type Inference

**Files:**
- Modify: `lib/Chalk/IR/Node/Phi.pm`
- Test: `t/ir/phi-types.t` (create)

**Step 1: Write the failing test**

Create `t/ir/phi-types.t`:

```perl
# ABOUTME: Test Phi node computes union of incoming types
# ABOUTME: Core to flow-sensitive typing at merge points

use lib 'lib';
use v5.42;
use Test::More;

use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Region;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Union;

# Create constants of different types
my $int5 = Chalk::IR::Node::Constant->new(
    value => 5, type => Chalk::IR::Type::Integer->constant(5));
my $float3 = Chalk::IR::Node::Constant->new(
    value => 3.0, type => Chalk::IR::Type::Float->constant(3.0));

# Create a region for the Phi
my $region = Chalk::IR::Node::Region->new(
    inputs => [],
);

# Test: Phi with same types returns that type
subtest 'Phi same types returns single type' => sub {
    my $int3 = Chalk::IR::Node::Constant->new(
        value => 3, type => Chalk::IR::Type::Integer->constant(3));

    my $phi = Chalk::IR::Node::Phi->new(
        region => $region,
        inputs => [$int5, $int3],
    );

    ok($phi->can('compute_type'), 'Phi has compute_type');
    my $type = $phi->compute_type;
    ok($type isa Chalk::IR::Type::Integer, 'Phi(Int, Int) = Integer');
};

# Test: Phi with different types returns union
subtest 'Phi different types returns union' => sub {
    my $phi = Chalk::IR::Node::Phi->new(
        region => $region,
        inputs => [$int5, $float3],
    );

    my $type = $phi->compute_type;
    ok($type isa Chalk::IR::Type::Union, 'Phi(Int, Float) = Union');
    ok($type->contains(Chalk::IR::Type::Integer->TOP()), 'Union contains Int');
    ok($type->contains(Chalk::IR::Type::Float->TOP()), 'Union contains Float');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/phi-types.t`
Expected: FAIL

**Step 3: Add compute_type to Phi.pm**

```perl
use Chalk::IR::Type::Union;

method compute_type() {
    return Chalk::IR::Type::Top->top() unless @inputs;

    # Collect types from all inputs
    my @types;
    for my $input (@inputs) {
        next unless defined $input;
        my $t = $input->can('compute_type') ? $input->compute_type() :
                $input->can('type') ? $input->type :
                Chalk::IR::Type::Top->top();
        push @types, $t;
    }

    return Chalk::IR::Type::Top->top() unless @types;
    return $types[0] if @types == 1;

    # Check if all types are the same class
    my $first_class = ref($types[0]);
    my $all_same = 1;
    for my $t (@types[1..$#types]) {
        if (ref($t) ne $first_class) {
            $all_same = 0;
            last;
        }
    }

    # Same type class: meet them
    if ($all_same) {
        my $result = $types[0];
        for my $t (@types[1..$#types]) {
            $result = $result->meet($t);
        }
        return $result;
    }

    # Different types: create union
    return Chalk::IR::Type::Union->new(members => \@types);
}
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/phi-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Phi.pm t/ir/phi-types.t
git commit -m "feat(types): Phi node computes union of incoming types (#367)

At control flow merge points, Phi returns:
- Single type if all inputs have same type class
- Union type if inputs have different types
- Core to flow-sensitive type inference"
```

---

## Task 7: Create GitHub Milestone

**Step 1: Create milestone**

```bash
gh api repos/{owner}/{repo}/milestones -f title="Type System Stage 1" \
  -f description="Flow-sensitive type tracking through expressions. Issues: #367, #368, #369, #370, #313" \
  -f state="open"
```

**Step 2: Add issues to milestone**

```bash
gh issue edit 367 --milestone "Type System Stage 1"
gh issue edit 368 --milestone "Type System Stage 1"
gh issue edit 369 --milestone "Type System Stage 1"
gh issue edit 370 --milestone "Type System Stage 1"
gh issue edit 313 --milestone "Type System Stage 1"
```

**Step 3: Commit plan**

```bash
git add docs/plans/2025-12-17-type-system-stage1-implementation.md
git commit -m "docs: Type System Stage 1 implementation plan

Detailed TDD implementation plan for:
- Task 1: Add type field to Node base class
- Task 2: Create Union type class
- Task 3-5: Add compute_type to all operation nodes
- Task 6: Phi node union inference
- Task 7: GitHub milestone setup"
```

---

## Summary

| Task | Description | Files | Tests |
|------|-------------|-------|-------|
| 1 | Type field on Node | Node.pm | node-type-field.t |
| 2 | Union type class | Type/Union.pm | type-union.t |
| 3 | Comparison types | GT,LT,EQ,NE,GE,LE.pm | comparison-types.t |
| 4 | Arithmetic types | Subtract,Divide,Negate.pm | arithmetic-types.t |
| 5 | Logical types | Not.pm | logical-types.t |
| 6 | Phi union inference | Phi.pm | phi-types.t |
| 7 | GitHub milestone | - | - |

**Estimated time:** 2-3 hours with TDD
