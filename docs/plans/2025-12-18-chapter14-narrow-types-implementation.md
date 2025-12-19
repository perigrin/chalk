# Chapter 14: Narrow Primitive Types - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add sub-word integer types (i8, i16, i32, u8, u16, u32) and f32 with truncation, extension, and bitwise operations.

**Architecture:** Extend existing IR::Type::Integer with `bits` and `signed` parameters. Add Truncate/Extend nodes for type conversion. Add BitAnd/BitOr/BitXor/BitNot for bitwise ops.

**Tech Stack:** Perl 5.42.0, Object::Pad classes, existing IR node infrastructure.

---

## Task 1: Extend Integer Type with bits/signed

**Files:**
- Modify: `lib/Chalk/IR/Type/Integer.pm`
- Test: `t/ir/narrow-types.t` (create)

**Step 1: Write the failing test**

Create `t/ir/narrow-types.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for narrow integer types (i8, i16, i32, u8, u16, u32)
# ABOUTME: Verifies bits/signed parameters and range calculations
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Type::Integer;

subtest 'Integer type constructors' => sub {
    my $i8 = Chalk::IR::Type::Integer->i8();
    is($i8->bits, 8, 'i8 has 8 bits');
    is($i8->signed, 1, 'i8 is signed');

    my $u32 = Chalk::IR::Type::Integer->u32();
    is($u32->bits, 32, 'u32 has 32 bits');
    is($u32->signed, 0, 'u32 is unsigned');
};

subtest 'Integer range calculations' => sub {
    my $i8 = Chalk::IR::Type::Integer->i8();
    is($i8->min, -128, 'i8 min is -128');
    is($i8->max, 127, 'i8 max is 127');

    my $u8 = Chalk::IR::Type::Integer->u8();
    is($u8->min, 0, 'u8 min is 0');
    is($u8->max, 255, 'u8 max is 255');
};

subtest 'Integer mask calculation' => sub {
    my $i8 = Chalk::IR::Type::Integer->i8();
    is($i8->mask, 0xFF, 'i8 mask is 0xFF');

    my $u16 = Chalk::IR::Type::Integer->u16();
    is($u16->mask, 0xFFFF, 'u16 mask is 0xFFFF');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/narrow-types.t`
Expected: FAIL - methods i8(), u32(), bits(), signed(), min(), max(), mask() don't exist

**Step 3: Write minimal implementation**

Modify `lib/Chalk/IR/Type/Integer.pm` - add new fields and methods after existing fields:

```perl
field $bits   :param :reader = 64;
field $signed :param :reader = 1;

method min() {
    return 0 unless $signed;
    return -(1 << ($bits - 1));
}

method max() {
    return (1 << $bits) - 1 unless $signed;
    return (1 << ($bits - 1)) - 1;
}

method mask() {
    return (1 << $bits) - 1;
}

method sign_bit() {
    return 1 << ($bits - 1);
}

# Convenience constructors
sub i8  ($class) { $class->new(bits => 8,  signed => 1) }
sub i16 ($class) { $class->new(bits => 16, signed => 1) }
sub i32 ($class) { $class->new(bits => 32, signed => 1) }
sub i64 ($class) { $class->new(bits => 64, signed => 1) }
sub u8  ($class) { $class->new(bits => 8,  signed => 0) }
sub u16 ($class) { $class->new(bits => 16, signed => 0) }
sub u32 ($class) { $class->new(bits => 32, signed => 0) }
sub u64 ($class) { $class->new(bits => 64, signed => 0) }
sub bool ($class) { $class->new(bits => 1, signed => 0) }
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/narrow-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/Integer.pm t/ir/narrow-types.t
git commit -m "feat(types): Add bits/signed parameters to Integer type (#336)"
```

---

## Task 2: Extend Float Type with bits

**Files:**
- Modify: `lib/Chalk/IR/Type/Float.pm`
- Modify: `t/ir/narrow-types.t`

