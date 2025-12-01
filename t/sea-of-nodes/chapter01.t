# ABOUTME: Test for Sea of Nodes IR generation - Chapter 1: Simplest program
# ABOUTME: Validates core node types: Start, Return, Constant - the minimum viable IR

use lib 'lib';
use v5.42;
use Test::More;
use Test::Deep;

# Chapter 1 scope from SeaOfNodes/Simple:
# - Start node: function entry point, no inputs
# - Return node: takes control and data inputs
# - Constant node: leaf node holding literal value
# - Test program: "return 1;" - the simplest possible program

# Test that we can load the core IR node modules
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Return');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Grammar::Chalk');
use_ok('Chalk::Semiring::ChalkIR');
use_ok('Chalk::IR::Node::Scope');

# === Part 1: Direct Node Construction Tests ===
# These test the node classes in isolation (unit tests)

subtest 'Start node: function entry point' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');

    # Start has no inputs (entry point)
    is_deeply($start->inputs, [], 'Start node has no inputs');

    # op() returns node type
    is($start->op, 'Start', 'Start node op() returns "Start"');

    # id() returns unique identifier (refaddr)
    ok($start->id, 'Start node has an id');
    ok($start->id =~ /^\d+$/, 'Start node id is numeric (refaddr)');

    # to_hash() for serialization
    my $hash = $start->to_hash;
    is($hash->{op}, 'Start', 'to_hash includes op');
    is_deeply($hash->{inputs}, [], 'to_hash inputs is empty array');
    is($hash->{attributes}{label}, 'main', 'to_hash includes label attribute');
};

subtest 'Constant node: literal value' => sub {
    my $const = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => 'Int',
    );

    # Constant has no inputs (leaf node)
    is_deeply($const->inputs, [], 'Constant node has no inputs');

    # op() returns node type
    is($const->op, 'Constant', 'Constant node op() returns "Constant"');

    # Value accessor
    is($const->value, 1, 'Constant node value is 1');
    is($const->type, 'Int', 'Constant node type is Int');

    # id() returns unique identifier
    ok($const->id, 'Constant node has an id');

    # to_hash() for serialization
    my $hash = $const->to_hash;
    is($hash->{op}, 'Constant', 'to_hash includes op');
    is($hash->{attributes}{value}, 1, 'to_hash includes value');
    is($hash->{attributes}{type}, 'Int', 'to_hash includes type');
};

subtest 'Return node: function exit' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');
    my $const = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');

    my $return = Chalk::IR::Node::Return->new(
        control => $start,
        value   => $const,
    );

    # op() returns node type
    is($return->op, 'Return', 'Return node op() returns "Return"');

    # inputs() builds from control and value
    my $inputs = $return->inputs;
    is(scalar(@$inputs), 2, 'Return node has 2 inputs');
    is($inputs->[0], $start->id, 'First input is control (Start id)');
    is($inputs->[1], $const->id, 'Second input is value (Constant id)');

    # Accessors
    is($return->control, $start, 'control() returns Start node');
    is($return->value, $const, 'value() returns Constant node');

    # to_hash() for serialization
    my $hash = $return->to_hash;
    is($hash->{op}, 'Return', 'to_hash includes op');
    is($hash->{attributes}{control_id}, $start->id, 'to_hash includes control_id');
    is($hash->{attributes}{value_id}, $const->id, 'to_hash includes value_id');
};

subtest 'Node ID uniqueness' => sub {
    my $start = Chalk::IR::Node::Start->new(label => 'main');
    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Int');
    my $return = Chalk::IR::Node::Return->new(control => $start, value => $const1);

    # All nodes should have unique IDs
    my @ids = ($start->id, $const1->id, $const2->id, $return->id);
    my %seen;
    $seen{$_}++ for @ids;

    is(scalar(keys %seen), 4, 'All 4 nodes have unique IDs');
    my @duplicates = grep { $_ > 1 } values %seen;
    is(scalar(@duplicates), 0, 'No duplicate IDs');
};

# === Part 2: Graph Building Tests ===
# These test that nodes can be assembled into a graph

