#!/usr/bin/env perl
# ABOUTME: Test pure SPPF semiring implementation
# ABOUTME: Verifies parse forest construction without scoring complexity
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Base;
use Chalk::Semiring::SPPF;

subtest 'SPPF forest node classes exist' => sub {
    ok Chalk::ParseForest->can('new'), 'SPPFForest class exists';
    ok Chalk::ParseForest::SymbolNode->can('new'), 'SPPFSymbolNode class exists';
    ok Chalk::ParseForest::PackedNode->can('new'), 'SPPFPackedNode class exists';
    ok Chalk::ParseForest::TerminalNode->can('new'), 'SPPFTerminalNode class exists';
};

subtest 'SPPFElement basic properties' => sub {
    my $forest = Chalk::ParseForest->new();
    my $node = $forest->get_or_create_symbol_node('S', 0, 5);

    my $elem = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node,
        forest    => $forest
    );

    ok $elem, 'SPPFElement created';
    ok $elem->sppf_node, 'Has SPPF node';
    ok $elem->forest, 'Has forest reference';
    is $elem->sppf_node->symbol, 'S', 'Node has correct symbol';
    is $elem->sppf_node->start_pos, 0, 'Node has correct start position';
    is $elem->sppf_node->end_pos, 5, 'Node has correct end position';
};

subtest 'SPPFElement multiplication (sequence)' => sub {
    my $forest = Chalk::ParseForest->new();
    my $node1 = $forest->get_or_create_symbol_node('A', 0, 2);
    my $node2 = $forest->get_or_create_symbol_node('B', 2, 5);

    my $elem1 = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node1,
        forest    => $forest
    );

    my $elem2 = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node2,
        forest    => $forest
    );

    my $result = $elem1->multiply($elem2);

    ok $result, 'Multiplication succeeds';
    # Lazy construction: multiply() doesn't create nodes immediately
    # Nodes are created in on_complete() when rules finish
    is scalar(@{$result->children}), 2, 'Result has 2 children';
    is $result->start_pos, 0, 'Sequence starts at first position';
    is $result->end_pos, 5, 'Sequence ends at last position';
};

subtest 'SPPFElement addition (alternatives)' => sub {
    my $forest = Chalk::ParseForest->new();
    my $node1 = $forest->get_or_create_symbol_node('E', 0, 5);
    my $node2 = $forest->get_or_create_symbol_node('E', 0, 5);

    my $elem1 = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node1,
        forest    => $forest
    );

    my $elem2 = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node2,
        forest    => $forest
    );

    my $result = $elem1->add($elem2);

    ok $result, 'Addition succeeds';
    # Add should merge alternatives into the same node
    # and return one of the elements (doesn't matter which for pure SPPF)
    ok $result->sppf_node, 'Result has SPPF node';
};

subtest 'SPPFElement to_string' => sub {
    my $forest = Chalk::ParseForest->new();
    my $node = $forest->get_or_create_symbol_node('S', 0, 5);

    my $elem = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node,
        forest    => $forest
    );

    my $str = $elem->to_string;
    ok $str, 'to_string produces output';
    like $str, qr/S/, 'Shows symbol';
    like $str, qr/\[0\(\),5\(\)\]/, 'Shows position span';
};

subtest 'SPPF semiring identity elements' => sub {
    my $semiring = Chalk::Semiring::SPPF->new();

    ok $semiring, 'SPPF semiring created';
    ok $semiring->mul_id, 'Has multiplicative identity';
    ok $semiring->add_id, 'Has additive identity';
    ok $semiring->forest, 'Has forest';

    isa_ok $semiring->forest, ['Chalk::ParseForest'];
};

subtest 'SPPF forest node creation' => sub {
    my $forest = Chalk::ParseForest->new();

    my $node1 = $forest->get_or_create_symbol_node('E', 0, 5);
    my $node2 = $forest->get_or_create_symbol_node('E', 0, 5);

    # Same key should return same node
    is $node1, $node2, 'get_or_create returns same node for same key';

    my $node3 = $forest->get_or_create_symbol_node('E', 0, 3);
    isnt $node1, $node3, 'Different span creates different node';
};

subtest 'SPPF forest intermediate node creation' => sub {
    my $forest = Chalk::ParseForest->new();

    my $left = $forest->get_or_create_symbol_node('A', 0, 2);
    my $right = $forest->get_or_create_symbol_node('B', 2, 5);

    # Create intermediate node per Scott's algorithm
    my $intermediate = $forest->get_or_create_intermediate_node('S ::= A B · C', 0, 5);

    ok $intermediate, 'Intermediate node created';
    is $intermediate->rule_label, 'S ::= A B · C', 'Intermediate node has correct rule label';
    is $intermediate->start_pos, 0, 'Intermediate starts at position 0';
    is $intermediate->end_pos, 5, 'Intermediate ends at position 5';

    # Test that same key returns same node
    my $intermediate2 = $forest->get_or_create_intermediate_node('S ::= A B · C', 0, 5);
    is $intermediate, $intermediate2, 'Same key returns same intermediate node';
};

subtest 'SPPF forest alternative merging' => sub {
    my $forest = Chalk::ParseForest->new();

    my $node1 = $forest->get_or_create_symbol_node('E', 0, 5);
    my $node2 = $forest->get_or_create_symbol_node('E', 0, 5);

    # Should be the same node due to get_or_create
    is $node1, $node2, 'Same span returns same node';

    # Add a packed node to create alternatives
    my $packed1 = Chalk::ParseForest::PackedNode->new(rule => undef);
    my $child = $forest->get_or_create_symbol_node('A', 0, 5);
    $packed1->add_child($child);
    $node1->add_packed_node($packed1);

    my @packed_before = $node1->packed_nodes;
    is scalar(@packed_before), 1, 'Node has one packed node';

    # Add alternative
    my $packed2 = Chalk::ParseForest::PackedNode->new(rule => undef);
    my $child2 = $forest->get_or_create_symbol_node('B', 0, 5);
    $packed2->add_child($child2);
    $node2->add_packed_node($packed2);

    my @packed_after = $node1->packed_nodes;
    is scalar(@packed_after), 2, 'Node now has two packed nodes (alternatives)';
};

subtest 'SPPF semiring operator overloading' => sub {
    my $forest = Chalk::ParseForest->new();
    my $node1 = $forest->get_or_create_symbol_node('A', 0, 2);
    my $node2 = $forest->get_or_create_symbol_node('B', 2, 5);

    my $elem1 = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node1,
        forest    => $forest
    );

    my $elem2 = Chalk::Semiring::SPPFElement->new(
        sppf_node => $node2,
        forest    => $forest
    );

    my $mult = $elem1 * $elem2;
    ok $mult, 'Operator * works';
    # Lazy construction: multiply doesn't create nodes immediately
    is scalar(@{$mult->children}), 2, 'Multiply creates lazy element with children';

    my $add = $elem1 + $elem2;
    ok $add, 'Operator + works';
    ok $add->sppf_node, 'Add returns element with node (prefers first arg)';
};
