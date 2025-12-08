#!/usr/bin/env perl
# ABOUTME: Test TypeInference semiring integration with Earley parser
# ABOUTME: Verifies type tracking through PREDICT/SCAN/COMPLETE and pruning of invalid types

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::TypeInference;
use Chalk::Grammar::Token;

# Simple test grammar for type checking
my $test_grammar_bnf = q{
    Expression ::= INTEGER
                 | Expression '+' Expression
                 | Expression '-' Expression
};

my $grammar = Chalk::Grammar->build_from_bnf($test_grammar_bnf, 'Expression', 'Test');

subtest 'on_scan extracts type from Token::Int' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # Create a mock Earley item (we only need the parts used by on_scan)
    my $item = bless {}, 'MockItem';

    # Start with top type element
    my $element = $type_sr->one();

    # Create an integer token
    my $int_token = Chalk::Grammar::Token::Int->new(
        value => '42',
        pattern_name => 'INTEGER'
    );

    # Call on_scan - it should extract Int type from the token
    my $result = $type_sr->on_scan($item, $element, 0, $int_token, 'INTEGER');

    # For now, this test will FAIL because on_scan() just returns element unchanged
    # We need to implement type extraction logic
    my $type_name = $result->type_obj->name();
    is($type_name, 'Int', 'on_scan extracts Int type from Token::Int');
};

subtest 'on_scan extracts type from Token::Float' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    my $item = bless {}, 'MockItem';
    my $element = $type_sr->one();

    # Create a float token
    my $float_token = Chalk::Grammar::Token::Float->new(
        value => '3.14',
        pattern_name => 'FLOAT'
    );

    my $result = $type_sr->on_scan($item, $element, 0, $float_token, 'FLOAT');

    # This will FAIL - on_scan doesn't extract types yet
    my $type_name = $result->type_obj->name();
    is($type_name, 'Num', 'on_scan extracts Num type from Token::Float');
};

subtest 'on_complete propagates types through derivation' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # This test will FAIL because on_complete() doesn't exist yet
    # We need to implement it following the SPPF pattern

    my $can_complete = $type_sr->can('on_complete');
    ok($can_complete, 'TypeInference has on_complete method');

    if ($can_complete) {
        # Mock completed item: INTEGER rule with Int type
        my $rule = bless { lhs => 'Expression' }, 'MockRule';
        my $item = bless {
            rule => $rule,
            start_pos => 0,
            end_pos => 2
        }, 'MockItem';

        # Element representing "42" : Int
        my $int_type = $type_sr->type_from_name('Int');
        my $element = Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $int_type
        );

        # Call on_complete
        my $result = $type_sr->on_complete($item, $element);

        # Result should preserve the Int type
        is($result->type_obj->name(), 'Int',
           'on_complete preserves type through rule completion');
    }
};

subtest 'Type multiplication combines constraints via meet' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # Get Int and Num types
    my $int_type = $type_sr->type_from_name('Int');
    my $num_type = $type_sr->type_from_name('Num');

    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $int_type
    );
    my $num_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $num_type
    );

    # Int ∧ Num should yield Int (more specific type)
    my $result = $int_elem->multiply($num_elem);
    is($result->type_obj->name(), 'Int',
       'multiply uses meet: Int ∧ Num = Int');

    # Get compatible but less specific type (Int <: Str)
    my $str_type = $type_sr->type_from_name('Str');
    my $str_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $str_type
    );

    # Int ∧ Str should yield Int (more specific type, since Int <: Str)
    my $refined = $int_elem->multiply($str_elem);
    is($refined->type_obj->name(), 'Int',
       'multiply refines type: Int ∧ Str = Int (Int <: Str)');

    # Get truly incompatible types for bottom test
    my $hash_type = $type_sr->type_from_name('Hash');
    my $hash_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $hash_type
    );

    # Int ∧ Hash should yield ⊥ (incompatible types)
    my $invalid = $int_elem->multiply($hash_elem);
    ok($invalid->type_obj->is_bottom(),
       'multiply detects contradiction: Int ∧ Hash = ⊥');
};

subtest 'Type addition combines alternatives via join' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # Get Int and Num types
    my $int_type = $type_sr->type_from_name('Int');
    my $num_type = $type_sr->type_from_name('Num');

    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $int_type
    );
    my $num_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $num_type
    );

    # Int ∨ Num should yield Num (less specific type, covers both)
    my $result = $int_elem->add($num_elem);
    is($result->type_obj->name(), 'Num',
       'add uses join: Int ∨ Num = Num');
};

subtest 'Bottom type marks invalid derivations' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # Bottom element
    my $bottom = $type_sr->zero();

    ok($bottom->type_obj->is_bottom(),
       'zero() returns bottom type (⊥)');
    ok(!$bottom->valid(),
       'bottom type is marked as invalid');
    is($bottom->score(), 0,
       'bottom type has score of 0');
};

subtest 'Top type represents no constraints (PREDICT start)' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # Top element
    my $top = $type_sr->one();

    ok(!$top->type_obj->is_bottom(),
       'one() returns top type (⊤)');
    ok($top->valid(),
       'top type is valid');
    is($top->type_obj->name(), 'Any',
       'top type is Any');
};
