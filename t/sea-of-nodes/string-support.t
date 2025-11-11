# ABOUTME: Test for Sea of Nodes IR generation - String support (Issue #98 Phase 4)
# ABOUTME: Validates IR generation for string concatenation, length, and substring operations

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Builder');

# Test manual IR graph construction for string operations
# This tests the IR infrastructure for Phase 4: String Support
subtest 'Manual IR graph construction for string operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node (entry point)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create constants for strings
    my $const_hello = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 'Hello', type => 'Str' }
    );
    $graph->add_node($const_hello);

    my $const_world = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => ' World', type => 'Str' }
    );
    $graph->add_node($const_world);

    # Create StrConcat node for: 'Hello' . ' World'
    my $str_concat = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'StrConcat',
        inputs => ['node_0', 'node_1', 'node_2'],  # Control, left, right
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($str_concat);

    # Create StrLength node for: length($str)
    my $str_length = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'StrLength',
        inputs => ['node_0', 'node_3'],  # Control, string
        attributes => {
            string => { op => 'NodeRef', node_id => 'node_3' }
        }
    );
    $graph->add_node($str_length);

    # Create constants for substr parameters
    my $const_offset = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 0, type => 'Int' }
    );
    $graph->add_node($const_offset);

    my $const_length = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 5, type => 'Int' }
    );
    $graph->add_node($const_length);

    # Create StrSubstr node for: substr($str, 0, 5)
    my $str_substr = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'StrSubstr',
        inputs => ['node_0', 'node_3', 'node_5', 'node_6'],  # Control, string, offset, length
        attributes => {
            string => { op => 'NodeRef', node_id => 'node_3' },
            offset => { op => 'NodeRef', node_id => 'node_5' },
            length => { op => 'NodeRef', node_id => 'node_6' }
        }
    );
    $graph->add_node($str_substr);

    # Create Return node (returns the substring)
    my $return = Chalk::IR::Node->new(
        id => 'node_8',
        op => 'Return',
        inputs => ['node_0', 'node_7'],  # Control, data
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 9, 'Graph has 9 nodes');

    # Verify StrConcat node
    my $concat_node = $graph->get_node('node_3');
    ok($concat_node, 'StrConcat node exists');
    is($concat_node->op, 'StrConcat', 'StrConcat node has correct op');
    is($concat_node->attributes->{left}{node_id}, 'node_1', 'StrConcat has correct left operand');
    is($concat_node->attributes->{right}{node_id}, 'node_2', 'StrConcat has correct right operand');

    # Verify StrLength node
    my $length_node = $graph->get_node('node_4');
    ok($length_node, 'StrLength node exists');
    is($length_node->op, 'StrLength', 'StrLength node has correct op');
    is($length_node->attributes->{string}{node_id}, 'node_3', 'StrLength references correct string');

    # Verify StrSubstr node
    my $substr_node = $graph->get_node('node_7');
    ok($substr_node, 'StrSubstr node exists');
    is($substr_node->op, 'StrSubstr', 'StrSubstr node has correct op');
    is($substr_node->attributes->{string}{node_id}, 'node_3', 'StrSubstr references correct string');
    is($substr_node->attributes->{offset}{node_id}, 'node_5', 'StrSubstr has correct offset');
    is($substr_node->attributes->{length}{node_id}, 'node_6', 'StrSubstr has correct length');
};

# Test IR Builder methods for string operations
subtest 'IR Builder methods for string support' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');
    is($start->op, 'Start', 'Builder creates Start node');

    # Build constants for strings
    my $const_hello = $builder->build_constant_node('Hello');
    my $const_world = $builder->build_constant_node(' World');

    # Build StrConcat node
    my $str_concat = $builder->build_str_concat_node($const_hello, $const_world);
    ok($str_concat, 'Builder creates StrConcat node');
    is($str_concat->op, 'StrConcat', 'StrConcat has correct op');

    # Build StrLength node
    my $str_length = $builder->build_str_length_node($str_concat);
    ok($str_length, 'Builder creates StrLength node');
    is($str_length->op, 'StrLength', 'StrLength has correct op');

    # Build constants for substr parameters
    my $const_offset = $builder->build_constant_node(0);
    my $const_length = $builder->build_constant_node(5);

    # Build StrSubstr node
    my $str_substr = $builder->build_str_substr_node($str_concat, $const_offset, $const_length);
    ok($str_substr, 'Builder creates StrSubstr node');
    is($str_substr->op, 'StrSubstr', 'StrSubstr has correct op');

    # Verify all nodes are in the graph
    ok($graph->get_node($str_concat->id), 'StrConcat in graph');
    ok($graph->get_node($str_length->id), 'StrLength in graph');
    ok($graph->get_node($str_substr->id), 'StrSubstr in graph');
};

done_testing();
