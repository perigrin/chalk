#!/usr/bin/env perl
# ABOUTME: Test Composite semiring pattern implementation
# ABOUTME: Verifies combining multiple semirings with delegation and composition
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Base;
use Chalk::Semiring::Composite;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Position;
use Chalk::Semiring::Viterbi;
use Chalk::Semiring::SPPF;

subtest 'CompositeElement basic properties' => sub {
    my $bool = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 5);

    my $composite = Chalk::Semiring::CompositeElement->new(
        elements => [$bool, $pos]
    );

    ok $composite, 'CompositeElement created';
    is $composite->elements, [$bool, $pos], 'Elements accessor works';
    is scalar($composite->elements->@*), 2, 'Has two elements';
};

subtest 'CompositeElement multiplication delegates' => sub {
    my $bool1 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos1 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 2);

    my $bool2 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos2 = Chalk::Semiring::PositionElement->new(start_pos => 2, end_pos => 5);

    my $comp1 = Chalk::Semiring::CompositeElement->new(elements => [$bool1, $pos1]);
    my $comp2 = Chalk::Semiring::CompositeElement->new(elements => [$bool2, $pos2]);

    my $result = $comp1->multiply($comp2);

    ok $result, 'Multiplication succeeds';
    isa_ok $result, 'Chalk::Semiring::CompositeElement';
    is scalar($result->elements->@*), 2, 'Result has two elements';

    # Check Boolean multiplication (AND)
    ok $result->elements->[0]->value, 'Boolean AND preserves true';

    # Check Position multiplication (sequence)
    is $result->elements->[1]->start_pos, 0, 'Position starts at first';
    is $result->elements->[1]->end_pos, 5, 'Position ends at last';
};

subtest 'CompositeElement addition delegates' => sub {
    my $bool1 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos1 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 3);

    my $bool2 = Chalk::Semiring::BooleanElement->new(value => 0);
    my $pos2 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 5);

    my $comp1 = Chalk::Semiring::CompositeElement->new(elements => [$bool1, $pos1]);
    my $comp2 = Chalk::Semiring::CompositeElement->new(elements => [$bool2, $pos2]);

    my $result = $comp1->add($comp2);

    ok $result, 'Addition succeeds';
    isa_ok $result, 'Chalk::Semiring::CompositeElement';

    # Check Boolean addition (OR)
    ok $result->elements->[0]->value, 'Boolean OR gives true';

    # Check Position addition (prefers further)
    is $result->elements->[1]->end_pos, 5, 'Position prefers further parse';
};

subtest 'CompositeElement to_string combines' => sub {
    my $bool = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 5);

    my $composite = Chalk::Semiring::CompositeElement->new(elements => [$bool, $pos]);

    my $str = $composite->to_string;
    ok $str, 'to_string produces output';
    like $str, qr/1/, 'Contains Boolean representation';
    like $str, qr/\[0,5\]/, 'Contains Position representation';
};

subtest 'Composite semiring creation' => sub {
    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $pos_sr = Chalk::Semiring::Position->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$bool_sr, $pos_sr]
    );

    ok $composite, 'Composite semiring created';
    is $composite->semirings, [$bool_sr, $pos_sr], 'Semirings accessor works';
};

subtest 'Composite semiring identity elements' => sub {
    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $pos_sr = Chalk::Semiring::Position->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$bool_sr, $pos_sr]
    );

    ok $composite->mul_id, 'Has multiplicative identity';
    ok $composite->add_id, 'Has additive identity';

    isa_ok $composite->mul_id, 'Chalk::Semiring::CompositeElement';
    isa_ok $composite->add_id, 'Chalk::Semiring::CompositeElement';

    is scalar($composite->mul_id->elements->@*), 2, 'mul_id has both elements';
    is scalar($composite->add_id->elements->@*), 2, 'add_id has both elements';
};

subtest 'Composite semiring init_element_from_rule' => sub {
    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $pos_sr = Chalk::Semiring::Position->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$bool_sr, $pos_sr]
    );

    # Create a mock rule
    my $rule = bless {
        lhs => 'S',
        rhs => ['a', 'b'],
        probability => 1.0
    }, 'MockRule';

    my $elem = $composite->init_element_from_rule($rule, 0, 5);

    ok $elem, 'init_element_from_rule succeeds';
    isa_ok $elem, 'Chalk::Semiring::CompositeElement';
    is scalar($elem->elements->@*), 2, 'Element has both components';

    # Check Boolean component
    ok $elem->elements->[0]->value, 'Boolean element is true';

    # Check Position component
    is $elem->elements->[1]->start_pos, 0, 'Position element has correct start';
    is $elem->elements->[1]->end_pos, 5, 'Position element has correct end';
};

