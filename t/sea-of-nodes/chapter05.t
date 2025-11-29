# ABOUTME: Test for Sea of Nodes IR generation - Chapter 5: If Statements with Phi Nodes
# ABOUTME: Validates If, Region, Phi nodes, comparison operators, and control flow merging with validator

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Node::Scope');
use_ok('Chalk::IR::Validator');

# Test If node with true/false branches
subtest 'If node with control and condition' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'test_if',
            params => ['$x']
        }
    );
    $graph->add_node($start);

    # Control projection
    my $ctrl = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    );
    $graph->add_node($ctrl);

    # Parameter projection
    my $x = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$x' }
    );
    $graph->add_node($x);

    # Constant 0 for comparison
    my $const_0 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0, type => 'Int' }
    );
    $graph->add_node($const_0);

    # GT comparison: $x > 0
    my $gt = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'GT',
        inputs => ['node_1', 'node_2', 'node_3'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_3' }
        }
    );
    $graph->add_node($gt);

    # If node: branches on condition
    my $if_node = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'If',
        inputs => ['node_1', 'node_4'],  # control and condition
        attributes => {}
    );
    $graph->add_node($if_node);

    # True branch projection
    my $if_true = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Proj',
        inputs => ['node_5'],
        attributes => { index => 0, label => 'true' }
    );
    $graph->add_node($if_true);

    # False branch projection
    my $if_false = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'Proj',
        inputs => ['node_5'],
        attributes => { index => 1, label => 'false' }
    );
    $graph->add_node($if_false);

    # Verify If node structure
    my $if_check = $graph->get_node('node_5');
    ok($if_check, 'If node exists');
    is($if_check->op, 'If', 'Node op is If');
    cmp_deeply($if_check->inputs, ['node_1', 'node_4'], 'If has control and condition inputs');

    # Verify projections
    my $true_proj = $graph->get_node('node_6');
    is($true_proj->op, 'Proj', 'True branch is Proj');
    is($true_proj->attributes->{index}, 0, 'True branch has index 0');
    is($true_proj->attributes->{label}, 'true', 'True branch labeled');

    my $false_proj = $graph->get_node('node_7');
    is($false_proj->op, 'Proj', 'False branch is Proj');
    is($false_proj->attributes->{index}, 1, 'False branch has index 1');
    is($false_proj->attributes->{label}, 'false', 'False branch labeled');
};

# Test comparison operators
subtest 'Comparison operators (GT, LT, EQ, NE, LE, GE)' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create constants for comparison
    my $const_5 = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 5, type => 'Int' }
    );
    $graph->add_node($const_5);

    my $const_10 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const_10);

    # GT: 10 > 5 (true)
    my $gt = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'GT',
        inputs => ['node_1', 'node_0'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_0' }
        }
    );
    $graph->add_node($gt);

    # LT: 5 < 10 (true)
    my $lt = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'LT',
        inputs => ['node_0', 'node_1'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_0' },
            right => { op => 'NodeRef', node_id => 'node_1' }
        }
    );
    $graph->add_node($lt);

    # EQ: 5 == 5 (true)
    my $eq = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'EQ',
        inputs => ['node_0', 'node_0'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_0' },
            right => { op => 'NodeRef', node_id => 'node_0' }
        }
    );
    $graph->add_node($eq);

    # NE: 5 != 10 (true)
    my $ne = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'NE',
        inputs => ['node_0', 'node_1'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_0' },
            right => { op => 'NodeRef', node_id => 'node_1' }
        }
    );
    $graph->add_node($ne);

    # LE: 5 <= 10 (true)
    my $le = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'LE',
        inputs => ['node_0', 'node_1'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_0' },
            right => { op => 'NodeRef', node_id => 'node_1' }
        }
    );
    $graph->add_node($le);

    # GE: 10 >= 5 (true)
    my $ge = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'GE',
        inputs => ['node_1', 'node_0'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_1' },
            right => { op => 'NodeRef', node_id => 'node_0' }
        }
    );
    $graph->add_node($ge);

    # Verify all operators exist
    is($graph->get_node('node_2')->op, 'GT', 'GT operator exists');
    is($graph->get_node('node_3')->op, 'LT', 'LT operator exists');
    is($graph->get_node('node_4')->op, 'EQ', 'EQ operator exists');
    is($graph->get_node('node_5')->op, 'NE', 'NE operator exists');
    is($graph->get_node('node_6')->op, 'LE', 'LE operator exists');
    is($graph->get_node('node_7')->op, 'GE', 'GE operator exists');
};

