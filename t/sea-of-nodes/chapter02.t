# ABOUTME: Test for Sea of Nodes IR generation - Chapter 2: Arithmetic expressions
# ABOUTME: Validates arithmetic operations (Add, Multiply, Subtract, Divide) with constant folding and operator precedence

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');

# Test simple addition with constants (should fold to constant)
subtest 'Constant folding: 1 + 2 -> 3' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Add node with two constant operands
    # This should perform constant folding and become a Constant node
    my $add = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Add',
        inputs => ['node_0'],  # Non-semantic edge to Start
        attributes => {
            left => { op => 'Constant', value => 1, type => 'Int' },
            right => { op => 'Constant', value => 2, type => 'Int' },
        }
    );
    my $folded = $add->peephole($graph);

    # After peephole optimization, should be a constant
    ok($folded, 'Peephole returned a node');
    is($folded->op, 'Constant', 'Add(1, 2) folded to Constant');
    is($folded->attributes->{value}, 3, 'Folded constant has value 3');
};

# Test multiplication with constants (should fold)
subtest 'Constant folding: 2 * 3 -> 6' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Multiply node with two constant operands
    my $mul = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Multiply',
        inputs => ['node_0'],
        attributes => {
            left => { op => 'Constant', value => 2, type => 'Int' },
            right => { op => 'Constant', value => 3, type => 'Int' },
        }
    );
    my $folded = $mul->peephole($graph);

    ok($folded, 'Peephole returned a node');
    is($folded->op, 'Constant', 'Multiply(2, 3) folded to Constant');
    is($folded->attributes->{value}, 6, 'Folded constant has value 6');
};

# Test subtraction with constants (should fold)
subtest 'Constant folding: 5 - 2 -> 3' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $sub = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Subtract',
        inputs => ['node_0'],
        attributes => {
            left => { op => 'Constant', value => 5, type => 'Int' },
            right => { op => 'Constant', value => 2, type => 'Int' },
        }
    );
    my $folded = $sub->peephole($graph);

    ok($folded, 'Peephole returned a node');
    is($folded->op, 'Constant', 'Subtract(5, 2) folded to Constant');
    is($folded->attributes->{value}, 3, 'Folded constant has value 3');
};

# Test division with constants (should fold)
subtest 'Constant folding: 6 / 2 -> 3' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $div = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Divide',
        inputs => ['node_0'],
        attributes => {
            left => { op => 'Constant', value => 6, type => 'Int' },
            right => { op => 'Constant', value => 2, type => 'Int' },
        }
    );
    my $folded = $div->peephole($graph);

    ok($folded, 'Peephole returned a node');
    is($folded->op, 'Constant', 'Divide(6, 2) folded to Constant');
    is($folded->attributes->{value}, 3, 'Folded constant has value 3');
};

# Test manual IR graph construction for: return 1 + 2 * 3;
# Expected: Add(Constant(1), Multiply(Constant(2), Constant(3)))
# After folding: Add(Constant(1), Constant(6)) -> Constant(7)
subtest 'Manual IR graph construction for return 1 + 2 * 3' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Multiply node: 2 * 3
    # With constant folding, this becomes Constant(6)
    my $mul = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Multiply',
        inputs => ['node_0'],
        attributes => {
            left => { op => 'Constant', value => 2, type => 'Int' },
            right => { op => 'Constant', value => 3, type => 'Int' },
        }
    );
    $graph->add_node($mul);

    # Create Add node: 1 + (result of multiply)
    # This will reference the Multiply node as input
    my $add = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Add',
        inputs => ['node_0', 'node_1'],  # Start and Multiply
        attributes => {
            left => { op => 'Constant', value => 1, type => 'Int' },
            right => { op => 'NodeRef', node_id => 'node_1' },  # Reference to Multiply
        }
    );
    $graph->add_node($add);

    # Create Return node
    my $return = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_0', 'node_2'],  # Control from Start, data from Add
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 4, 'Graph has 4 nodes');

    # Verify Multiply node
    my $mul_node = $graph->get_node('node_1');
    ok($mul_node, 'Multiply node exists');
    is($mul_node->op, 'Multiply', 'Multiply node has correct op');
    is($mul_node->attributes->{left}{value}, 2, 'Multiply left operand is 2');
    is($mul_node->attributes->{right}{value}, 3, 'Multiply right operand is 3');

    # Verify Add node
    my $add_node = $graph->get_node('node_2');
    ok($add_node, 'Add node exists');
    is($add_node->op, 'Add', 'Add node has correct op');
    is($add_node->attributes->{left}{value}, 1, 'Add left operand is 1');
    is($add_node->attributes->{right}{node_id}, 'node_1', 'Add right operand references Multiply');

    # Verify Return node
    my $ret_node = $graph->get_node('node_3');
    ok($ret_node, 'Return node exists');
    is($ret_node->op, 'Return', 'Return node has correct op');
    cmp_deeply($ret_node->inputs, ['node_0', 'node_2'],
               'Return connects to Start (control) and Add (data)');
};

