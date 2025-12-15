# ABOUTME: Test for Global Value Numbering (GVN) optimization pass
# ABOUTME: Validates redundant computation elimination, common subexpression elimination, and value numbering correctness

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

# Load required modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Optimizer::GVN');

# Load type system
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

# Test 1: Elimination of redundant arithmetic (x+y computed twice)
subtest 'Eliminate redundant arithmetic' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build graph: return (x + y) + (x + y)
    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    # Constants x=3, y=5
    my $const_x = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 3, type => Chalk::IR::Type::Integer->constant(3) }
    );
    $graph->add_node($const_x);

    my $const_y = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 5, type => Chalk::IR::Type::Integer->constant(5) }
    );
    $graph->add_node($const_y);

    # First Add: x + y
    my $add1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add1);

    # Second Add: x + y (duplicate)
    my $add2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add2);

    # Third Add: (x+y) + (x+y)
    my $add3 = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Add',
        inputs => ['node_3', 'node_4'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_3' },
            right => { op => 'NodeRef', node_id => 'node_4' }
        }
    );
    $graph->add_node($add3);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Return',
        inputs => ['node_0', 'node_5'],
        attributes => {}
    );
    $graph->add_node($return);


    # Before GVN: 7 nodes
    is($graph->node_count, 7, 'Graph has 7 nodes before GVN');

    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    # After GVN: Should eliminate one Add node (node_4 is duplicate of node_3)
    ok($metrics->{nodes_eliminated} > 0, 'GVN eliminated redundant nodes');
    ok(exists $metrics->{redirections}, 'Metrics include redirection count');

    # Verify node_4 was redirected to node_3
    is($metrics->{redirections}{'node_4'}, 'node_3',
       'Duplicate Add node redirected to canonical');
};

# Test 2: Common subexpression elimination (a*b used twice)
subtest 'Common subexpression elimination' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build graph: return (a*b) + (a*b)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    # Constants a=4, b=7
    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 4, type => Chalk::IR::Type::Integer->constant(4) }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 7, type => Chalk::IR::Type::Integer->constant(7) }
    );
    $graph->add_node($const_b);

    # First Multiply: a * b
    my $mul1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Multiply',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($mul1);

    # Second Multiply: a * b (duplicate)
    my $mul2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Multiply',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($mul2);

    # Add: (a*b) + (a*b)
    my $add = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Add',
        inputs => ['node_3', 'node_4'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_3' },
            right => { op => 'NodeRef', node_id => 'node_4' }
        }
    );
    $graph->add_node($add);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Return',
        inputs => ['node_0', 'node_5'],
        attributes => {}
    );
    $graph->add_node($return);


    is($graph->node_count, 7, 'Graph has 7 nodes before GVN');

    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    ok($metrics->{nodes_eliminated} > 0, 'GVN eliminated duplicate Multiply');
    is($metrics->{redirections}{'node_4'}, 'node_3',
       'Duplicate Multiply redirected to canonical');
};

# Test 3: Commutativity handling (Add(a,b) === Add(b,a))
subtest 'Commutativity in Add operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    # Constants
    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => Chalk::IR::Type::Integer->constant(10) }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 20, type => Chalk::IR::Type::Integer->constant(20) }
    );
    $graph->add_node($const_b);

    # Add: a + b
    my $add1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add1);

    # Add: b + a (commuted, should be recognized as same)
    my $add2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Add',
        inputs => ['node_2', 'node_1'],  # Reversed order
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_1' }
        }
    );
    $graph->add_node($add2);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Return',
        inputs => ['node_0', 'node_4'],
        attributes => {}
    );
    $graph->add_node($return);


    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $metrics = $result->{metrics};

    # Should recognize commutative equivalence
    ok($metrics->{nodes_eliminated} > 0,
       'GVN recognized commutative Add operations as equivalent');
    ok(exists $metrics->{redirections}{'node_4'},
       'Commuted Add was redirected');
};

# Test 4: Commutativity in Multiply operations
subtest 'Commutativity in Multiply operations' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 6, type => Chalk::IR::Type::Integer->constant(6) }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 9, type => Chalk::IR::Type::Integer->constant(9) }
    );
    $graph->add_node($const_b);

    # Multiply: a * b
    my $mul1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Multiply',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($mul1);

    # Multiply: b * a (commuted)
    my $mul2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Multiply',
        inputs => ['node_2', 'node_1'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_1' }
        }
    );
    $graph->add_node($mul2);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Return',
        inputs => ['node_0', 'node_4'],
        attributes => {}
    );
    $graph->add_node($return);


    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $metrics = $result->{metrics};

    ok($metrics->{nodes_eliminated} > 0,
       'GVN recognized commutative Multiply operations');
};

