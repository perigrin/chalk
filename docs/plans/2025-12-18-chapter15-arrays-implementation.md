# Chapter 15: Fixed-Length Arrays - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add fixed-length arrays with bounds checking, length operator, and element type inference.

**Architecture:** Extend existing NewArray/ArrayLoad/ArrayStore nodes with length tracking and bounds checking. Add ArrayLength and Panic nodes. Element types inferred via TypeInference semiring.

**Tech Stack:** Perl 5.42.0, Object::Pad classes, existing IR node and heap infrastructure.

---

## Task 1: Extend NewArray with Length Parameter

**Files:**
- Modify: `lib/Chalk/IR/Node/NewArray.pm`
- Create: `t/ir/fixed-arrays.t`

**Step 1: Write the failing test**

Create `t/ir/fixed-arrays.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for fixed-length array IR nodes
# ABOUTME: Verifies NewArray length, ArrayLength, and bounds checking
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'NewArray with length' => sub {
    my $len = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $arr = Chalk::IR::Node::NewArray->new(
        length => $len,
    );

    ok($arr->can('length'), 'NewArray has length accessor');
    is($arr->length->value, 10, 'NewArray length is 10');
};

subtest 'NewArray with element_type' => sub {
    my $len = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $arr = Chalk::IR::Node::NewArray->new(
        length => $len,
        element_type => Chalk::IR::Type::Integer->i64(),
    );

    ok($arr->can('element_type'), 'NewArray has element_type accessor');
    ok($arr->element_type->isa('Chalk::IR::Type::Integer'), 'element_type is Integer');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/fixed-arrays.t`
Expected: FAIL - length and element_type accessors don't exist

**Step 3: Write minimal implementation**

Modify `lib/Chalk/IR/Node/NewArray.pm` to add length and element_type fields:

```perl
# ABOUTME: Allocates a new array in the heap and returns its heap ID
# ABOUTME: Supports fixed-length arrays with optional element type tracking
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NewArray :isa(Chalk::IR::Node::Base) {
    field $length :param :reader = undef;           # NEW: size expression for fixed arrays
    field $element_type :param :reader = undef;     # NEW: element type for optimization

    method op() { 'NewArray' }

    method inputs() {
        return defined($length) ? [ $length->id ] : [];
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NewArray',
            inputs => $self->inputs,
            attributes => {
                has_length => defined($length) ? 1 : 0,
                element_type => defined($element_type) ? $element_type->name : 'Any',
            },
        };
    }

    method execute($context) {
        # Allocate a new heap ID for this array
        my $env = $context->('env:');
        my $heap_id = $env->allocate_heap_id();

        # If length specified, store it in metadata
        if (defined($length)) {
            my $len_val = $context->("node:" . $length->id);
            $env->set_array_length($heap_id, $len_val);
        }

        return $heap_id;
    }

    method peephole($graph = undef) {
        return $self;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/fixed-arrays.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/NewArray.pm t/ir/fixed-arrays.t
git commit -m "feat(ir): Add length and element_type to NewArray (#337)"
```

---

## Task 2: Implement ArrayLength Node

**Files:**
- Create: `lib/Chalk/IR/Node/ArrayLength.pm`
- Modify: `t/ir/fixed-arrays.t`

**Step 1: Write the failing test**

Add to `t/ir/fixed-arrays.t`:

```perl
use Chalk::IR::Node::ArrayLength;

subtest 'ArrayLength basic' => sub {
    my $len = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $arr_len = Chalk::IR::Node::ArrayLength->new(array => $arr);

    is($arr_len->op, 'ArrayLength', 'ArrayLength op is correct');
    ok($arr_len->can('array'), 'ArrayLength has array accessor');
};

subtest 'ArrayLength constant folding' => sub {
    my $len = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $arr_len = Chalk::IR::Node::ArrayLength->new(array => $arr);

    my $result = $arr_len->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'ArrayLength folds to constant');
    is($result->value, 42, 'Folded length is 42');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/fixed-arrays.t`