# Test Region node merging control flow
subtest 'Region node merges control flow' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create two control paths (from If true/false branches)
    my $ctrl_true = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Proj',
        inputs => [],
        attributes => { index => 0, label => 'true' }
    );
    $graph->add_node($ctrl_true);

    my $ctrl_false = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => [],
        attributes => { index => 1, label => 'false' }
    );
    $graph->add_node($ctrl_false);

    # Region merges both control paths
    my $region = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Region',
        inputs => ['node_0', 'node_1'],  # Two control predecessors
        attributes => {}
    );
    $graph->add_node($region);

    # Verify Region structure
    my $region_node = $graph->get_node('node_2');
    ok($region_node, 'Region node exists');
    is($region_node->op, 'Region', 'Node op is Region');
    cmp_deeply($region_node->inputs, ['node_0', 'node_1'], 'Region has two control inputs');
};

# Test Phi node merging values from different paths
subtest 'Phi node merges values from control paths' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Region (merge point)
    my $region = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Region',
        inputs => ['node_ctrl_true', 'node_ctrl_false'],
        attributes => {}
    );
    $graph->add_node($region);

    # Constants from each branch
    my $const_1 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 1, type => 'Int' }
    );
    $graph->add_node($const_1);

    my $const_0 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0, type => 'Int' }
    );
    $graph->add_node($const_0);

    # Phi node merges values
    my $phi = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Phi',
        inputs => ['node_0', 'node_1', 'node_2'],  # Region control, then alternatives
        attributes => {
            region_id => 'node_0',
        }
    );
    $graph->add_node($phi);

    # Verify Phi structure
    my $phi_node = $graph->get_node('node_3');
    ok($phi_node, 'Phi node exists');
    is($phi_node->op, 'Phi', 'Node op is Phi');
    cmp_deeply($phi_node->inputs, ['node_0', 'node_1', 'node_2'], 'Phi has Region as control input plus two alternatives');
    is($phi_node->attributes->{region_id}, 'node_0', 'Phi references Region');
    is(scalar($phi_node->inputs->@*) - 1, 2, 'Phi has two alternatives (from inputs array)');
};

# Test complete if-then-else with phi node
subtest 'Complete if-then-else: classify($x) with phi merge' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'classify',
            params => ['$x']
        }
    );
    $graph->add_node($start);

    # Control projection
    my $ctrl = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    );
    $graph->add_node($ctrl);

    # Parameter projection
    my $x = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$x' }
    );
    $graph->add_node($x);

    # Constant 0 for comparison
    my $const_0 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0, type => 'Int' }
    );
    $graph->add_node($const_0);

    # GT comparison: $x > 0
    my $gt = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'GT',
        inputs => ['node_1', 'node_2', 'node_3'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_3' }
        }
    );
    $graph->add_node($gt);

    # If node
    my $if_node = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'If',
        inputs => ['node_1', 'node_4'],
        attributes => {}
    );
    $graph->add_node($if_node);

    # True branch projection
    my $if_true = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Proj',
        inputs => ['node_5'],
        attributes => { index => 0, label => 'true' }
    );
    $graph->add_node($if_true);

    # False branch projection
    my $if_false = Chalk::IR::Node->new(
        id => 'node_7',
        op => 'Proj',
        inputs => ['node_5'],
        attributes => { index => 1, label => 'false' }
    );
    $graph->add_node($if_false);

    # Constants for return values
    my $const_1 = Chalk::IR::Node->new(
        id => 'node_8',
        op => 'Constant',
        inputs => [],
        attributes => { value => 1, type => 'Int' }
    );
    $graph->add_node($const_1);

    # Region merges control flow
    my $region = Chalk::IR::Node->new(
        id => 'node_9',
        op => 'Region',
        inputs => ['node_6', 'node_7'],  # true and false branches
        attributes => {}
    );
    $graph->add_node($region);

    # Phi merges return values (1 from true branch, 0 from false branch)
    my $phi = Chalk::IR::Node->new(
        id => 'node_10',
        op => 'Phi',
        inputs => ['node_9', 'node_8', 'node_3'],  # Region control, then alternatives
        attributes => {
            region_id => 'node_9',
        }
    );
    $graph->add_node($phi);

    # Return node uses merged control and phi value
    my $return = Chalk::IR::Node->new(
        id => 'node_11',
        op => 'Return',
        inputs => ['node_9', 'node_10'],
        attributes => {}
    );
    $graph->add_node($return);

    # Materialize pending nodes
    $graph->materialize_pending_nodes();

    # Verify graph structure
    is($graph->node_count, 12, 'Graph has 12 nodes');

    # Verify If/Region/Phi relationship
    my $if_check = $graph->get_node('node_5');
    is($if_check->op, 'If', 'If node exists');

    my $region_check = $graph->get_node('node_9');
    is($region_check->op, 'Region', 'Region merges branches');
    cmp_deeply($region_check->inputs, ['node_6', 'node_7'], 'Region merges If branches');

    my $phi_check = $graph->get_node('node_10');
    is($phi_check->op, 'Phi', 'Phi merges values');
    is($phi_check->attributes->{region_id}, 'node_9', 'Phi at Region');
    is(scalar($phi_check->inputs->@*) - 1, 2, 'Phi has two alternatives (from inputs array)');

    my $ret_check = $graph->get_node('node_11');
    cmp_deeply($ret_check->inputs, ['node_9', 'node_10'], 'Return uses Region control and Phi value');
};

