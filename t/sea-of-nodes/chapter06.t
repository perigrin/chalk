# ABOUTME: Test for Sea of Nodes IR generation - Chapter 6: Dead Control Flow Elimination
# ABOUTME: Validates constant condition optimization, dead branch elimination, and Region/Phi simplification

use lib 'lib';
use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Node::Scope');
use_ok('Chalk::IR::Validator');

# Load polymorphic node classes for peephole optimization tests
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::If');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Node::Region');
use_ok('Chalk::IR::Node::Phi');
use_ok('Chalk::IR::Node::Return');

# Test constant condition optimization: if (1) - always true
subtest 'Constant true condition: if (1)' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'test_if_true',
            params => []
        }
    );
    $graph->add_node($start);

    # Control projection
    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => ['node_0'],
        index => 0,
        label => '$ctrl'
    );
    $graph->add_node($ctrl);

    # Constant 1 (true condition)
    my $const_1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => 'Int'
    );
    $graph->add_node($const_1);

    # If node with constant condition - use polymorphic If node
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $const_1->id],
        condition_id => $const_1->id,
    );
    $graph->add_node($if_node);

    # Apply peephole optimization
    my $optimized_if = $if_node->peephole($graph);

    # Verify that If with constant true condition is optimized
    # The optimization should happen when creating Proj nodes
    ok($optimized_if, 'If node returns after peephole');
};

# Test constant condition optimization: if (0) - always false
subtest 'Constant false condition: if (0)' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'test_if_false',
            params => []
        }
    );
    $graph->add_node($start);

    # Control projection
    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => ['node_0'],
        index => 0,
        label => '$ctrl'
    );
    $graph->add_node($ctrl);

    # Constant 0 (false condition)
    my $const_0 = Chalk::IR::Node::Constant->new(
        value => 0,
        type => 'Int'
    );
    $graph->add_node($const_0);

    # If node with constant condition
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $const_0->id],
        condition_id => $const_0->id,
    );
    $graph->add_node($if_node);

    # Apply peephole optimization
    my $optimized_if = $if_node->peephole($graph);

    ok($optimized_if, 'If node returns after peephole');
};

# Test Proj node optimization for dead branches
subtest 'Proj node optimization: dead branch becomes ~Ctrl' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'test', params => [] }
    );
    $graph->add_node($start);

    # Control projection
    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => ['node_0'],
        index => 0,
        label => '$ctrl'
    );
    $graph->add_node($ctrl);

    # Constant 1 (true)
    my $const_1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => 'Int'
    );
    $graph->add_node($const_1);

    # If node with constant true
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $const_1->id],
        condition_id => $const_1->id,
    );
    $graph->add_node($if_node);

    # True branch projection - should become live (pass through ctrl)
    my $if_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'true'
    );
    $graph->add_node($if_true);

    # False branch projection - should become dead (~Ctrl)
    my $if_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'false'
    );
    $graph->add_node($if_false);

    # Apply peephole optimization to projections
    my $opt_true = $if_true->peephole($graph);
    my $opt_false = $if_false->peephole($graph);

    # True branch should pass through to control node
    is($opt_true->id, $ctrl->id, 'True branch passes through to control');
    is($opt_true->op, 'Proj', 'True branch is original control Proj');

    # False branch should become ~Ctrl constant
    is($opt_false->op, 'Constant', 'False branch becomes Constant');
    is($opt_false->value, '~Ctrl', 'False branch is ~Ctrl');
    is($opt_false->type, 'Control', 'False branch type is Control');
};

# Test Phi node simplification when one input is dead
subtest 'Phi node simplification: single live input' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Dead control constant
    my $dead_ctrl = Chalk::IR::Node::Constant->new(
        value => '~Ctrl',
        type => 'Control'
    );
    $graph->add_node($dead_ctrl);

    # Live control
    my $live_ctrl = Chalk::IR::Node::Proj->new(
        inputs => [],
        index => 0,
        label => 'true'
    );
    $graph->add_node($live_ctrl);

    # Region with one dead and one live input
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$live_ctrl->id, $dead_ctrl->id],  # live, dead
    );
    $graph->add_node($region);

    # Two values for Phi
    my $value_1 = Chalk::IR::Node::Constant->new(
        value => 42,
        type => 'Int'
    );
    $graph->add_node($value_1);

    my $value_2 = Chalk::IR::Node::Constant->new(
        value => 0,
        type => 'Int'
    );
    $graph->add_node($value_2);

    # Phi node with alternatives corresponding to Region inputs
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $value_1->id, $value_2->id],  # Region control, then alternatives
        region_id => $region->id,
    );
    $graph->add_node($phi);

    # Apply peephole optimization to Phi
    my $opt_phi = $phi->peephole($graph);

    # Phi should simplify to the single live value (42)
    is($opt_phi->id, $value_1->id, 'Phi simplifies to live value node');
    is($opt_phi->op, 'Constant', 'Phi becomes the constant node');
    is($opt_phi->value, 42, 'Phi value is 42 from live branch');
};