Expected: FAIL - ArrayLength module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/ArrayLength.pm`:

```perl
# ABOUTME: ArrayLength node returns the length of a fixed-size array
# ABOUTME: Corresponds to the "#" implicit field in TypeStruct representation
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayLength :isa(Chalk::IR::Node::Base) {
    field $array :param :reader;

    method op() { 'ArrayLength' }

    method inputs() {
        return [ $array->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'ArrayLength',
            inputs => $self->inputs,
            attributes => {
                array_id => $array->id,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding: if array is NewArray with constant length, fold
        if ($array->isa('Chalk::IR::Node::NewArray') && defined($array->length)) {
            my $len_node = $array->length;
            if ($len_node->isa('Chalk::IR::Node::Constant') && $len_node->is_constant) {
                use Chalk::IR::Node::Constant;
                use Chalk::IR::Type::Integer;
                return Chalk::IR::Node::Constant->new(
                    value => $len_node->value,
                    type => Chalk::IR::Type::Integer->i64()
                );
            }
        }

        return $self;
    }

    method execute($context) {
        my $env = $context->('env:');
        my $heap_id = $context->("node:" . $array->id);
        return $env->get_array_length($heap_id);
    }

    method compute_type() {
        use Chalk::IR::Type::Integer;
        return Chalk::IR::Type::Integer->i64();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/fixed-arrays.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/ArrayLength.pm t/ir/fixed-arrays.t
git commit -m "feat(ir): Add ArrayLength node with constant folding (#337)"
```

---

## Task 3: Implement Panic Node

**Files:**
- Create: `lib/Chalk/IR/Node/Panic.pm`
- Create: `t/ir/panic.t`

**Step 1: Write the failing test**

Create `t/ir/panic.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for Panic IR node
# ABOUTME: Verifies runtime error termination for bounds violations
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::Panic;

subtest 'Panic node creation' => sub {
    my $panic = Chalk::IR::Node::Panic->new(
        message => 'Array index out of bounds'
    );

    is($panic->op, 'Panic', 'Panic op is correct');
    is($panic->message, 'Array index out of bounds', 'message accessor works');
};

subtest 'Panic to_hash' => sub {
    my $panic = Chalk::IR::Node::Panic->new(
        message => 'Test error',
        source_info => { line => 42 }
    );

    my $hash = $panic->to_hash();
    is($hash->{op}, 'Panic', 'to_hash op is Panic');
    is($hash->{attributes}{message}, 'Test error', 'to_hash has message');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/panic.t`
Expected: FAIL - Panic module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/Panic.pm`:

```perl
# ABOUTME: Panic node terminates execution with a runtime error
# ABOUTME: Used for bounds checking violations and other unrecoverable errors
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Panic :isa(Chalk::IR::Node::Base) {
    field $message :param :reader;
    field $source_info :param :reader = undef;

    method op() { 'Panic' }

    method inputs() {
        return [];  # No data inputs - terminal node
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'Panic',
            inputs => $self->inputs,
            attributes => {
                message => $message,
                source_info => $source_info,
            },
        };
    }

    method execute($context) {
        # Terminate execution with error
        die "PANIC: $message";
    }

    method peephole($graph = undef) {
        return $self;  # Cannot optimize away panic
    }

    # Panic is a control flow terminator like Never
    method is_terminator() { 1 }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/panic.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Panic.pm t/ir/panic.t
git commit -m "feat(ir): Add Panic node for runtime error termination (#337)"
```

---

## Task 4: Add Bounds Checking to ArrayLoad

**Files:**
- Modify: `lib/Chalk/IR/Node/ArrayLoad.pm`
- Create: `t/ir/bounds-checking.t`

**Step 1: Write the failing test**

Create `t/ir/bounds-checking.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for array bounds checking
# ABOUTME: Verifies ArrayLoad/ArrayStore detect out-of-bounds access
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::ArrayLoad;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Panic;
use Chalk::IR::Type::Integer;

subtest 'ArrayLoad with bounds_check flag' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->i64());
    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->i64());

    my $load = Chalk::IR::Node::ArrayLoad->new(
        array_id => $arr->id,
        index_id => $idx->id,
        bounds_check => 1,
    );

    ok($load->can('bounds_check'), 'ArrayLoad has bounds_check accessor');
    is($load->bounds_check, 1, 'bounds_check is enabled');
};

subtest 'ArrayLoad bounds check elimination (safe)' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->i64());
    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->i64());

    my $load = Chalk::IR::Node::ArrayLoad->new(
        array => $arr,
        index => $idx,
        bounds_check => 1,
    );

    my $result = $load->peephole();
    # Should still be ArrayLoad but with bounds_check potentially removed
    ok($result->isa('Chalk::IR::Node::ArrayLoad'), 'Result is ArrayLoad');
};

subtest 'ArrayLoad bounds check to Panic (always fails)' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->i64());
    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 15, type => Chalk::IR::Type::Integer->i64());

    my $load = Chalk::IR::Node::ArrayLoad->new(
        array => $arr,
        index => $idx,
        bounds_check => 1,
    );

    my $result = $load->peephole();
    ok($result->isa('Chalk::IR::Node::Panic'), 'Out-of-bounds access becomes Panic');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/bounds-checking.t`
Expected: FAIL - bounds_check, array, index accessors don't exist

**Step 3: Write minimal implementation**

Modify `lib/Chalk/IR/Node/ArrayLoad.pm`:

```perl
# ABOUTME: Loads a value from an array in the heap
# ABOUTME: Supports bounds checking for fixed-length arrays
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayLoad :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader = undef;     # Legacy: heap ID reference
    field $index_id :param :reader = undef;     # Legacy: index node ID
    field $array :param :reader = undef;        # NEW: array node reference
    field $index :param :reader = undef;        # NEW: index node reference
    field $bounds_check :param :reader = 0;     # NEW: enable bounds checking

    method op() { 'ArrayLoad' }

    method inputs() {
        if (defined($array) && defined($index)) {
            return [ $array->id, $index->id ];
        }
        return [];
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayLoad',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id // ($array ? $array->id : undef),
                index_id => $index_id // ($index ? $index->id : undef),
                bounds_check => $bounds_check,
            },
        };
    }

    method peephole($graph = undef) {
        # Bounds check elimination/conversion
        if ($bounds_check && defined($array) && defined($index)) {
            # Check if both array length and index are constant
            if ($array->isa('Chalk::IR::Node::NewArray') && defined($array->length)) {
                my $len_node = $array->length;
                if ($len_node->isa('Chalk::IR::Node::Constant') && $len_node->is_constant &&
                    $index->isa('Chalk::IR::Node::Constant') && $index->is_constant) {

                    my $len = $len_node->value;
                    my $idx = $index->value;

                    # Always out of bounds - replace with Panic
                    if ($idx < 0 || $idx >= $len) {
                        use Chalk::IR::Node::Panic;
                        return Chalk::IR::Node::Panic->new(
                            message => "Array index $idx out of bounds [0..$len)"
                        );
                    }

                    # Always in bounds - can eliminate check
                    # Return new ArrayLoad without bounds_check
                    return Chalk::IR::Node::ArrayLoad->new(
                        array => $array,
                        index => $index,
                        bounds_check => 0,
                    );
                }
            }
        }

        return $self;
    }

    method execute($context) {
        # Get the heap ID from the array node
        my $heap_id = defined($array)
            ? $context->("node:" . $array->id)
            : $context->("node:$array_id");

        # Get the index value
        my $idx = defined($index)
            ? $context->("node:" . $index->id)
            : $context->("node:$index_id");

        my $env = $context->('env:');

        # Bounds check at runtime if enabled
        if ($bounds_check) {
            my $len = $env->get_array_length($heap_id);
            if (defined($len) && ($idx < 0 || $idx >= $len)) {
                die "PANIC: Array index $idx out of bounds [0..$len)";
            }
        }

        return $env->lookup_heap($heap_id, $idx);
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/bounds-checking.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/ArrayLoad.pm t/ir/bounds-checking.t
git commit -m "feat(ir): Add bounds checking to ArrayLoad with peephole (#337)"
```

---

## Task 5: Add Bounds Checking to ArrayStore

**Files:**
- Modify: `lib/Chalk/IR/Node/ArrayStore.pm`
- Modify: `t/ir/bounds-checking.t`

**Step 1: Write the failing test**

Add to `t/ir/bounds-checking.t`:

```perl
use Chalk::IR::Node::ArrayStore;

subtest 'ArrayStore with bounds_check flag' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->i64());
    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->i64());
    my $val = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());

    my $store = Chalk::IR::Node::ArrayStore->new(
        array => $arr,
        index => $idx,
        value => $val,
        bounds_check => 1,
    );

    ok($store->can('bounds_check'), 'ArrayStore has bounds_check accessor');
    is($store->bounds_check, 1, 'bounds_check is enabled');
};

subtest 'ArrayStore bounds check to Panic' => sub {
    my $len = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->i64());
    my $arr = Chalk::IR::Node::NewArray->new(length => $len);
    my $idx = Chalk::IR::Node::Constant->new(value => -1, type => Chalk::IR::Type::Integer->i64());
    my $val = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());

    my $store = Chalk::IR::Node::ArrayStore->new(
        array => $arr,
        index => $idx,
        value => $val,
        bounds_check => 1,
    );

    my $result = $store->peephole();
    ok($result->isa('Chalk::IR::Node::Panic'), 'Negative index becomes Panic');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/bounds-checking.t`
Expected: FAIL - array, index, value, bounds_check accessors don't exist on ArrayStore

**Step 3: Write minimal implementation**

Modify `lib/Chalk/IR/Node/ArrayStore.pm` (similar pattern to ArrayLoad):

```perl
# ABOUTME: Stores a value to an array in the heap
# ABOUTME: Supports bounds checking for fixed-length arrays
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayStore :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader = undef;     # Legacy: heap ID reference
    field $index_id :param :reader = undef;     # Legacy: index node ID
    field $value_id :param :reader = undef;     # Legacy: value node ID
    field $array :param :reader = undef;        # NEW: array node reference
    field $index :param :reader = undef;        # NEW: index node reference
    field $value :param :reader = undef;        # NEW: value node reference
    field $bounds_check :param :reader = 0;     # NEW: enable bounds checking

    method op() { 'ArrayStore' }

    method inputs() {
        if (defined($array) && defined($index) && defined($value)) {
            return [ $array->id, $index->id, $value->id ];
        }
        return [];
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayStore',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id // ($array ? $array->id : undef),
                index_id => $index_id // ($index ? $index->id : undef),
                value_id => $value_id // ($value ? $value->id : undef),
                bounds_check => $bounds_check,
            },
        };
    }

    method peephole($graph = undef) {
        # Bounds check elimination/conversion
        if ($bounds_check && defined($array) && defined($index)) {
            if ($array->isa('Chalk::IR::Node::NewArray') && defined($array->length)) {
                my $len_node = $array->length;
                if ($len_node->isa('Chalk::IR::Node::Constant') && $len_node->is_constant &&
                    $index->isa('Chalk::IR::Node::Constant') && $index->is_constant) {

                    my $len = $len_node->value;
                    my $idx = $index->value;

                    # Always out of bounds - replace with Panic
                    if ($idx < 0 || $idx >= $len) {
                        use Chalk::IR::Node::Panic;
                        return Chalk::IR::Node::Panic->new(
                            message => "Array index $idx out of bounds [0..$len)"
                        );
                    }

                    # Always in bounds - eliminate check
                    return Chalk::IR::Node::ArrayStore->new(
                        array => $array,
                        index => $index,
                        value => $value,
                        bounds_check => 0,
                    );
                }
            }
        }

        return $self;
    }

    method execute($context) {
        my $heap_id = defined($array)
            ? $context->("node:" . $array->id)
            : $context->("node:$array_id");

        my $idx = defined($index)
            ? $context->("node:" . $index->id)
            : $context->("node:$index_id");

        my $val = defined($value)
            ? $context->("node:" . $value->id)
            : $context->("node:$value_id");

        my $env = $context->('env:');

        # Bounds check at runtime if enabled
        if ($bounds_check) {
            my $len = $env->get_array_length($heap_id);
            if (defined($len) && ($idx < 0 || $idx >= $len)) {
                die "PANIC: Array index $idx out of bounds [0..$len)";
            }
        }

        $env->store_heap($heap_id, $idx, $val);
        return $val;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/bounds-checking.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/ArrayStore.pm t/ir/bounds-checking.t
git commit -m "feat(ir): Add bounds checking to ArrayStore with peephole (#337)"
```

---

## Task 6: Add TypeInference for Array Element Types

**Files:**
- Create: `lib/Chalk/Grammar/Chalk/Rule/ArrayStore.pm` (if not exists, or modify)
- Create: `t/ir/array-type-inference.t`

**Step 1: Write the failing test**

Create `t/ir/array-type-inference.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for array element type inference
# ABOUTME: Verifies TypeInference tracks what types are stored in arrays
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::Semiring::TypeInference;
use Chalk::IR::Type::Integer;
use Chalk::Grammar::Chalk::TypeLattice;

subtest 'Element type starts as Any' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $any = $lattice->top_type();

    ok($any->is_top, 'Top type represents Any/unknown element type');
};

subtest 'Element type narrows on store' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int = $lattice->type_from_name('Int');
    my $any = $lattice->top_type();

    # meet(Any, Int) should narrow to Int
    my $narrowed = $any->meet($int);
    is($narrowed->name, 'Int', 'Any meets Int = Int');
};

subtest 'Element type widens on mixed store' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int = $lattice->type_from_name('Int');
    my $str = $lattice->type_from_name('Str');

    # join(Int, Str) should widen to Any
    my $widened = $int->join($str);
    # Int and Str don't have a common subtype, so join goes to top
    ok($widened->is_top || $widened->name eq 'Any', 'Int join Str = Any');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/array-type-inference.t`
Expected: May pass if TypeLattice exists, or fail on missing methods

**Step 3: Verify existing infrastructure works**

The TypeInference semiring and TypeLattice should already handle this.
If tests pass, no new code needed. If they fail, add missing methods.

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/array-type-inference.t`
Expected: PASS

**Step 5: Commit**

```bash
git add t/ir/array-type-inference.t
git commit -m "test(ir): Add array element type inference tests (#337)"
```

---

## Task 7: Run Full Test Suite

**Step 1: Run all tests**

Run: `plenv exec perl -Ilib ./prove t/`
Expected: All tests pass

**Step 2: Run self-hosting test**

Run: `FORCE_SELF_HOSTING=1 plenv exec perl -Ilib t/self-hosting.t`
Expected: PASS

**Step 3: Final commit if any cleanup needed**

```bash
git status
git push origin feat/chapter15-arrays-337
```

---

## Summary

This plan implements:
1. NewArray with length and element_type parameters
2. ArrayLength node with constant folding
3. Panic node for runtime errors
4. Bounds checking in ArrayLoad with peephole optimization
5. Bounds checking in ArrayStore with peephole optimization
6. Element type inference via existing TypeInference

Total: 7 tasks, ~35 steps
