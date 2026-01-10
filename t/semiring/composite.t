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
    # Create elements that will reach consensus (both semirings choose comp1)
    my $bool1 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos1 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 5);

    my $bool2 = Chalk::Semiring::BooleanElement->new(value => 0);
    my $pos2 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 3);

    my $comp1 = Chalk::Semiring::CompositeElement->new(elements => [$bool1, $pos1]);
    my $comp2 = Chalk::Semiring::CompositeElement->new(elements => [$bool2, $pos2]);

    # Boolean: true OR false = true → returns comp1's Boolean (self)
    # Position: end=5 vs end=3 → returns comp1's Position (self)
    # Consensus: both chose self → returns comp1
    my $result = $comp1->add($comp2);

    ok $result == $comp1, 'Addition returns comp1 by reference (consensus)';
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

    # For add, use elements where both semirings will choose the same composite
    my $bool3 = Chalk::Semiring::BooleanElement->new(value => 1);
    my $pos3 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 5);
    my $bool4 = Chalk::Semiring::BooleanElement->new(value => 0);
    my $pos4 = Chalk::Semiring::PositionElement->new(start_pos => 0, end_pos => 3);
    my $comp3 = Chalk::Semiring::CompositeElement->new(elements => [$bool3, $pos3]);
    my $comp4 = Chalk::Semiring::CompositeElement->new(elements => [$bool4, $pos4]);

    # Boolean: true OR false = true → comp3, Position: 5 vs 3 → comp3
    my $add = $comp3 + $comp4;
    ok $add == $comp3, 'Operator + works (returns comp3 by consensus)';
};

subtest 'Invalid precedence propagates through multiply' => sub {
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
        valid => 0,  # Invalid precedence
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

    # When we multiply, the Precedence semiring returns an invalid element
    # (with preserved operator info for add() coordination)
    my $result = $elem1->multiply($elem2);

    # The result should have an invalid Precedence element (valid => 0)
    # Note: Invalid elements preserve operator info to allow add() coordination,
    # so result won't equal add_id (which has no operator info)
    ok !$result->elements->[1]->valid, 'Multiply propagates invalid precedence';
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

subtest 'Sequential filtering: short-circuit when semiring returns add_id' => sub {
    use Chalk::Semiring::Precedence;

    my @precedence_table = (
        { assoc => 'left', ops => ['+'] },
    );

    my $prec_sr = Chalk::Semiring::Precedence->new(precedence_table => \@precedence_table);
    my $bool_sr = Chalk::Semiring::Boolean->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $bool_sr]
    );

    # Use actual add_id from precedence semiring as one element
    # This simulates the case where a previous operation returned add_id
    my $prec_add_id = $prec_sr->add_id;
    my $bool_true1 = Chalk::Semiring::BooleanElement->new(value => 1);

    my $elem1 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_add_id, $bool_true1],
        parent_semiring => $composite
    );

    my $prec_valid = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 0
    );
    my $bool_true2 = Chalk::Semiring::BooleanElement->new(value => 1);

    my $elem2 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid, $bool_true2],
        parent_semiring => $composite
    );

    # Sequential filtering: Precedence.add(add_id, valid) returns valid (other)
    # Boolean.add(true, true) returns one of them (self)
    # This creates ambiguity, so use matching boolean values
    my $bool_false = Chalk::Semiring::BooleanElement->new(value => 0);
    my $elem1_fixed = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_add_id, $bool_false],
        parent_semiring => $composite
    );
    # Precedence: add_id + valid → other, Boolean: false + true → other
    my $result = $elem1_fixed->add($elem2);

    # Both semirings chose elem2, so result should be elem2 by reference
    ok $result == $elem2, 'Result is elem2 by reference (consensus on other)';

    # But what if BOTH inputs to add() are add_id?
    my $elem_both_add_id_1 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_sr->add_id, $bool_true1],
        parent_semiring => $composite
    );

    my $elem_both_add_id_2 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_sr->add_id, $bool_true1],
        parent_semiring => $composite
    );

    my $result2 = $elem_both_add_id_1->add($elem_both_add_id_2);

    # When both are add_id, Precedence.add() returns add_id
    # Sequential filtering should short-circuit
    ok $result2->equals($composite->add_id), 'Short-circuits when semiring add returns add_id';
};

subtest 'Sequential filtering: consensus when all agree' => sub {
    use Chalk::Semiring::Precedence;
    use Scalar::Util qw(refaddr);

    my @precedence_table = (
        { assoc => 'left', ops => ['+'] },
    );

    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(precedence_table => \@precedence_table);

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $bool_sr]
    );

    # Both elements valid - both semirings should prefer same element
    my $prec_valid1 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $bool_true = Chalk::Semiring::BooleanElement->new(value => 1);

    my $elem1 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid1, $bool_true],
        parent_semiring => $composite
    );

    my $prec_valid2 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $bool_true2 = Chalk::Semiring::BooleanElement->new(value => 1);

    my $elem2 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid2, $bool_true2],
        parent_semiring => $composite
    );

    my $result = $elem1->add($elem2);

    # When both valid, each semiring chooses independently
    # Boolean.add() prefers true (both are true, so should return elem1)
    # Precedence.add() when both valid returns self
    # Both should return their self element -> consensus on $elem1
    isa_ok $result, 'Chalk::Semiring::CompositeElement';
    is refaddr($result), refaddr($elem1), 'Consensus: all semirings chose self, returns original $self';
};

subtest 'Sequential filtering: ambiguity dies with diagnostic' => sub {
    use Chalk::Semiring::Precedence;

    my @precedence_table = (
        { assoc => 'left', ops => ['+'] },
    );

    my $bool_sr = Chalk::Semiring::Boolean->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(precedence_table => \@precedence_table);

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $bool_sr]
    );

    # Both precedence elements valid, so Precedence chooses self
    # But Boolean chooses other (true vs false)
    # This creates ambiguity
    my $prec_valid1 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $bool_false = Chalk::Semiring::BooleanElement->new(value => 0);

    my $elem1 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid1, $bool_false],
        parent_semiring => $composite
    );

    my $prec_valid2 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $bool_true = Chalk::Semiring::BooleanElement->new(value => 1);

    my $elem2 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid2, $bool_true],
        parent_semiring => $composite
    );

    # Should die with diagnostic showing which semiring chose what
    like dies { $elem1->add($elem2) },
        qr/Ambiguous parse in Composite\.add\(\):/,
        'Dies with ambiguity error';

    like dies { $elem1->add($elem2) },
        qr/Precedence chose self/,
        'Diagnostic shows Precedence chose self';

    like dies { $elem1->add($elem2) },
        qr/Boolean chose other/,
        'Diagnostic shows Boolean chose other';
};

# Mock rule class for testing
package MockRule {
    sub lhs { shift->{lhs} }
    sub rhs { shift->{rhs} }
    sub probability { shift->{probability} }
}
