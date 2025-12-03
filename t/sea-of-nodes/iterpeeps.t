# ABOUTME: Tests for IterPeeps worklist-based iterative peephole optimization
# ABOUTME: Validates fixed-point convergence where single-pass optimization is insufficient

use lib 'lib';
use v5.42;
use Test::More;
use Test::Deep;

# Load required modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::Add');
use_ok('Chalk::IR::Node::Multiply');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Optimizer::IterPeeps');

# Test 1: Basic construction and empty graph
subtest 'IterPeeps construction' => sub {
    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    ok(defined($iterpeeps), 'IterPeeps can be constructed');

    # Empty graph should pass through unchanged
    my $graph = Chalk::IR::Graph->new();
    my $result = $iterpeeps->apply($graph);
    is($result->node_count, 0, 'Empty graph remains empty');
};

# Test 2: Single constant folding (single pass sufficient)
subtest 'Single constant folding' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: 1 + 2
    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $add = Chalk::IR::Node::Add->new(left => $const1, right => $const2);

    $graph->add_node($const1);
    $graph->add_node($const2);
    $graph->add_node($add);

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # The Add should be replaced with Constant(3)
    # We should have fewer nodes after optimization
    ok($result->node_count <= $graph->node_count, 'Optimization does not increase node count');
};

# Test 3: Iterative optimization - the key test case
# (1 + 2) * (3 + 4) should fold to 21 in multiple iterations
subtest 'Iterative constant folding' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: (1 + 2) * (3 + 4)
    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $const3 = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $const4 = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');

    my $add1 = Chalk::IR::Node::Add->new(left => $const1, right => $const2);    # 1 + 2 = 3
    my $add2 = Chalk::IR::Node::Add->new(left => $const3, right => $const4);    # 3 + 4 = 7
    my $mul = Chalk::IR::Node::Multiply->new(left => $add1, right => $add2);    # 3 * 7 = 21

    $graph->add_node($const1);
    $graph->add_node($const2);
    $graph->add_node($const3);
    $graph->add_node($const4);
    $graph->add_node($add1);
    $graph->add_node($add2);
    $graph->add_node($mul);

    is($graph->node_count, 7, 'Graph starts with 7 nodes');

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # After full optimization, we should have reduced nodes
    # The multiply node should have been replaced with a constant
    # Check that we have a constant 21 somewhere in the result
    my $found_21 = 0;
    for my $node_id (keys %{$result->nodes}) {
        my $node = $result->get_node($node_id);
        if ($node->op eq 'Constant') {
            my $attrs = $node->attributes;
            if (defined($attrs->{value}) && $attrs->{value} == 21) {
                $found_21 = 1;
                last;
            }
        }
    }

    ok($found_21, 'Iterative optimization folds (1+2)*(3+4) to 21');
};

# Test 4: Worklist adds users when node changes
subtest 'Users added to worklist on change' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: (1 + 2) + x where x is a variable (non-constant)
    # The (1 + 2) should fold to 3, and then the outer Add
    # should be re-checked (though it won't fold further without x being constant)
    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $const_x = Chalk::IR::Node::Constant->new(value => 10, type => 'Integer');  # Using constant as stand-in

    my $add_inner = Chalk::IR::Node::Add->new(left => $const1, right => $const2);  # 1 + 2 = 3
    my $add_outer = Chalk::IR::Node::Add->new(left => $add_inner, right => $const_x);  # 3 + 10 = 13

    $graph->add_node($const1);
    $graph->add_node($const2);
    $graph->add_node($const_x);
    $graph->add_node($add_inner);
    $graph->add_node($add_outer);

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # Should fold to 13
    my $found_13 = 0;
    for my $node_id (keys %{$result->nodes}) {
        my $node = $result->get_node($node_id);
        if ($node->op eq 'Constant') {
            my $attrs = $node->attributes;
            if (defined($attrs->{value}) && $attrs->{value} == 13) {
                $found_13 = 1;
                last;
            }
        }
    }

    ok($found_13, 'Nested addition (1+2)+10 folds to 13 via worklist iteration');
};

# Test 5: Fixed-point convergence (no infinite loops)
subtest 'Fixed-point convergence' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build a graph that won't change - just constants
    my $const1 = Chalk::IR::Node::Constant->new(value => 42, type => 'Integer');
    my $const2 = Chalk::IR::Node::Constant->new(value => 99, type => 'Integer');

    $graph->add_node($const1);
    $graph->add_node($const2);

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->apply($graph);

    # Should complete without hanging and preserve the constants
    is($result->node_count, 2, 'Graph with no optimizations converges immediately');
};

# Test 6: Pipeline compatibility
subtest 'Pipeline compatibility' => sub {
    use_ok('Chalk::IR::OptimizerPipeline');

    my $graph = Chalk::IR::Graph->new();
    my $const = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    $graph->add_node($const);

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $pipeline = Chalk::IR::OptimizerPipeline->new(optimizers => [$iterpeeps]);

    my $result = $pipeline->apply($graph);
    ok(defined($result), 'IterPeeps works in pipeline');
    is($result->node_count, 1, 'Graph preserved through pipeline');
};

# Test 7: Metrics tracking
subtest 'Metrics tracking' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build: 1 + 2
    my $const1 = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $const2 = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $add = Chalk::IR::Node::Add->new(left => $const1, right => $const2);

    $graph->add_node($const1);
    $graph->add_node($const2);
    $graph->add_node($add);

    my $iterpeeps = Chalk::IR::Optimizer::IterPeeps->new();
    my $result = $iterpeeps->run_iterpeeps($graph);

    ok(exists($result->{metrics}), 'Metrics returned');
    ok(exists($result->{metrics}{iterations}), 'Iteration count tracked');
    ok(exists($result->{metrics}{peepholes_applied}), 'Peepholes applied tracked');
    ok($result->{metrics}{peepholes_applied} >= 1, 'At least one peephole applied');
};

done_testing();
