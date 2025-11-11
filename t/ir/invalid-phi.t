# ABOUTME: Negative test cases for phi node validation - prepares for Chapter 5 if statement implementation
# ABOUTME: Tests various invalid phi node placements and configurations to ensure validator catches errors

use v5.42;
use Test::More;
use Test::Deep;
use lib 'lib';

use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Validator');

# Test: Phi node at non-merge point (no Region)
subtest 'Phi node without Region control' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create constant node for the Phi alternative
    my $const1 = Chalk::IR::Node->new(
        id => 'const_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const1);

    # Invalid: Phi directly connected to Start (not a Region)
    my $phi = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Phi',
        inputs => ['node_0', 'const_1'],
        attributes => {
            region_id => 'node_0',
            variable => '$x',
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
    my ($success, $errors) = $validator->validate_all($graph);

    ok(!$success, 'Invalid phi placement fails validation');
    my $phi_errors = grep { /Phi.*Region|not at a Region/i } @$errors;
    ok($phi_errors > 0, 'Phi validation error found');
};

# Test: Phi with too many alternatives
subtest 'Phi node with excess alternatives' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Region with 2 predecessors (binary merge)
    my $region = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Region',
        inputs => ['node_0', 'node_0'],
        attributes => {}
    );
    $graph->add_node($region);

    # Create constant nodes for the Phi alternatives
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

    # Invalid: Phi with 3 alternatives but Region has only 2 predecessors
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1', 'const_1', 'const_2', 'const_3'],  # Extra!
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
    my ($success, $errors) = $validator->validate_all($graph);

    ok(!$success, 'Phi with wrong alternative count fails validation');
    my $phi_errors = grep { /expects 2.*has 3/i } @$errors;
    ok($phi_errors > 0, 'Phi arity mismatch error found');
};

# Test: Phi with too few alternatives
subtest 'Phi node with insufficient alternatives' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Region with 3 predecessors (ternary merge)
    my $region = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Region',
        inputs => ['node_0', 'node_0', 'node_0'],
        attributes => {}
    );
    $graph->add_node($region);

    # Create constant nodes for the Phi alternatives
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

    # Invalid: Phi with 2 alternatives but Region has 3 predecessors
    # Missing third alternative!
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1', 'const_1', 'const_2'],
        attributes => {
            region_id => 'node_1',
            variable => '$result',
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
    my ($success, $errors) = $validator->validate_all($graph);

    ok(!$success, 'Phi with too few alternatives fails validation');
    my $phi_errors = grep { /expects 3.*has 2/i } @$errors;
    ok($phi_errors > 0, 'Phi arity mismatch error found (too few)');
};

# Test: Phi referencing non-existent Region
subtest 'Phi node references non-existent Region' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create constant node for the Phi alternative
    my $const1 = Chalk::IR::Node->new(
        id => 'const_1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const1);

    # Invalid: Phi references node_999 which doesn't exist
    my $phi = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Phi',
        inputs => ['node_999', 'const_1'],  # Non-existent!
        attributes => {
            region_id => 'node_999',
            variable => '$x',
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
    my ($success, $errors) = $validator->validate_all($graph);

    ok(!$success, 'Phi with non-existent Region fails validation');
    my $phi_errors = grep { /non-existent.*node_999/i } @$errors;
    ok($phi_errors > 0, 'Error mentions non-existent Region');
};

# Test: Phi with no control input
subtest 'Phi node with empty inputs' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Invalid: Phi with no control input at all
    my $phi = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Phi',
        inputs => [],  # No control input!
        attributes => {
            variable => '$x',
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
    my ($success, $errors) = $validator->validate_all($graph);

    ok(!$success, 'Phi with no control input fails validation');
    my $phi_errors = grep { /no control input/i } @$errors;
    ok($phi_errors > 0, 'Error mentions missing control input');
};

# Test: Valid phi node (baseline for comparison)
subtest 'Valid phi node passes validation' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Valid Region with 2 predecessors
    my $region = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Region',
        inputs => ['node_0', 'node_0'],
        attributes => {}
    );
    $graph->add_node($region);

    # Create constant nodes for the Phi alternatives
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

    # Valid: Phi with correct number of alternatives
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1', 'const_1', 'const_2'],
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
    my ($success, $errors) = $validator->validate_all($graph);

    ok($success, 'Valid phi node passes all validation');
    is(scalar(@$errors), 0, 'No validation errors');
};

# Test: Multiple phi nodes at same Region
subtest 'Multiple phi nodes at same Region' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $region = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Region',
        inputs => ['node_0', 'node_0'],
        attributes => {}
    );
    $graph->add_node($region);

    # Create constant nodes for the first Phi ($x)
    my $const_x1 = Chalk::IR::Node->new(
        id => 'const_x1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const_x1);

    my $const_x2 = Chalk::IR::Node->new(
        id => 'const_x2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 20, type => 'Int' }
    );
    $graph->add_node($const_x2);

    # First phi: $x
    my $phi_x = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1', 'const_x1', 'const_x2'],
        attributes => {
            region_id => 'node_1',
            variable => '$x',
        }
    );
    $graph->add_node($phi_x);

    # Create constant nodes for the second Phi ($y)
    my $const_y1 = Chalk::IR::Node->new(
        id => 'const_y1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 100, type => 'Int' }
    );
    $graph->add_node($const_y1);

    my $const_y2 = Chalk::IR::Node->new(
        id => 'const_y2',
        op => 'Constant',
        inputs => [],
        attributes => { value => 200, type => 'Int' }
    );
    $graph->add_node($const_y2);

    # Second phi: $y (both valid)
    my $phi_y = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Phi',
        inputs => ['node_1', 'const_y1', 'const_y2'],
        attributes => {
            region_id => 'node_1',
            variable => '$y',
        }
    );
    $graph->add_node($phi_y);

    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    );
    $graph->add_node($return);

    my $validator = Chalk::IR::Validator->new();
    my ($success, $errors) = $validator->validate_all($graph);

    ok($success, 'Multiple valid phi nodes at same Region pass validation');
    is(scalar(@$errors), 0, 'No validation errors for multiple phis');
};

done_testing();
