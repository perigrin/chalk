#!/usr/bin/env perl
# ABOUTME: Test IR::Node transformation chain tracking for debugging transformations
# ABOUTME: Verify nodes can record and retrieve transformation history
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::IR::Node;
use Chalk::IR::SourceInfo;

# Test 1: Node without transform_chain
{
    my $node = Chalk::IR::Node->new(
        id => 1,
        op => 'Constant',
        inputs => [],
        attributes => {value => 42},
    );

    isa_ok($node, 'Chalk::IR::Node', 'Node without transform_chain created');
    is($node->transform_chain, undef, 'transform_chain is undef when not provided');
    is($node->transform_history, undef, 'transform_history returns undef when no chain');
}

# Test 2: Node with empty transform_chain
{
    my $node = Chalk::IR::Node->new(
        id => 2,
        op => 'Add',
        inputs => [3, 4],
        attributes => {},
        transform_chain => [],
    );

    isa_ok($node, 'Chalk::IR::Node', 'Node with empty transform_chain created');
    is(ref($node->transform_chain), 'ARRAY', 'transform_chain is arrayref');
    is(scalar($node->transform_chain->@*), 0, 'empty transform_chain has zero elements');
}

# Test 3: record_transform method
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 10,
        start_col  => 5,
        end_line   => 10,
        end_col    => 15,
        start_pos  => 100,
        end_pos    => 110,
    );

    my $original_node = Chalk::IR::Node->new(
        id => 5,
        op => 'Constant',
        inputs => [],
        attributes => {value => 42},
        source_info => $source_info,
    );

    # Record a transformation
    my $new_node = $original_node->record_transform(
        operation => 'semantic_action',
        rule_name => 'IntegerLiteral',
        description => 'Parse integer literal',
    );

    isa_ok($new_node, 'Chalk::IR::Node', 'record_transform returns a node');
    isnt($new_node, $original_node, 'record_transform returns a new node instance');
    is(ref($new_node->transform_chain), 'ARRAY', 'new node has transform_chain');
    is(scalar($new_node->transform_chain->@*), 1, 'transform_chain has one entry');

    my $transform = $new_node->transform_chain->[0];
    is($transform->{operation}, 'semantic_action', 'transform records operation');
    is($transform->{rule_name}, 'IntegerLiteral', 'transform records rule_name');
    is($transform->{description}, 'Parse integer literal', 'transform records description');
    ok(exists $transform->{timestamp}, 'transform includes timestamp');
    is($transform->{source_node_id}, 5, 'transform records source node id');
}

# Test 4: Chaining multiple transformations
{
    my $node1 = Chalk::IR::Node->new(
        id => 10,
        op => 'Constant',
        inputs => [],
        attributes => {value => 5},
    );

    my $node2 = $node1->record_transform(
        operation => 'optimization',
        rule_name => 'constant_folding',
        description => 'Fold constant expression',
    );

    my $node3 = $node2->record_transform(
        operation => 'type_inference',
        rule_name => 'infer_int_type',
        description => 'Infer integer type',
    );

    is(scalar($node3->transform_chain->@*), 2, 'chained transformations accumulate');
    is($node3->transform_chain->[0]{operation}, 'optimization', 'first transform preserved');
    is($node3->transform_chain->[1]{operation}, 'type_inference', 'second transform added');
}

# Test 5: transform_history formatted output
{
    my $node = Chalk::IR::Node->new(
        id => 20,
        op => 'Add',
        inputs => [21, 22],
        attributes => {},
    );

    my $transformed = $node->record_transform(
        operation => 'semantic_action',
        rule_name => 'BinaryOp',
        description => 'Parse binary addition',
    );

    my $history = $transformed->transform_history();
    isnt($history, undef, 'transform_history returns formatted string');
    like($history, qr/semantic_action/, 'history includes operation type');
    like($history, qr/BinaryOp/, 'history includes rule name');
}

done_testing();