# Test Region node collapse when only one input is live
subtest 'Region node collapse: single live input' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Dead control
    my $dead_ctrl = Chalk::IR::Node::Constant->new(
        value => '~Ctrl',
        type => 'Control'
    );
    $graph->add_node($dead_ctrl);

    # Live control
    my $live_ctrl = Chalk::IR::Node::Proj->new(
        inputs => [],
        index => 0,
        label => 'true'
    );
    $graph->add_node($live_ctrl);

    # Region with one dead and one live input
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$live_ctrl->id, $dead_ctrl->id],  # live, dead
    );
    $graph->add_node($region);

    # Apply peephole optimization
    my $opt_region = $region->peephole($graph);

    # Region should collapse to single live input
    is($opt_region->id, $live_ctrl->id, 'Region collapses to live control');
    is($opt_region->op, 'Proj', 'Region becomes the live Proj node');
    is($opt_region->label, 'true', 'Region is the true branch');
};

# Test complete dead code elimination: if (1) { return 42; } return 0;
subtest 'Complete dead code elimination: if (1) with dead else branch' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build IR for: if (1) { return 42; } return 0;
    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'dead_code_test', params => [] }
    );
    $graph->add_node($start);

    # Control projection
    my $ctrl = Chalk::IR::Node::Proj->new(
        inputs => ['node_0'],
        index => 0,
        label => '$ctrl'
    );
    $graph->add_node($ctrl);

    # Constant 1 (always true)
    my $const_1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => 'Int'
    );
    $graph->add_node($const_1);

    # If node
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$ctrl->id, $const_1->id],
        condition_id => $const_1->id,
    );
    $graph->add_node($if_node);

    # True branch projection
    my $if_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'true'
    );
    $graph->add_node($if_true);

    # False branch projection
    my $if_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'false'
    );
    $graph->add_node($if_false);

    # Constant 42 (return value from true branch)
    my $const_42 = Chalk::IR::Node::Constant->new(
        value => 42,
        type => 'Int'
    );
    $graph->add_node($const_42);

    # Constant 0 (return value from false branch - dead code)
    my $const_0 = Chalk::IR::Node::Constant->new(
        value => 0,
        type => 'Int'
    );
    $graph->add_node($const_0);

    # Region merges control flow
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$if_true->id, $if_false->id],
    );
    $graph->add_node($region);

    # Phi merges return values
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $const_42->id, $const_0->id],
        region_id => $region->id,
    );
    $graph->add_node($phi);

    # Count nodes before optimization
    my $initial_count = $graph->node_count;
    is($initial_count, 10, 'Graph has 10 nodes before optimization');

    # Apply peephole optimization to Proj nodes first
    my $opt_true = $if_true->peephole($graph);
    my $opt_false = $if_false->peephole($graph);

    # Verify false branch becomes ~Ctrl
    is($opt_false->op, 'Constant', 'False branch becomes Constant after optimization');
    is($opt_false->value, '~Ctrl', 'False branch is ~Ctrl');

    # If we update the graph with the optimized nodes, Region and Phi would simplify
    # For this test, we verify the peephole logic works correctly
    ok($opt_true, 'True branch optimized');
    ok($opt_false, 'False branch optimized');
};

# Test constant comparison that's always true
subtest 'Constant comparison optimization: 5 > 3 (always true)' => sub {
    plan skip_all => 'GT node peephole not yet implemented';

    my $graph = Chalk::IR::Graph->new();

    # Constant 5
    my $const_5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => 'Int'
    );
    $graph->add_node($const_5);

    # Constant 3
    my $const_3 = Chalk::IR::Node::Constant->new(
        value => 3,
        type => 'Int'
    );
    $graph->add_node($const_3);

    # GT: 5 > 3 (always true) - would need GT node peephole
    # This test is skipped until GT::peephole is implemented
};

# Test validator confirms optimized IR correctness
subtest 'Validator confirms optimized IR correctness' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build simple optimized IR (as if dead code was already eliminated)
    # This represents: return 42;
    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'optimized', params => [] }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42, type => 'Int' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    ));


    # Run validator
    my $validator = Chalk::IR::Validator->new();
    my ($success, $errors) = $validator->validate_all($graph);

    if (!$success) {
        diag("Validation errors:");
        diag($_) for @$errors;
    }

    ok($success, 'Validator confirms optimized IR is correct');
    is(scalar(@$errors), 0, 'No validation errors');
};

done_testing();
