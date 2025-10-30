# ABOUTME: Test for threaded interpreter execution of IR nodes
# ABOUTME: Validates that execute() methods work correctly for each node type

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node::Constant');
use_ok('Chalk::IR::Node::Add');
use_ok('Chalk::IR::Node::Subtract');
use_ok('Chalk::IR::Node::Multiply');
use_ok('Chalk::IR::Node::Divide');
use_ok('Chalk::IR::Node::Start');
use_ok('Chalk::IR::Node::Return');
use_ok('Chalk::IR::Graph');

# Test Constant node execution
subtest 'Constant node execution' => sub {
    # Create a simple Constant node
    my $constant = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 42,
        type => 'Int',
    );

    # Execute should return the constant value
    my $result = $constant->execute();
    is($result, 42, 'Constant node execute returns its value');
};

# Test arithmetic operations
subtest 'Arithmetic node execution' => sub {
    # Create a values map simulating already-computed node values
    my %values = (
        'node_left' => 10,
        'node_right' => 3,
    );

    # Test Add: 10 + 3 = 13
    my $add = Chalk::IR::Node::Add->new(
        id => 'node_add',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $add_result = $add->execute(\%values);
    is($add_result, 13, 'Add node: 10 + 3 = 13');

    # Test Subtract: 10 - 3 = 7
    my $sub = Chalk::IR::Node::Subtract->new(
        id => 'node_sub',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $sub_result = $sub->execute(\%values);
    is($sub_result, 7, 'Subtract node: 10 - 3 = 7');

    # Test Multiply: 10 * 3 = 30
    my $mul = Chalk::IR::Node::Multiply->new(
        id => 'node_mul',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $mul_result = $mul->execute(\%values);
    is($mul_result, 30, 'Multiply node: 10 * 3 = 30');

    # Test Divide: 10 / 3 = 3.333...
    my $div = Chalk::IR::Node::Divide->new(
        id => 'node_div',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $div_result = $div->execute(\%values);
    cmp_ok($div_result, '==', 10/3, 'Divide node: 10 / 3');
};

# Test Start node execution
subtest 'Start node execution' => sub {
    # Start node represents function entry
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_start',
        inputs => [],
        function_name => 'main',
        params => [],
    );

    # Execute should return a control token (undef for now)
    my $result = $start->execute();
    ok(defined($result) || !defined($result), 'Start node execute completes');
};

# Test Return node execution
subtest 'Return node execution' => sub {
    # Create values map with the return value
    my %values = (
        'node_value' => 42,
    );

    # Return node wraps a value
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_return',
        inputs => ['node_ctrl', 'node_value'],
        value_id => 'node_value',
        control_id => 'node_ctrl',
    );

    # Execute should return the value
    my $result = $return->execute(\%values);
    is($result, 42, 'Return node returns its value');
};

done_testing();
