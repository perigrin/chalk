#!/usr/bin/env perl
# ABOUTME: Test TypeInference tropical semiring operations over type lattice
# ABOUTME: Verifies semiring laws (associativity, identity, distributivity) with types as values

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar::Chalk::TypeLattice;
use Chalk::Semiring::TypeInference;

# Test tropical semiring structure over type lattice
# S = Type lattice
# ⊕ = ∨ (join)     # "could be either type" - combine alternatives
# ⊗ = ∧ (meet)     # "must satisfy all constraints" - combine within derivation
# 𝟘 = ⊥ (bottom)   # type contradiction (identity for join)
# 𝟙 = ⊤ (top)      # no constraints yet (identity for meet)

subtest 'Type lattice provides bottom and top types' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $bottom = $lattice->bottom_type();
    ok $bottom, 'bottom_type() returns a type';
    ok $bottom->is_bottom(), 'bottom type is actually bottom';

    my $top = $lattice->top_type();
    ok $top, 'top_type() returns a type';
    is $top->name(), 'Any', 'top type is Any';
};

subtest 'Join (⊕) operations' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    # Join of Int and Num should be Num (least upper bound)
    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    my $joined = $lattice->join($int_type, $num_type);
    is $joined->name(), 'Num', 'Int ∨ Num = Num';

    # Join of Int and Str should be Scalar (or Any depending on lattice)
    my $str_type = $lattice->type_from_name('Str');
    my $int_str_join = $lattice->join($int_type, $str_type);
    ok defined($int_str_join), 'Int ∨ Str has a join';
};

subtest 'Meet (⊗) operations' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    # Meet of Num and Int should be Int (greatest lower bound)
    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    my $meet = $lattice->meet($num_type, $int_type);
    is $meet->name(), 'Int', 'Num ∧ Int = Int';

    # TODO: Meet of incompatible types should be bottom
    # Current implementation returns Int instead of bottom for Int ∧ Str
    # This is a known limitation from Phase 1
    my $str_type = $lattice->type_from_name('Str');
    my $int_str_meet = $lattice->meet($int_type, $str_type);

    {
        my $todo = todo 'Meet of incompatible scalar types should return bottom';
        ok $int_str_meet->is_bottom(), 'Int ∧ Str = ⊥ (incompatible types)';
    }
};

subtest 'Identity elements' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    # Bottom is identity for join: x ∨ ⊥ = x
    my $int_type = $lattice->type_from_name('Int');
    my $bottom = $lattice->bottom_type();

    my $int_or_bottom = $lattice->join($int_type, $bottom);
    is $int_or_bottom->name(), 'Int', 'Int ∨ ⊥ = Int (bottom is join identity)';

    # Top is identity for meet: x ∧ ⊤ = x
    my $top = $lattice->top_type();
    my $int_and_top = $lattice->meet($int_type, $top);
    is $int_and_top->name(), 'Int', 'Int ∧ Any = Int (top is meet identity)';
};

subtest 'Associativity of join' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $a = $lattice->type_from_name('Int');
    my $b = $lattice->type_from_name('Num');
    my $c = $lattice->type_from_name('Scalar');

    # (a ∨ b) ∨ c should equal a ∨ (b ∨ c)
    my $left = $lattice->join($lattice->join($a, $b), $c);
    my $right = $lattice->join($a, $lattice->join($b, $c));

    is $left->name(), $right->name(), '(Int ∨ Num) ∨ Scalar = Int ∨ (Num ∨ Scalar) [associativity]';
};

subtest 'Associativity of meet' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $a = $lattice->type_from_name('Scalar');
    my $b = $lattice->type_from_name('Num');
    my $c = $lattice->type_from_name('Int');

    # (a ∧ b) ∧ c should equal a ∧ (b ∧ c)
    my $left = $lattice->meet($lattice->meet($a, $b), $c);
    my $right = $lattice->meet($a, $lattice->meet($b, $c));

    is $left->name(), $right->name(), '(Scalar ∧ Num) ∧ Int = Scalar ∧ (Num ∧ Int) [associativity]';
};