**Step 1: Write the failing test**

Add to `t/ir/narrow-types.t`:

```perl
use Chalk::IR::Type::Float;

subtest 'Float type constructors' => sub {
    my $f32 = Chalk::IR::Type::Float->f32();
    is($f32->bits, 32, 'f32 has 32 bits');

    my $f64 = Chalk::IR::Type::Float->f64();
    is($f64->bits, 64, 'f64 has 64 bits');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/narrow-types.t`
Expected: FAIL - f32(), f64(), bits() don't exist on Float

**Step 3: Write minimal implementation**

Modify `lib/Chalk/IR/Type/Float.pm` - add bits field and constructors:

```perl
field $bits :param :reader = 64;

sub f32 ($class) { $class->new(bits => 32) }
sub f64 ($class) { $class->new(bits => 64) }
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/narrow-types.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Type/Float.pm t/ir/narrow-types.t
git commit -m "feat(types): Add bits parameter to Float type for f32 support (#336)"
```

---

## Task 3: Implement Truncate Node

**Files:**
- Create: `lib/Chalk/IR/Node/Truncate.pm`
- Create: `t/ir/truncate.t`

**Step 1: Write the failing test**

Create `t/ir/truncate.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for Truncate IR node
# ABOUTME: Verifies narrowing from wider to narrower integer types
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::Truncate;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'Truncate constant folding' => sub {
    # 300 truncated to i8 = 44 (300 & 0xFF = 44)
    my $const = Chalk::IR::Node::Constant->new(
        value => 300,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $trunc = Chalk::IR::Node::Truncate->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i8()
    );

    my $result = $trunc->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'Truncate folds to constant');
    is($result->value, 44, 'Truncated value is 44');
};

subtest 'Truncate signed wraparound' => sub {
    # 200 truncated to i8 = -56 (200 & 0xFF = 200, sign extend = -56)
    my $const = Chalk::IR::Node::Constant->new(
        value => 200,
        type => Chalk::IR::Type::Integer->i64()
    );

    my $trunc = Chalk::IR::Node::Truncate->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i8()
    );

    my $result = $trunc->peephole();
    is($result->value, -56, 'Signed truncation wraps correctly');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/truncate.t`