# Test 5: Different constants should NOT be merged
TODO: {
local $TODO = "see issue #200";
subtest 'Different constants are not merged' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    # Two different constants
    my $const1 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42, type => Chalk::IR::Type::Integer->constant(42) }
    );
    $graph->add_node($const1);

    my $const2 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 99, type => Chalk::IR::Type::Integer->constant(99) }
    );
    $graph->add_node($const2);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    );
    $graph->add_node($return);


    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    # Should NOT merge different constants
    ok($optimized->get_node('node_1'), 'First constant still exists');
    ok($optimized->get_node('node_2'), 'Second constant still exists');
    is($metrics->{nodes_eliminated}, 0, 'No nodes eliminated (constants differ)');
};
} # end TODO

# Test 6: Same constants SHOULD be merged
subtest 'Identical constants are merged' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    # Two identical constants
    my $const1 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42, type => Chalk::IR::Type::Integer->constant(42) }
    );
    $graph->add_node($const1);

    my $const2 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42, type => Chalk::IR::Type::Integer->constant(42) }
    );
    $graph->add_node($const2);

    # Add using both constants
    my $add = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_0', 'node_3'],
        attributes => {}
    );
    $graph->add_node($return);


    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $metrics = $result->{metrics};

    ok($metrics->{nodes_eliminated} > 0, 'Duplicate constant eliminated');
    ok(exists $metrics->{redirections}{'node_2'},
       'Second constant redirected to first');
};

# Test 7: Idempotence - running GVN twice should not change anything
subtest 'GVN is idempotent' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 5, type => Chalk::IR::Type::Integer->constant(5) }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 5, type => Chalk::IR::Type::Integer->constant(5) }
    );
    $graph->add_node($const_b);

    my $add = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add);

    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_0', 'node_3'],
        attributes => {}
    );
    $graph->add_node($return);


    # First GVN pass
    my $result1 = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $graph1 = $result1->{graph};
    my $metrics1 = $result1->{metrics};

    ok($metrics1->{nodes_eliminated} > 0, 'First pass eliminated nodes');

    # Second GVN pass
    my $result2 = Chalk::IR::Optimizer::GVN->run_gvn($graph1);
    my $metrics2 = $result2->{metrics};

    is($metrics2->{nodes_eliminated}, 0,
       'Second pass eliminated no nodes (idempotent)');
};

# Test 8: Non-commutative operations (Subtract) should respect order
TODO: {
local $TODO = "see issue #200";
subtest 'Non-commutative operations respect order' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => Chalk::IR::Type::Integer->constant(10) }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 3, type => Chalk::IR::Type::Integer->constant(3) }
    );
    $graph->add_node($const_b);

    # Subtract: a - b (should be 7)
    my $sub1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Subtract',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($sub1);

    # Subtract: b - a (should be -7, different!)
    my $sub2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Subtract',
        inputs => ['node_2', 'node_1'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_1' }
        }
    );
    $graph->add_node($sub2);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Return',
        inputs => ['node_0', 'node_4'],
        attributes => {}
    );
    $graph->add_node($return);


    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    # Should NOT merge - they're different operations
    ok($optimized->get_node('node_3'), 'First Subtract still exists');
    ok($optimized->get_node('node_4'), 'Second Subtract still exists');
    is($metrics->{nodes_eliminated}, 0,
       'No elimination for non-commutative operations with different order');
};
} # end TODO

# Test 9: Proj nodes with different indices should not merge
subtest 'Proj nodes respect index differences' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    # If node
    my $if_node = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'If',
        inputs => ['node_0'],
        attributes => {
            condition => { op => 'Constant', value => 1, type => Chalk::IR::Type::Integer->constant(1) }
        }
    );
    $graph->add_node($if_node);

    # Proj index 0 (true branch)
    my $proj0 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_1'],
        attributes => { index => 0 }
    );
    $graph->add_node($proj0);

    # Proj index 1 (false branch)
    my $proj1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Proj',
        inputs => ['node_1'],
        attributes => { index => 1 }
    );
    $graph->add_node($proj1);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_0', 'node_2'],
        attributes => {}
    );
    $graph->add_node($return);


    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $optimized = $result->{graph};
    my $metrics = $result->{metrics};

    # Should NOT merge - different indices
    ok($optimized->get_node('node_2'), 'Proj index 0 still exists');
    ok($optimized->get_node('node_3'), 'Proj index 1 still exists');
    is($metrics->{nodes_eliminated}, 0,
       'Proj nodes with different indices not merged');
};