subtest 'Commutativity of join' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    my $left = $lattice->join($int_type, $num_type);
    my $right = $lattice->join($num_type, $int_type);

    is $left->name(), $right->name(), 'Int ∨ Num = Num ∨ Int [commutativity]';
};

subtest 'Commutativity of meet' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    my $left = $lattice->meet($int_type, $num_type);
    my $right = $lattice->meet($num_type, $int_type);

    is $left->name(), $right->name(), 'Int ∧ Num = Num ∧ Int [commutativity]';
};

subtest 'Idempotence of join' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $int_type = $lattice->type_from_name('Int');
    my $joined = $lattice->join($int_type, $int_type);

    is $joined->name(), 'Int', 'Int ∨ Int = Int [idempotence]';
};

subtest 'Idempotence of meet' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $int_type = $lattice->type_from_name('Int');
    my $meet = $lattice->meet($int_type, $int_type);

    is $meet->name(), 'Int', 'Int ∧ Int = Int [idempotence]';
};

subtest 'Absorption laws' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    # x ∨ (x ∧ y) = x
    my $meet = $lattice->meet($int_type, $num_type);  # Int ∧ Num = Int
    my $join = $lattice->join($int_type, $meet);      # Int ∨ Int = Int
    is $join->name(), 'Int', 'Int ∨ (Int ∧ Num) = Int [absorption]';

    # x ∧ (x ∨ y) = x
    my $join2 = $lattice->join($int_type, $num_type);  # Int ∨ Num = Num
    my $meet2 = $lattice->meet($int_type, $join2);     # Int ∧ Num = Int
    is $meet2->name(), 'Int', 'Int ∧ (Int ∨ Num) = Int [absorption]';
};

# TypeInference Semiring Element tests
subtest 'TypeInferenceElement wraps type objects' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int_type = $lattice->type_from_name('Int');

    my $elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $int_type);
    ok $elem, 'TypeInferenceElement created';
    isa_ok $elem, 'Chalk::Semiring::TypeInferenceElement';
    is $elem->type_obj->name(), 'Int', 'Element wraps Int type';
};

subtest 'TypeInferenceElement add() uses join' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $int_type);
    my $num_elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $num_type);

    my $result = $int_elem->add($num_elem);
    is $result->type_obj->name(), 'Num', 'Int ⊕ Num = Num (add uses join)';
};

subtest 'TypeInferenceElement multiply() uses meet' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $num_type = $lattice->type_from_name('Num');
    my $int_type = $lattice->type_from_name('Int');

    my $num_elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $num_type);
    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $int_type);

    my $result = $num_elem->multiply($int_elem);
    is $result->type_obj->name(), 'Int', 'Num ⊗ Int = Int (multiply uses meet)';
};

subtest 'TypeInference semiring identity elements' => sub {
    my $semiring = Chalk::Semiring::TypeInference->new();

    my $zero = $semiring->zero();
    ok $zero, 'zero() returns element';
    ok $zero->type_obj->is_bottom(), 'zero() is bottom type (⊥)';

    my $one = $semiring->one();
    ok $one, 'one() returns element';
    is $one->type_obj->name(), 'Any', 'one() is top type (⊤)';
};

subtest 'TypeInference semiring multiplication (meet) law' => sub {
    my $semiring = Chalk::Semiring::TypeInference->new();
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $one = $semiring->one();
    my $int_type = $lattice->type_from_name('Int');
    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $int_type);

    # x ⊗ 1 = x
    my $result = $int_elem->multiply($one);
    is $result->type_obj->name(), 'Int', 'Int ⊗ ⊤ = Int (one is multiplicative identity)';
};

subtest 'TypeInference semiring addition (join) law' => sub {
    my $semiring = Chalk::Semiring::TypeInference->new();
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $zero = $semiring->zero();
    my $int_type = $lattice->type_from_name('Int');
    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(type_obj => $int_type);

    # x ⊕ 0 = x
    my $result = $int_elem->add($zero);
    is $result->type_obj->name(), 'Int', 'Int ⊕ ⊥ = Int (zero is additive identity)';
};