subtest 'Composite SPPF+Viterbi semiring' => sub {
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $viterbi_sr = Chalk::Semiring::Viterbi->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $viterbi_sr]
    );

    ok $composite, 'SPPF+Viterbi composite created';

    # Create a mock rule with probability
    my $rule = bless {
        lhs => 'E',
        rhs => ['n'],
        probability => 0.5
    }, 'MockRule';

    my $elem = $composite->init_element_from_rule($rule, 0, 1);

    ok $elem, 'Composite element from rule created';
    is scalar($elem->elements->@*), 2, 'Has both SPPF and Viterbi elements';

    # Check SPPF component
    isa_ok $elem->elements->[0], 'Chalk::Semiring::SPPFElement';
    ok $elem->elements->[0]->sppf_node, 'SPPF element has node';

    # Check Viterbi component
    isa_ok $elem->elements->[1], 'Chalk::Semiring::ViterbiElement';
    ok defined($elem->elements->[1]->score), 'Viterbi element has score';
};

subtest 'Composite accessor by index' => sub {
    my $bool = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 5);

    my $composite = Chalk::Semiring::CompositeElement->new(elements => [$bool, $pos]);

    is $composite->element_at(0), $bool, 'element_at(0) returns first';
    is $composite->element_at(1), $pos, 'element_at(1) returns second';
};

subtest 'Composite operator overloading' => sub {
    my $bool1 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos1 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 2);

    my $bool2 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos2 = Chalk::Semiring::PositionElement->new(start_pos => 2, end_pos => 5);

    my $comp1 = Chalk::Semiring::CompositeElement->new(elements => [$bool1, $pos1]);
    my $comp2 = Chalk::Semiring::CompositeElement->new(elements => [$bool2, $pos2]);

    my $mult = $comp1 * $comp2;
    ok $mult, 'Operator * works';

    my $add = $comp1 + $comp2;
    ok $add, 'Operator + works';
};

subtest 'Short-circuit on add_id in multiply' => sub {
    use Chalk::Semiring::Precedence;

    # Create a precedence table
    my @precedence_table = (
        { assoc => 'left', ops => ['+'] },    # Index 0 - High precedence
        { assoc => 'left', ops => ['||'] },   # Index 1 - Low precedence
    );

    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(precedence_table => \@precedence_table);

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$bool_sr, $prec_sr]
    );

    # Create elements: one with valid precedence, one with invalid
    my $bool_true = Chalk::Semiring::BooleanElement->new(value => 1);
    my $prec_invalid = Chalk::Semiring::PrecedenceElement->new(
        valid => 0,  # Invalid precedence - this is add_id
        operator => '||',
        precedence_level => 1
    );

    my $elem1 = Chalk::Semiring::CompositeElement->new(
        elements => [$bool_true, $prec_invalid],
        parent_semiring => $composite
    );

    my $bool_true2 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $prec_valid = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 0
    );

    my $elem2 = Chalk::Semiring::CompositeElement->new(
        elements => [$bool_true2, $prec_valid],
        parent_semiring => $composite
    );

    # When we multiply, the Precedence semiring returns add_id (invalid)
    # The Composite should short-circuit and return its add_id
    my $result = $elem1->multiply($elem2);

    # Check if result equals composite add_id
    # This will FAIL initially because current implementation doesn't short-circuit
    my $expected_invalid = $composite->add_id;
    ok $result->equals($expected_invalid), 'Short-circuits to add_id when any child is invalid';
};

subtest 'No short-circuit when all children valid in multiply' => sub {
    use Chalk::Semiring::Precedence;

    my @precedence_table = (
        { assoc => 'left', ops => ['+'] },
    );

    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(precedence_table => \@precedence_table);

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$bool_sr, $prec_sr]
    );

    # Both elements valid
    my $bool_true1 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $prec_valid1 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $elem1 = Chalk::Semiring::CompositeElement->new(
        elements => [$bool_true1, $prec_valid1],
        parent_semiring => $composite
    );

    my $bool_true2 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $prec_valid2 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $elem2 = Chalk::Semiring::CompositeElement->new(
        elements => [$bool_true2, $prec_valid2],
        parent_semiring => $composite
    );

    # Should not short-circuit - all valid
    my $result = $elem1->multiply($elem2);

    # Result should NOT equal add_id
    my $add_id = $composite->add_id;
    ok !$result->equals($add_id), 'Does not short-circuit when all children valid';

    # Result should have valid elements
    ok $result->elements->[0]->value, 'Boolean element still valid';
    ok $result->elements->[1]->valid, 'Precedence element still valid';
};

# Mock rule class for testing
package MockRule {
    sub lhs { shift->{lhs} }
    sub rhs { shift->{rhs} }
    sub probability { shift->{probability} }
}
