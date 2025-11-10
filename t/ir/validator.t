# ABOUTME: Test suite for IR graph validator - validates SSA form, CFG structure, dominance, and phi nodes
# ABOUTME: Ensures IR graphs maintain correctness properties required for Sea of Nodes compilation

use v5.42;
use Test::More;
use Test::Deep;
use lib 'lib';

# Test that we can load the required modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Validator');

# Helper: Create simple valid graph (Chapter 1 style: return constant)
sub make_valid_simple_graph {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $constant = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($constant);

    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    );
    $graph->add_node($return);

    return $graph;
}

# Helper: Create graph with Store/Load for SSA validation (Chapter 3 style)
sub make_graph_with_variable {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Store: $x = 10
    my $const10 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const10);

    my $store = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            variable => '$x',
            value => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($store);

    # Load: return $x
    my $load = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Load',
        inputs => ['node_0'],
        attributes => {
            variable => '$x',
            store_id => 'node_2'
        }
    );
    $graph->add_node($load);

    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_0', 'node_3'],
        attributes => {}
    );
    $graph->add_node($return);

    return $graph;
}

# Test validate_all on valid graph
subtest 'validate_all on valid simple graph' => sub {
    my $graph = make_valid_simple_graph();
    my $validator = Chalk::IR::Validator->new();

    my ($success, $errors) = $validator->validate_all($graph);

    ok($success, 'Simple valid graph passes all validation');
    is(scalar(@$errors), 0, 'No errors reported');
};

# Test validate_cfg - CFG structure validation
subtest 'validate_cfg on valid graph' => sub {
    my $graph = make_valid_simple_graph();
    my $validator = Chalk::IR::Validator->new();

    my @errors = $validator->validate_cfg($graph);

    is(scalar(@errors), 0, 'Valid graph has no CFG errors');
};

subtest 'validate_cfg detects missing Start node' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Only add Return node, no Start
    my $return = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Return',
        inputs => [],
        attributes => {}
    );
    $graph->add_node($return);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_cfg($graph);

    ok(scalar(@errors) > 0, 'Missing Start node produces errors');
    like($errors[0], qr/Start node/i, 'Error mentions Start node');
};

subtest 'validate_cfg detects missing Return node' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Only add Start node, no Return
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_cfg($graph);

    ok(scalar(@errors) > 0, 'Missing Return node produces errors');
    like($errors[0], qr/Return node/i, 'Error mentions Return node');
};

subtest 'validate_cfg detects unreachable nodes' => sub {
    my $graph = make_valid_simple_graph();

    # Add an isolated node not connected to Start
    # Note: Constants are exempt from reachability checks, so use a different op
    my $orphan = Chalk::IR::Node->new(
        id => 'node_999',
        op => 'Add',  # Use non-Constant op to test reachability
        inputs => [],  # No connection to Start
        attributes => { left => {value => 1}, right => {value => 2} }
    );
    $graph->add_node($orphan);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_cfg($graph);

    ok(scalar(@errors) > 0, 'Unreachable node produces errors');
    like($errors[0], qr/unreachable|not reachable/i, 'Error mentions unreachability');
    like($errors[0], qr/node_999/, 'Error identifies the orphan node');
};

# Test validate_single_assignment - SSA form validation
subtest 'validate_single_assignment on valid graph' => sub {
    my $graph = make_graph_with_variable();
    my $validator = Chalk::IR::Validator->new();

    my @errors = $validator->validate_single_assignment($graph);

    is(scalar(@errors), 0, 'Valid SSA form has no errors');
};

subtest 'validate_single_assignment detects multiple assignments' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # First assignment: $x = 10
    my $store1 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            variable => '$x',
            value => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($store1);

    # Second assignment: $x = 20 (violates SSA!)
    my $store2 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            variable => '$x',
            value => { op => 'Constant', value => 20, type => 'Int' }
        }
    );
    $graph->add_node($store2);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_single_assignment($graph);

    ok(scalar(@errors) > 0, 'Multiple assignments detected');
    like($errors[0], qr/\$x/, 'Error mentions variable name');
    like($errors[0], qr/multiple|twice|assigned more than once/i, 'Error mentions multiple assignment');
};

# Test validate_dominance - dominance validation
subtest 'validate_dominance on valid graph' => sub {
    my $graph = make_graph_with_variable();
    my $validator = Chalk::IR::Validator->new();

    my @errors = $validator->validate_dominance($graph);

    is(scalar(@errors), 0, 'Valid dominance relationships have no errors');
};