# Test IR Builder generates correct IR for arithmetic expression
# TODO: Re-enable when parser integration is complete
SKIP: {
    skip 'build_from_code removed - use parser with semantic actions instead', 1;

subtest 'IR Builder generates correct IR for return 1 + 2 * 3' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->build_from_code("return 1 + 2 * 3;");

    # Verify graph structure
    ok($graph, 'Builder returns a graph');
    is($graph->node_count, 4, 'Generated graph has 4 nodes (Start, Multiply, Add, Return)');

    # Verify Start node
    my $start_node = $graph->get_node('node_0');
    ok($start_node, 'Start node exists');
    is($start_node->op, 'Start', 'Start node has correct op');

    # Verify Multiply node (2 * 3)
    my $mul_node = $graph->get_node('node_1');
    ok($mul_node, 'Multiply node exists');
    is($mul_node->op, 'Multiply', 'Multiply node has correct op');
    is($mul_node->attributes->{left}{value}, 2, 'Multiply left operand is 2');
    is($mul_node->attributes->{right}{value}, 3, 'Multiply right operand is 3');

    # Verify Add node (1 + mul_result)
    my $add_node = $graph->get_node('node_2');
    ok($add_node, 'Add node exists');
    is($add_node->op, 'Add', 'Add node has correct op');
    is($add_node->attributes->{left}{value}, 1, 'Add left operand is 1');
    is($add_node->attributes->{right}{node_id}, 'node_1', 'Add right operand references Multiply');

    # Verify Return node
    my $ret_node = $graph->get_node('node_3');
    ok($ret_node, 'Return node exists');
    is($ret_node->op, 'Return', 'Return node has correct op');
    cmp_deeply($ret_node->inputs, ['node_0', 'node_2'],
               'Return connects to Start (control) and Add (data)');
};
}  # End SKIP

# Test JSON serialization for arithmetic expressions
subtest 'JSON serialization of arithmetic IR' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create a simple Add: 10 + 20
    my $add = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Add',
        inputs => ['node_0'],
        attributes => {
            left => { op => 'Constant', value => 10, type => 'Int' },
            right => { op => 'Constant', value => 20, type => 'Int' },
        }
    );
    $graph->add_node($add);

    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    );
    $graph->add_node($return);

    # Convert to JSON
    my $json = $graph->to_json();
    ok($json, 'Graph can be serialized to JSON');

    # Verify JSON structure
    is($json->{version}, '1.0', 'JSON has version 1.0');
    is($json->{entry}, 'node_0', 'JSON has correct entry node');
    is(scalar @{$json->{nodes}}, 3, 'JSON has 3 nodes');

    # Find nodes in JSON by ID
    my %json_nodes = map { $_->{id} => $_ } @{$json->{nodes}};

    # Verify Add node in JSON
    ok(exists $json_nodes{'node_1'}, 'Add node in JSON');
    is($json_nodes{'node_1'}{op}, 'Add', 'Add node op in JSON');
    is($json_nodes{'node_1'}{attributes}{left}{value}, 10, 'Add left value in JSON');
    is($json_nodes{'node_1'}{attributes}{right}{value}, 20, 'Add right value in JSON');
};

# Test that non-constant arithmetic doesn't fold
subtest 'No folding when operands are not constants' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Add node where right operand is a node reference, not a constant
    my $add = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Add',
        inputs => ['node_0'],
        attributes => {
            left => { op => 'Constant', value => 1, type => 'Int' },
            right => { op => 'NodeRef', node_id => 'node_0' },  # Reference to another node
        }
    );
    my $result = $add->peephole($graph);

    # Should return the original node unchanged (or a new node with same op)
    ok($result, 'Peephole returned a node');
    is($result->op, 'Add', 'Add with non-constant operand remains Add');
};

done_testing();