# Test validator on control flow IR
subtest 'Validator confirms Chapter 5 IR correctness' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build valid if-then-else IR
    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'classify', params => ['$x'] }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$x' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0, type => 'Int' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_4',
        op => 'GT',
        inputs => ['node_1', 'node_2', 'node_3'],  # control, left operand, right operand
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_3' }
        }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_5',
        op => 'If',
        inputs => ['node_1', 'node_4'],
        attributes => {}
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Proj',
        inputs => ['node_5'],
        attributes => { index => 0, label => 'true' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_7',
        op => 'Proj',
        inputs => ['node_5'],
        attributes => { index => 1, label => 'false' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_8',
        op => 'Constant',
        inputs => [],
        attributes => { value => 1, type => 'Int' }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_9',
        op => 'Region',
        inputs => ['node_6', 'node_7'],
        attributes => {}
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_10',
        op => 'Phi',
        inputs => ['node_9', 'node_8', 'node_3'],  # region, value from true branch, value from false branch
        attributes => {
            region_id => 'node_9',
        }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_11',
        op => 'Return',
        inputs => ['node_9', 'node_10'],
        attributes => {}
    ));

    # Materialize pending nodes
    $graph->materialize_pending_nodes();

    # Run validator
    my $validator = Chalk::IR::Validator->new();
    my ($success, $errors) = $validator->validate_all($graph);

    if (!$success) {
        diag("Validation errors:");
        diag($_) for @$errors;
    }

    ok($success, 'Validator confirms IR is correct');
    is(scalar(@$errors), 0, 'No validation errors');
};

# Test JSON serialization with control flow
subtest 'JSON serialization with If/Region/Phi' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Build simple if-then-else
    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'test', params => [] }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_1',
        op => 'If',
        inputs => [],
        attributes => {}
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Region',
        inputs => [],
        attributes => {}
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Phi',
        inputs => ['node_2'],  # Region control with no alternatives (empty region)
        attributes => {
            region_id => 'node_2',
        }
    ));

    $graph->add_node(Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_2', 'node_3'],
        attributes => {}
    ));

    # Materialize pending nodes
    $graph->materialize_pending_nodes();

    # Serialize to JSON
    my $json = $graph->to_json();
    ok($json, 'Graph serializes to JSON');
    is(scalar(@{$json->{nodes}}), 5, 'JSON has 5 nodes');

    # Find nodes
    my %json_nodes = map { $_->{id} => $_ } @{$json->{nodes}};

    # Verify control flow nodes in JSON
    ok(exists $json_nodes{'node_1'}, 'If node in JSON');
    is($json_nodes{'node_1'}{op}, 'If', 'If op in JSON');

    ok(exists $json_nodes{'node_2'}, 'Region node in JSON');
    is($json_nodes{'node_2'}{op}, 'Region', 'Region op in JSON');

    ok(exists $json_nodes{'node_3'}, 'Phi node in JSON');
    is($json_nodes{'node_3'}{op}, 'Phi', 'Phi op in JSON');
    is($json_nodes{'node_3'}{attributes}{region_id}, 'node_2', 'Phi region_id in JSON');
};

done_testing();