Expected: FAIL - Truncate module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/Truncate.pm`:

```perl
# ABOUTME: Truncate node narrows integers from wider to narrower types
# ABOUTME: Implements bit masking with optional sign extension
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Truncate :isa(Chalk::IR::Node::Base) {
    field $operand :param :reader;
    field $target_type :param :reader;

    method op() { 'Truncate' }

    method inputs() {
        return [ $operand->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'Truncate',
            inputs => $self->inputs,
            attributes => {
                target_bits => $target_type->bits,
                target_signed => $target_type->signed,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($operand->isa('Chalk::IR::Node::Constant') && $operand->is_constant) {
            my $val = $operand->value;
            my $mask = $target_type->mask;
            my $truncated = $val & $mask;

            # Sign extend if signed and high bit set
            if ($target_type->signed && ($truncated & $target_type->sign_bit)) {
                $truncated = $truncated | (~$mask);
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $truncated,
                type => $target_type
            );
        }

        return $self;
    }

    method compute_type() {
        return $target_type;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/truncate.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/Truncate.pm t/ir/truncate.t
git commit -m "feat(ir): Add Truncate node for narrowing integer types (#336)"
```

---

## Task 4: Implement SignExtend Node

**Files:**
- Create: `lib/Chalk/IR/Node/SignExtend.pm`
- Create: `t/ir/extend.t`

**Step 1: Write the failing test**

Create `t/ir/extend.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for SignExtend and ZeroExtend IR nodes
# ABOUTME: Verifies widening from narrower to wider integer types
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::SignExtend;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'SignExtend positive value' => sub {
    # 100 (i8) sign-extended to i64 = 100
    my $const = Chalk::IR::Node::Constant->new(
        value => 100,
        type => Chalk::IR::Type::Integer->i8()
    );

    my $ext = Chalk::IR::Node::SignExtend->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i64()
    );

    my $result = $ext->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'SignExtend folds to constant');
    is($result->value, 100, 'Positive value unchanged');
};

subtest 'SignExtend negative value' => sub {
    # -56 (i8) sign-extended to i64 = -56
    my $const = Chalk::IR::Node::Constant->new(
        value => -56,
        type => Chalk::IR::Type::Integer->i8()
    );

    my $ext = Chalk::IR::Node::SignExtend->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i64()
    );

    my $result = $ext->peephole();
    is($result->value, -56, 'Negative value sign-extended correctly');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/extend.t`
Expected: FAIL - SignExtend module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/SignExtend.pm`:

```perl
# ABOUTME: SignExtend node widens signed integers preserving sign bit
# ABOUTME: Used when loading from narrower signed types
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::SignExtend :isa(Chalk::IR::Node::Base) {
    field $operand :param :reader;
    field $target_type :param :reader;

    method op() { 'SignExtend' }

    method inputs() {
        return [ $operand->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'SignExtend',
            inputs => $self->inputs,
            attributes => {
                target_bits => $target_type->bits,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding - sign extension preserves value for constants
        if ($operand->isa('Chalk::IR::Node::Constant') && $operand->is_constant) {
            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $operand->value,  # Perl handles sign correctly
                type => $target_type
            );
        }

        return $self;
    }

    method compute_type() {
        return $target_type;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/extend.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/SignExtend.pm t/ir/extend.t
git commit -m "feat(ir): Add SignExtend node for widening signed integers (#336)"
```

---

## Task 5: Implement ZeroExtend Node

**Files:**
- Create: `lib/Chalk/IR/Node/ZeroExtend.pm`
- Modify: `t/ir/extend.t`

**Step 1: Write the failing test**

Add to `t/ir/extend.t`:

```perl
use Chalk::IR::Node::ZeroExtend;

subtest 'ZeroExtend value' => sub {
    # 200 (u8) zero-extended to i64 = 200
    my $const = Chalk::IR::Node::Constant->new(
        value => 200,
        type => Chalk::IR::Type::Integer->u8()
    );

    my $ext = Chalk::IR::Node::ZeroExtend->new(
        operand => $const,
        target_type => Chalk::IR::Type::Integer->i64()
    );

    my $result = $ext->peephole();
    ok($result->isa('Chalk::IR::Node::Constant'), 'ZeroExtend folds to constant');
    is($result->value, 200, 'Value zero-extended correctly');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/extend.t`
Expected: FAIL - ZeroExtend module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/ZeroExtend.pm`:

```perl
# ABOUTME: ZeroExtend node widens unsigned integers padding with zeros
# ABOUTME: Used when loading from narrower unsigned types
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ZeroExtend :isa(Chalk::IR::Node::Base) {
    field $operand :param :reader;
    field $target_type :param :reader;

    method op() { 'ZeroExtend' }

    method inputs() {
        return [ $operand->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'ZeroExtend',
            inputs => $self->inputs,
            attributes => {
                target_bits => $target_type->bits,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($operand->isa('Chalk::IR::Node::Constant') && $operand->is_constant) {
            my $val = $operand->value;
            # Mask to source type's range to ensure positive
            my $source_type = $operand->type;
            if ($source_type && $source_type->can('mask')) {
                $val = $val & $source_type->mask;
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $val,
                type => $target_type
            );
        }

        return $self;
    }

    method compute_type() {
        return $target_type;
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/extend.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/ZeroExtend.pm t/ir/extend.t
git commit -m "feat(ir): Add ZeroExtend node for widening unsigned integers (#336)"
```

---

## Task 6: Implement BitAnd Node

**Files:**
- Create: `lib/Chalk/IR/Node/BitAnd.pm`
- Create: `t/ir/bitwise-ops.t`

**Step 1: Write the failing test**

Create `t/ir/bitwise-ops.t`:

```perl
#!/usr/bin/env perl
# ABOUTME: Tests for bitwise operation IR nodes
# ABOUTME: Verifies BitAnd, BitOr, BitXor, BitNot with peephole optimizations
use 5.42.0;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

subtest 'BitAnd constant folding' => sub {
    my $a = Chalk::IR::Node::Constant->new(value => 0b11110000, type => Chalk::IR::Type::Integer->i64());
    my $b = Chalk::IR::Node::Constant->new(value => 0b10101010, type => Chalk::IR::Type::Integer->i64());

    my $and = Chalk::IR::Node::BitAnd->new(left => $a, right => $b);
    my $result = $and->peephole();

    ok($result->isa('Chalk::IR::Node::Constant'), 'BitAnd folds to constant');
    is($result->value, 0b10100000, 'BitAnd computed correctly');
};

subtest 'BitAnd identity x & -1 = x' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $neg1 = Chalk::IR::Node::Constant->new(value => -1, type => Chalk::IR::Type::Integer->i64());

    my $and = Chalk::IR::Node::BitAnd->new(left => $x, right => $neg1);
    my $result = $and->peephole();

    is($result->value, 42, 'x & -1 = x');
};

subtest 'BitAnd annihilator x & 0 = 0' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $zero = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->i64());

    my $and = Chalk::IR::Node::BitAnd->new(left => $x, right => $zero);
    my $result = $and->peephole();

    is($result->value, 0, 'x & 0 = 0');
};

done_testing();
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: FAIL - BitAnd module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/BitAnd.pm`:

```perl
# ABOUTME: BitAnd node performs bitwise AND operation
# ABOUTME: NOT short-circuit like logical And - evaluates both operands
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitAnd :isa(Chalk::IR::Node::Base) {
    field $left :param :reader;
    field $right :param :reader;

    method op() { 'BitAnd' }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitAnd',
            inputs => $self->inputs,
            attributes => {
                left_id => $left->id,
                right_id => $right->id,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($left->isa('Chalk::IR::Node::Constant') && $left->is_constant &&
            $right->isa('Chalk::IR::Node::Constant') && $right->is_constant) {

            my $lval = $left->value;
            my $rval = $right->value;

            # Identity: x & -1 = x
            return $left if $rval == -1;
            return $right if $lval == -1;

            # Annihilator: x & 0 = 0
            if ($lval == 0 || $rval == 0) {
                use Chalk::IR::Node::Constant;
                return Chalk::IR::Node::Constant->new(
                    value => 0,
                    type => $left->type // Chalk::IR::Type::Integer->i64()
                );
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $lval & $rval,
                type => $left->type // Chalk::IR::Type::Integer->i64()
            );
        }

        return $self;
    }

    method compute_type() {
        return $left->compute_type if $left->can('compute_type');
        return Chalk::IR::Type::Integer->TOP();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/BitAnd.pm t/ir/bitwise-ops.t
git commit -m "feat(ir): Add BitAnd node with peephole optimizations (#336)"
```

---

## Task 7: Implement BitOr Node

**Files:**
- Create: `lib/Chalk/IR/Node/BitOr.pm`
- Modify: `t/ir/bitwise-ops.t`

**Step 1: Write the failing test**

Add to `t/ir/bitwise-ops.t`:

```perl
use Chalk::IR::Node::BitOr;

subtest 'BitOr constant folding' => sub {
    my $a = Chalk::IR::Node::Constant->new(value => 0b11110000, type => Chalk::IR::Type::Integer->i64());
    my $b = Chalk::IR::Node::Constant->new(value => 0b00001111, type => Chalk::IR::Type::Integer->i64());

    my $or = Chalk::IR::Node::BitOr->new(left => $a, right => $b);
    my $result = $or->peephole();

    ok($result->isa('Chalk::IR::Node::Constant'), 'BitOr folds to constant');
    is($result->value, 0b11111111, 'BitOr computed correctly');
};

subtest 'BitOr identity x | 0 = x' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $zero = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->i64());

    my $or = Chalk::IR::Node::BitOr->new(left => $x, right => $zero);
    my $result = $or->peephole();

    is($result->value, 42, 'x | 0 = x');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: FAIL - BitOr module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/BitOr.pm`:

```perl
# ABOUTME: BitOr node performs bitwise OR operation
# ABOUTME: NOT short-circuit like logical Or - evaluates both operands
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitOr :isa(Chalk::IR::Node::Base) {
    field $left :param :reader;
    field $right :param :reader;

    method op() { 'BitOr' }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitOr',
            inputs => $self->inputs,
            attributes => {
                left_id => $left->id,
                right_id => $right->id,
            },
        };
    }

    method peephole($graph = undef) {
        if ($left->isa('Chalk::IR::Node::Constant') && $left->is_constant &&
            $right->isa('Chalk::IR::Node::Constant') && $right->is_constant) {

            my $lval = $left->value;
            my $rval = $right->value;

            # Identity: x | 0 = x
            return $left if $rval == 0;
            return $right if $lval == 0;

            # Annihilator: x | -1 = -1
            if ($lval == -1 || $rval == -1) {
                use Chalk::IR::Node::Constant;
                return Chalk::IR::Node::Constant->new(
                    value => -1,
                    type => $left->type // Chalk::IR::Type::Integer->i64()
                );
            }

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $lval | $rval,
                type => $left->type // Chalk::IR::Type::Integer->i64()
            );
        }

        return $self;
    }

    method compute_type() {
        return $left->compute_type if $left->can('compute_type');
        return Chalk::IR::Type::Integer->TOP();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/BitOr.pm t/ir/bitwise-ops.t
git commit -m "feat(ir): Add BitOr node with peephole optimizations (#336)"
```

---

## Task 8: Implement BitXor Node

**Files:**
- Create: `lib/Chalk/IR/Node/BitXor.pm`
- Modify: `t/ir/bitwise-ops.t`

**Step 1: Write the failing test**

Add to `t/ir/bitwise-ops.t`:

```perl
use Chalk::IR::Node::BitXor;

subtest 'BitXor constant folding' => sub {
    my $a = Chalk::IR::Node::Constant->new(value => 0b11110000, type => Chalk::IR::Type::Integer->i64());
    my $b = Chalk::IR::Node::Constant->new(value => 0b10101010, type => Chalk::IR::Type::Integer->i64());

    my $xor = Chalk::IR::Node::BitXor->new(left => $a, right => $b);
    my $result = $xor->peephole();

    ok($result->isa('Chalk::IR::Node::Constant'), 'BitXor folds to constant');
    is($result->value, 0b01011010, 'BitXor computed correctly');
};

subtest 'BitXor identity x ^ 0 = x' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->i64());
    my $zero = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->i64());

    my $xor = Chalk::IR::Node::BitXor->new(left => $x, right => $zero);
    my $result = $xor->peephole();

    is($result->value, 42, 'x ^ 0 = x');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: FAIL - BitXor module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/BitXor.pm`:

```perl
# ABOUTME: BitXor node performs bitwise XOR operation
# ABOUTME: Includes identity (x ^ 0 = x) and self-inverse (x ^ x = 0) optimizations
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitXor :isa(Chalk::IR::Node::Base) {
    field $left :param :reader;
    field $right :param :reader;

    method op() { 'BitXor' }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitXor',
            inputs => $self->inputs,
            attributes => {
                left_id => $left->id,
                right_id => $right->id,
            },
        };
    }

    method peephole($graph = undef) {
        if ($left->isa('Chalk::IR::Node::Constant') && $left->is_constant &&
            $right->isa('Chalk::IR::Node::Constant') && $right->is_constant) {

            my $lval = $left->value;
            my $rval = $right->value;

            # Identity: x ^ 0 = x
            return $left if $rval == 0;
            return $right if $lval == 0;

            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => $lval ^ $rval,
                type => $left->type // Chalk::IR::Type::Integer->i64()
            );
        }

        # Self-inverse: x ^ x = 0 (same node reference)
        if (refaddr($left) == refaddr($right)) {
            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => 0,
                type => $left->compute_type // Chalk::IR::Type::Integer->i64()
            );
        }

        return $self;
    }

    method compute_type() {
        return $left->compute_type if $left->can('compute_type');
        return Chalk::IR::Type::Integer->TOP();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/BitXor.pm t/ir/bitwise-ops.t
git commit -m "feat(ir): Add BitXor node with peephole optimizations (#336)"
```

---

## Task 9: Implement BitNot Node

**Files:**
- Create: `lib/Chalk/IR/Node/BitNot.pm`
- Modify: `t/ir/bitwise-ops.t`

**Step 1: Write the failing test**

Add to `t/ir/bitwise-ops.t`:

```perl
use Chalk::IR::Node::BitNot;

subtest 'BitNot constant folding' => sub {
    my $x = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->i64());

    my $not = Chalk::IR::Node::BitNot->new(operand => $x);
    my $result = $not->peephole();

    ok($result->isa('Chalk::IR::Node::Constant'), 'BitNot folds to constant');
    is($result->value, -1, '~0 = -1');
};
```

**Step 2: Run test to verify it fails**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: FAIL - BitNot module doesn't exist

**Step 3: Write minimal implementation**

Create `lib/Chalk/IR/Node/BitNot.pm`:

```perl
# ABOUTME: BitNot node performs bitwise NOT (complement) operation
# ABOUTME: Unary operator that inverts all bits
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::BitNot :isa(Chalk::IR::Node::Base) {
    field $operand :param :reader;

    method op() { 'BitNot' }

    method inputs() {
        return [ $operand->id ];
    }

    method to_hash() {
        return {
            id => $self->id,
            op => 'BitNot',
            inputs => $self->inputs,
            attributes => {},
        };
    }

    method peephole($graph = undef) {
        # Constant folding
        if ($operand->isa('Chalk::IR::Node::Constant') && $operand->is_constant) {
            use Chalk::IR::Node::Constant;
            return Chalk::IR::Node::Constant->new(
                value => ~$operand->value,
                type => $operand->type // Chalk::IR::Type::Integer->i64()
            );
        }

        # Double negation: ~~x = x
        if ($operand->isa('Chalk::IR::Node::BitNot')) {
            return $operand->operand;
        }

        return $self;
    }

    method compute_type() {
        return $operand->compute_type if $operand->can('compute_type');
        return Chalk::IR::Type::Integer->TOP();
    }
}

1;
```

**Step 4: Run test to verify it passes**

Run: `plenv exec perl -Ilib t/ir/bitwise-ops.t`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/Chalk/IR/Node/BitNot.pm t/ir/bitwise-ops.t
git commit -m "feat(ir): Add BitNot node with peephole optimizations (#336)"
```

---

## Task 10: Run Full Test Suite

**Step 1: Run all tests**

Run: `plenv exec perl -Ilib ./prove t/`
Expected: All tests pass

**Step 2: Run self-hosting test**

Run: `FORCE_SELF_HOSTING=1 plenv exec perl -Ilib t/self-hosting.t`
Expected: PASS (new files should parse)

**Step 3: Final commit if any cleanup needed**

```bash
git status
# If clean, push the branch
git push origin feat/chapter14-narrow-types-336
```

---

## Summary

This plan implements:
1. Parameterized Integer type (bits, signed, min, max, mask)
2. Float32 support (bits parameter)
3. Truncate node for narrowing
4. SignExtend/ZeroExtend nodes for widening
5. BitAnd, BitOr, BitXor, BitNot nodes with peephole optimizations

Total: 10 tasks, ~50 steps