# Test 10: Complex expression with multiple common subexpressions
subtest 'Complex expression optimization' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: ((a+b) * (a+b)) + ((a+b) * (a+b))
    # Should recognize (a+b) computed 4 times, (a+b)*(a+b) computed twice
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function_name => 'main' }
    );
    $graph->add_node($start);

    my $const_a = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 2, type => Chalk::IR::Type::Integer->constant(2) }
    );
    $graph->add_node($const_a);

    my $const_b = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 3, type => Chalk::IR::Type::Integer->constant(3) }
    );
    $graph->add_node($const_b);

    # First (a+b)
    my $add1 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add1);

    # Second (a+b) - duplicate
    my $add2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add2);

    # First (a+b) * (a+b)
    my $mul1 = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'Multiply',
        inputs => ['node_3', 'node_4'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_3' },
            right => { op => 'NodeRef', node_id => 'node_4' }
        }
    );
    $graph->add_node($mul1);

    # Third (a+b) - duplicate
    my $add3 = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add3);

    # Fourth (a+b) - duplicate
    my $add4 = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_2' }
        }
    );
    $graph->add_node($add4);

    # Second (a+b) * (a+b) - duplicate
    my $mul2 = Chalk::IR::Node->new(
        id => 'node_8',
        op => 'Multiply',
        inputs => ['node_6', 'node_7'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_6' },
            right => { op => 'NodeRef', node_id => 'node_7' }
        }
    );
    $graph->add_node($mul2);

    # Final add: (a+b)*(a+b) + (a+b)*(a+b)
    my $final_add = Chalk::IR::Node->new(
        id => 'node_9',
        op => 'Add',
        inputs => ['node_5', 'node_8'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_5' },
            right => { op => 'NodeRef', node_id => 'node_8' }
        }
    );
    $graph->add_node($final_add);

    # Return
    my $return = Chalk::IR::Node->new(
        id => 'node_10',
        op => 'Return',
        inputs => ['node_0', 'node_9'],
        attributes => {}
    );
    $graph->add_node($return);


    is($graph->node_count, 11, 'Graph has 11 nodes before GVN');

    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $metrics = $result->{metrics};

    # Should eliminate: 3 duplicate (a+b), 1 duplicate (a+b)*(a+b) = 4 nodes
    ok($metrics->{nodes_eliminated} >= 4,
       "GVN eliminated multiple redundant subexpressions (eliminated: $metrics->{nodes_eliminated})");
};

# Test: GVN preserves polymorphic node types
TODO: {
local $TODO = "see issue #200";
subtest 'GVN preserves polymorphic node types' => sub {
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Node::Add;
    use Chalk::IR::Node::Multiply;
    use Chalk::IR::Node::Start;
    use Chalk::IR::Node::Return;

    my $graph = Chalk::IR::Graph->new();

    # Build graph with polymorphic nodes using V2 API: (3 + 5) * (3 + 5)
    # V2 nodes compute their own IDs from their operands
    my $start = Chalk::IR::Node::Start->new(
        function_name => 'test',
        params => [],
    );
    $graph->add_node($start);

    my $const3 = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::IR::Type::Integer->constant(3),
    );
    $graph->add_node($const3);

    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );
    $graph->add_node($const5);

    # First Add: 3 + 5 (V2 API takes node objects, not IDs)
    my $add1 = Chalk::IR::Node::Add->new(
        left => $const3,
        right => $const5,
    );
    $graph->add_node($add1);

    # Second Add: 3 + 5 (duplicate - same operands = same content-addressable ID)
    # Note: V2 nodes with same operands will have same ID, so this tests
    # whether the graph handles that correctly
    my $add2 = Chalk::IR::Node::Add->new(
        left => $const3,
        right => $const5,
    );
    $graph->add_node($add2);

    # Multiply: (3+5) * (3+5)
    my $multiply = Chalk::IR::Node::Multiply->new(
        left => $add1,
        right => $add2,
    );
    $graph->add_node($multiply);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        value => $multiply,
        control => $start,
    );
    $graph->add_node($return);

    $graph->set_entry($start->id);


    # Verify nodes are polymorphic before GVN
    is(ref($graph->nodes->{$add1->id}), 'Chalk::IR::Node::Add', 'Add node is polymorphic before GVN');
    is(ref($graph->nodes->{$multiply->id}), 'Chalk::IR::Node::Multiply', 'Multiply node is polymorphic before GVN');

    # Run GVN
    my $result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    my $new_graph = $result->{graph};
    my $metrics = $result->{metrics};

    # With content-addressable IDs, add1 and add2 have the same ID,
    # so only one gets added to graph - GVN may not eliminate anything
    # The key test is that polymorphic types are preserved
    ok(defined($metrics->{nodes_eliminated}), 'GVN ran and reported metrics');

    # Verify nodes are STILL polymorphic after GVN (this is the key test!)
    my @add_nodes = grep { $_->op eq 'Add' } values %{$new_graph->nodes};
    ok(scalar(@add_nodes) >= 1, 'At least one Add node remains');
    is(ref($add_nodes[0]), 'Chalk::IR::Node::Add',
       'Add node is STILL polymorphic after GVN (not Chalk::IR::Node)');

    my @multiply_nodes = grep { $_->op eq 'Multiply' } values %{$new_graph->nodes};
    is(scalar(@multiply_nodes), 1, 'One Multiply node remains');
    is(ref($multiply_nodes[0]), 'Chalk::IR::Node::Multiply',
       'Multiply node is STILL polymorphic after GVN (not Chalk::IR::Node)');

    # Verify nodes have execute() methods
    ok($add_nodes[0]->can('execute'), 'Polymorphic Add has execute() method');
    ok($multiply_nodes[0]->can('execute'), 'Polymorphic Multiply has execute() method');
};
} # end TODO

done_testing();
