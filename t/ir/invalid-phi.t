# ABOUTME: Negative test cases for phi node validation - prepares for Chapter 5 if statement implementation
# ABOUTME: Tests various invalid phi node placements and configurations to ensure validator catches errors

use v5.42;
use Test::More;
use Test::Deep;

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

    # Invalid: Phi directly connected to Start (not a Region)
    my $phi = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Phi',
        inputs => ['node_0'],
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

    # Invalid: Phi with 3 alternatives but Region has only 2 predecessors
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1'],
        attributes => {
            variable => '$x',
            alternatives => [
                { op => 'Constant', value => 10, type => 'Int' },
                { op => 'Constant', value => 20, type => 'Int' },
                { op => 'Constant', value => 30, type => 'Int' }  # Extra!
            ]
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

    # Invalid: Phi with 2 alternatives but Region has 3 predecessors
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1'],
        attributes => {
            variable => '$result',
            alternatives => [
                { op => 'Constant', value => 10, type => 'Int' },
                { op => 'Constant', value => 20, type => 'Int' }
                # Missing third alternative!
            ]
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

    # Invalid: Phi references node_999 which doesn't exist
    my $phi = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Phi',
        inputs => ['node_999'],  # Non-existent!
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

    # Valid: Phi with correct number of alternatives
    my $phi = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1'],
        attributes => {
            variable => '$x',
            alternatives => [
                { op => 'Constant', value => 10, type => 'Int' },
                { op => 'Constant', value => 20, type => 'Int' }
            ]
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

    # First phi: $x
    my $phi_x = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Phi',
        inputs => ['node_1'],
        attributes => {
            variable => '$x',
            alternatives => [
                { op => 'Constant', value => 10, type => 'Int' },
                { op => 'Constant', value => 20, type => 'Int' }
            ]
        }
    );
    $graph->add_node($phi_x);

    # Second phi: $y (both valid)
    my $phi_y = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Phi',
        inputs => ['node_1'],
        attributes => {
            variable => '$y',
            alternatives => [
                { op => 'Constant', value => 100, type => 'Int' },
                { op => 'Constant', value => 200, type => 'Int' }
            ]
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