subtest 'validate_dominance detects use before definition' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create a simple control flow with Region to enable dominance checking
    my $region = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Region',
        inputs => ['node_0', 'node_0'],  # Simple merge
        attributes => {}
    );
    $graph->add_node($region);

    # Load $x before it's stored (violates dominance in control flow!)
    my $load = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_1'],
        attributes => {
            variable => '$x',
            store_id => 'node_3'  # References Store
        }
    );
    $graph->add_node($load);

    # Store comes "after" Load (wrong control flow order)
    my $store = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Store',
        inputs => ['node_1'],  # Same control point - doesn't dominate Load
        attributes => {
            variable => '$x',
            value => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($store);

    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    );
    $graph->add_node($return);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_dominance($graph);

    ok(scalar(@errors) > 0, 'Use before definition detected');
    like($errors[0], qr/\$x/, 'Error mentions variable name');
    like($errors[0], qr/dominance|definition|before/i, 'Error mentions dominance violation');
};

# Test validate_phi_placement - phi node validation (prepare for Chapter 5)
subtest 'validate_phi_placement on graph without phis' => sub {
    my $graph = make_valid_simple_graph();
    my $validator = Chalk::IR::Validator->new();

    my @errors = $validator->validate_phi_placement($graph);

    is(scalar(@errors), 0, 'Graph without phis has no phi placement errors');
};

subtest 'validate_phi_placement detects phi at non-merge point' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Phi node NOT at a Region (merge point) - invalid!
    my $phi = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Phi',
        inputs => ['node_0'],  # Only one input, not a merge
        attributes => {
            variable => '$x',
            alternatives => [
                { op => 'Constant', value => 10, type => 'Int' }
            ]
        }
    );
    $graph->add_node($phi);

    my $return = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Return',
        inputs => ['node_0', 'node_1'],
        attributes => {}
    );
    $graph->add_node($return);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_phi_placement($graph);

    ok(scalar(@errors) > 0, 'Phi at non-merge point detected');
    like($errors[0], qr/Phi|merge|Region/i, 'Error mentions phi/merge/region');
};

subtest 'validate_phi_placement detects wrong number of inputs' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Region with 2 predecessors
    my $region = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Region',
        inputs => ['node_0', 'node_0'],  # 2 control inputs
        attributes => {}
    );
    $graph->add_node($region);

    # Create constant nodes to reference
    my $const1 = Chalk::IR::Node->new(
        id => 'const_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const1);

    my $const2 = Chalk::IR::Node->new(
        id => 'const_2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 20, type => 'Int' }
    );
    $graph->add_node($const2);

    my $const3 = Chalk::IR::Node->new(
        id => 'const_3',
        op => 'Constant',
        inputs => [],
        attributes => { value => 30, type => 'Int' }
    );
    $graph->add_node($const3);

    # Phi with wrong number of alternatives (3 instead of 2)
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1', 'const_1', 'const_2', 'const_3'],  # 3 alternatives but Region has only 2 inputs!
        attributes => {
            region_id => 'node_1',
            variable => '$x',
        }
    );
    $graph->add_node($phi);

    my $return = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    );
    $graph->add_node($return);

    my $validator = Chalk::IR::Validator->new();
    my @errors = $validator->validate_phi_placement($graph);

    ok(scalar(@errors) > 0, 'Wrong number of phi inputs detected');
    like($errors[0], qr/2.*3|expects 2.*has 3/i, 'Error mentions mismatch (2 vs 3)');
};

# Test compute_dominance_tree
subtest 'compute_dominance_tree on simple graph' => sub {
    my $graph = make_valid_simple_graph();
    my $validator = Chalk::IR::Validator->new();

    my $dom_tree = $validator->compute_dominance_tree($graph);

    ok($dom_tree, 'Dominance tree computed');
    is(ref($dom_tree), 'HASH', 'Dominance tree is a hash');

    # Start dominates itself
    ok(exists($dom_tree->{node_0}), 'Start node in dominance tree');

    # All nodes should be dominated by Start
    ok(exists($dom_tree->{node_1}), 'Constant in dominance tree');
    ok(exists($dom_tree->{node_2}), 'Return in dominance tree');
};

done_testing();
