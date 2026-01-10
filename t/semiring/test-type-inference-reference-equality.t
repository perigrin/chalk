#!/usr/bin/env perl
# ABOUTME: Test that TypeInference.add() returns original references for consensus detection
# ABOUTME: Validates fix for issue #604 Component C - sequential filtering in Composite.add()

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
use Scalar::Util qw(refaddr);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Semiring::TypeInference;

# Create TypeInference semiring
my $type_sr = Chalk::Semiring::TypeInference->new();

subtest 'TypeInference.add() returns $self when joined type equals self type' => sub {
    # Create two elements with same type
    my $elem1 = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Num')
    );
    my $elem2 = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Num')
    );

    # add() should return $elem1 by reference (not a new element)
    my $result = $elem1->add($elem2);

    # Use refaddr to verify it's the same reference
    is refaddr($result), refaddr($elem1), 'add() returns $self when types are equal';
    ok $result == $elem1, 'Reference equality check (==) also works';
};

subtest 'TypeInference.add() returns $other when joined type equals other type' => sub {
    # Create elements where join produces other's type
    # Int ∨ Num = Num (join produces the more general type)
    my $elem_int = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Int')
    );
    my $elem_num = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Num')
    );

    # add() should return $elem_num by reference
    my $result = $elem_int->add($elem_num);

    is refaddr($result), refaddr($elem_num), 'add() returns $other when joined type equals other';
    ok $result == $elem_num, 'Reference equality check (==) confirms';
};

subtest 'TypeInference.add() returns other when joined type equals other (Int ∨ Str = Str)' => sub {
    # In the Chalk type lattice: Int <: Num <: Str
    # So Int ∨ Str = Str (join produces the supertype)

    my $elem_int = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Int')
    );
    my $elem_str = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Str')
    );

    my $result = $elem_int->add($elem_str);

    # Result should be $elem_str by reference since Int ∨ Str = Str
    is refaddr($result), refaddr($elem_str), 'add() returns $other when joined type equals other (Str)';
    is $result->type_obj->name(), 'Str', 'Joined type is Str';
};

subtest 'TypeInference.add() with identical elements returns self' => sub {
    my $elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Num')
    );

    my $result = $elem->add($elem);

    is refaddr($result), refaddr($elem), 'add() with same element returns self';
};