subtest 'Build minimal graph: Start -> Return(Constant)' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(label => 'main');
    my $const = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $return = Chalk::IR::Node::Return->new(control => $start, value => $const);

    $graph->add_node($start);
    $graph->add_node($const);
    $graph->add_node($return);

    is($graph->node_count, 3, 'Graph has 3 nodes');

    # Verify nodes are retrievable
    ok($graph->get_node($start->id), 'Can retrieve Start node');
    ok($graph->get_node($const->id), 'Can retrieve Constant node');
    ok($graph->get_node($return->id), 'Can retrieve Return node');
};

# === Part 3: Parser Integration Tests ===
# These test that parsing "return 1;" produces the expected IR

# Helper to create parser for testing
sub make_parser {
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

    my $semiring = Chalk::Semiring::ChalkIR->new(
        grammar => $grammar
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    return $parser;
}

# Helper to build graph from winning parse node
sub build_graph_from_result {
    my ($result) = @_;
    return undef unless $result && $result->can('context');

    my $ctx = $result->context;
    return undef unless $ctx && $ctx->can('focus');

    my $winning_node = $ctx->focus;
    return undef unless blessed($winning_node) && $winning_node->can('id');

    # Build graph by traversing from winning node
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        # Traverse via object references
        for my $accessor (qw(value_node value control left right operand condition source)) {
            next unless $node->can($accessor);
            # Skip value for Constant nodes (it's not a node reference)
            next if $accessor eq 'value' && $node->can('op') && $node->op eq 'Constant';
            my $ref = $node->$accessor;
            push @queue, $ref if blessed($ref) && $ref->can('id') && !$visited{$ref->id};
        }
        # Traverse Stop's returns
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
            }
        }
    }

    return $graph;
}

subtest 'Parse: return 1; - the simplest program' => sub {
    my $parser = make_parser();

    # Chapter 1 canonical example: return 1;
    my $code = 'return 1;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded for "return 1;"');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');
    ok($graph->node_count > 0, 'Graph has nodes');

    my @nodes = values %{$graph->nodes};

    # Should have Return node
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Has exactly one Return node');

    # Should have Constant node for 1
    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 1, 'Has at least one Constant node');

    # Verify the constant value
    my @ones = grep { $_->value == 1 || $_->value eq '1' } @constants;
    ok(scalar(@ones) >= 1, 'Has Constant node with value 1');
};

subtest 'Parse: return 42; - another constant' => sub {
    my $parser = make_parser();

    my $code = 'return 42;';
    my $result = $parser->parse_string($code);
    ok($result, 'Parse succeeded for "return 42;"');

    my $graph = build_graph_from_result($result);
    ok($graph, 'Graph built from result');

    my @nodes = values %{$graph->nodes};

    # Should have Return and Constant nodes
    my @returns = grep { $_->op eq 'Return' } @nodes;
    is(scalar(@returns), 1, 'Has Return node');

    my @constants = grep { $_->op eq 'Constant' } @nodes;
    ok(scalar(@constants) >= 1, 'Has Constant node');

    # Verify constant 42 exists
    my @fortytwos = grep { $_->value == 42 || $_->value eq '42' } @constants;
    ok(scalar(@fortytwos) >= 1, 'Has Constant node with value 42');
};

# === Part 4: Comparison with Simple's chapter01 behavior ===

subtest 'Chapter 1 compliance: node structure matches Simple' => sub {
    # Simple's chapter01 defines:
    # - Start: no inputs, isCFG() = true
    # - Return: inputs = [ctrl, data], isCFG() = true
    # - Constant: inputs = [Start] for traversal (Chalk differs here)

    my $start = Chalk::IR::Node::Start->new(label => 'test');
    my $const = Chalk::IR::Node::Constant->new(value => 1, type => 'Int');
    my $return = Chalk::IR::Node::Return->new(control => $start, value => $const);

    # Start compliance
    is_deeply($start->inputs, [], 'Start has no inputs (matches Simple)');
    is($start->op, 'Start', 'Start op is "Start"');

    # Return compliance
    my $ret_inputs = $return->inputs;
    is(scalar(@$ret_inputs), 2, 'Return has 2 inputs: [ctrl, data] (matches Simple)');

    # Constant difference: Simple has Start as input for traversal
    # Chalk has no inputs (pure leaf node)
    is_deeply($const->inputs, [], 'Constant has no inputs (Chalk design choice)');

    # Document the difference
    pass('Note: Simple Constants have Start as input for traversal; Chalk uses pure leaf nodes');
};

done_testing();
