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

    my $can_complete = $type_sr->can('on_complete');
    ok($can_complete, 'TypeInference has on_complete method');

    if ($can_complete) {
        # Mock rule that doesn't have infer_type method
        my $rule = bless { lhs => 'Expression' }, 'MockRule';

        # Mock item with rule method
        my $item = bless {
            _rule => $rule,
            start_pos => 0,
            end_pos => 2
        }, 'MockItem';

        # Add rule method to MockItem
        {
            no strict 'refs';
            *MockItem::rule = sub { shift->{_rule} };
        }

        # Element representing "42" : Int
        my $int_type = $type_sr->type_from_name('Int');
        my $element = Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $int_type,
            type_env => {},
            children => [],
            token => undef
        );

        # Call on_complete - should preserve element since rule has no infer_type
        my $result = $type_sr->on_complete($item, $element);

        # Result should preserve the Int type (no transformation)
        is($result->type_obj->name(), 'Int',
           'on_complete preserves type when rule has no infer_type method');
    }
};

subtest 'Type multiplication uses meet and builds parse tree' => sub {
    my $type_sr = Chalk::Semiring::TypeInference->new();

    # Get Int and Num types
    my $int_type = $type_sr->type_from_name('Int');
    my $num_type = $type_sr->type_from_name('Num');

    my $int_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $int_type,
        type_env => {},
        children => [],
        token => undef
    );
    my $num_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $num_type,
        type_env => {},
        children => [],
        token => undef
    );

    # multiply() uses meet for type inference
    my $result = $int_elem->multiply($num_elem);
    is($result->type_obj->name(), 'Int',
       'multiply uses meet: Int ∧ Num = Int');

    # Verify parse tree is built correctly
    is(scalar($result->children->@*), 1, 'multiply appends child to build parse tree');
    is($result->children->[0], $num_elem, 'Child is the right operand');

    # on_complete() can refine types based on grammar-specific rules
    # multiply() provides baseline type inference via meet
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
