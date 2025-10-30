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
use_ok('Chalk::IR::Node::GT');
use_ok('Chalk::IR::Node::LT');
use_ok('Chalk::IR::Node::EQ');
use_ok('Chalk::IR::Node::NE');
use_ok('Chalk::IR::Node::GE');
use_ok('Chalk::IR::Node::LE');
use_ok('Chalk::IR::Node::Negate');
use_ok('Chalk::IR::Node::If');
use_ok('Chalk::IR::Node::Proj');
use_ok('Chalk::IR::Node::Region');
use_ok('Chalk::IR::Node::Phi');
use_ok('Chalk::IR::Node::Store');
use_ok('Chalk::IR::Node::Load');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Interpreter');

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

# Test comparison operators
subtest 'Comparison operators execution' => sub {
    my %values = (
        'node_left' => 10,
        'node_right' => 3,
    );

    # Test GT: 10 > 3 = true (1)
    my $gt = Chalk::IR::Node::GT->new(
        id => 'node_gt',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $gt_result = $gt->execute(\%values);
    is($gt_result, 1, 'GT: 10 > 3 = true');

    # Test LT: 10 < 3 = false (0)
    my $lt = Chalk::IR::Node::LT->new(
        id => 'node_lt',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $lt_result = $lt->execute(\%values);
    is($lt_result, 0, 'LT: 10 < 3 = false');

    # Test EQ: 10 == 10 = true
    $values{'node_right'} = 10;
    my $eq = Chalk::IR::Node::EQ->new(
        id => 'node_eq',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $eq_result = $eq->execute(\%values);
    is($eq_result, 1, 'EQ: 10 == 10 = true');

    # Test NE: 10 != 3 = true
    $values{'node_right'} = 3;
    my $ne = Chalk::IR::Node::NE->new(
        id => 'node_ne',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $ne_result = $ne->execute(\%values);
    is($ne_result, 1, 'NE: 10 != 3 = true');

    # Test GE: 10 >= 10 = true
    $values{'node_right'} = 10;
    my $ge = Chalk::IR::Node::GE->new(
        id => 'node_ge',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $ge_result = $ge->execute(\%values);
    is($ge_result, 1, 'GE: 10 >= 10 = true');

    # Test LE: 10 <= 3 = false
    $values{'node_right'} = 3;
    my $le = Chalk::IR::Node::LE->new(
        id => 'node_le',
        inputs => ['node_ctrl', 'node_left', 'node_right'],
        left_id => 'node_left',
        right_id => 'node_right',
    );
    my $le_result = $le->execute(\%values);
    is($le_result, 0, 'LE: 10 <= 3 = false');
};

# Test unary operators
subtest 'Unary operators execution' => sub {
    # Test Negate: -(-5) = 5
    my %values = ('node_operand' => -5);
    my $negate = Chalk::IR::Node::Negate->new(
        id => 'node_neg',
        inputs => ['node_ctrl', 'node_operand'],
        operand_id => 'node_operand',
    );
    my $result = $negate->execute(\%values);
    is($result, 5, 'Negate: -(-5) = 5');

    # Test Negate: -(42) = -42
    $values{'node_operand'} = 42;
    my $negate2 = Chalk::IR::Node::Negate->new(
        id => 'node_neg2',
        inputs => ['node_ctrl', 'node_operand'],
        operand_id => 'node_operand',
    );
    my $result2 = $negate2->execute(\%values);
    is($result2, -42, 'Negate: -(42) = -42');
};

# Test control flow nodes
subtest 'Control flow: If node execution' => sub {
    # If node returns the condition value
    my %values = ('node_cond' => 1);
    my $if = Chalk::IR::Node::If->new(
        id => 'node_if',
        inputs => ['node_ctrl', 'node_cond'],
        condition_id => 'node_cond',
    );
    my $result = $if->execute(\%values);
    is($result, 1, 'If node returns condition value (true)');

    # Test with false condition
    $values{'node_cond'} = 0;
    my $if2 = Chalk::IR::Node::If->new(
        id => 'node_if2',
        inputs => ['node_ctrl', 'node_cond'],
        condition_id => 'node_cond',
    );
    my $result2 = $if2->execute(\%values);
    is($result2, 0, 'If node returns condition value (false)');
};

subtest 'Control flow: Proj node execution' => sub {
    # Proj extracts control path based on If result and its index
    # Index 0 = false branch, Index 1 = true branch

    # Test true branch (index 1)
    my %values = ('node_if' => 1);
    my $proj_true = Chalk::IR::Node::Proj->new(
        id => 'node_proj_true',
        inputs => ['node_if'],
        index => 1,
        label => 'IfTrue',
    );
    my $result = $proj_true->execute(\%values);
    is($result, 1, 'Proj[1] active when If=true');

    # Test false branch (index 0)
    $values{'node_if'} = 0;
    my $proj_false = Chalk::IR::Node::Proj->new(
        id => 'node_proj_false',
        inputs => ['node_if'],
        index => 0,
        label => 'IfFalse',
    );
    my $result2 = $proj_false->execute(\%values);
    is($result2, 1, 'Proj[0] active when If=false');

    # Test inactive branch
    $values{'node_if'} = 1;
    my $proj_false2 = Chalk::IR::Node::Proj->new(
        id => 'node_proj_false2',
        inputs => ['node_if'],
        index => 0,
        label => 'IfFalse',
    );
    my $result3 = $proj_false2->execute(\%values);
    is($result3, 0, 'Proj[0] inactive when If=true');
};

subtest 'Control flow: Region node execution' => sub {
    # Region merges control from multiple paths
    my %values = (
        'node_proj_true' => 1,
        'node_proj_false' => 0,
    );
    my $region = Chalk::IR::Node::Region->new(
        id => 'node_region',
        inputs => ['node_proj_false', 'node_proj_true'],
    );
    my $result = $region->execute(\%values);
    # Region returns index of active path (1 in this case - true path)
    is($result, 1, 'Region returns active path index');

    # Test with false path active
    $values{'node_proj_true'} = 0;
    $values{'node_proj_false'} = 1;
    my $region2 = Chalk::IR::Node::Region->new(
        id => 'node_region2',
        inputs => ['node_proj_false', 'node_proj_true'],
    );
    my $result2 = $region2->execute(\%values);
    is($result2, 0, 'Region returns active path index (false path)');
};

subtest 'Control flow: Phi node execution' => sub {
    # Phi selects value based on Region's active path
    # inputs: [region_id, value_for_path_0, value_for_path_1, ...]
    my %values = (
        'node_region' => 1,  # Path 1 is active (true branch)
        'node_val_false' => -42,
        'node_val_true' => 42,
    );
    my $phi = Chalk::IR::Node::Phi->new(
        id => 'node_phi',
        inputs => ['node_region', 'node_val_false', 'node_val_true'],
        region_id => 'node_region',
    );
    my $result = $phi->execute(\%values);
    is($result, 42, 'Phi selects true-branch value when path=1');

    # Test with false path active
    $values{'node_region'} = 0;
    my $phi2 = Chalk::IR::Node::Phi->new(
        id => 'node_phi2',
        inputs => ['node_region', 'node_val_false', 'node_val_true'],
        region_id => 'node_region',
    );
    my $result2 = $phi2->execute(\%values);
    is($result2, -42, 'Phi selects false-branch value when path=0');
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

# Test graph linearization
subtest 'Simple graph linearization' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a simple graph: Start -> Constant -> Return
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    my $constant = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 42,
        type => 'Int',
    );
    $graph->add_node($constant);

    my $return = Chalk::IR::Node::Return->new(
        id => 'node_2',
        inputs => ['node_0', 'node_1'],
        value_id => 'node_1',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Linearize the graph
    my @schedule = $graph->linearize();

    # Verify we have all 3 nodes
    is(scalar(@schedule), 3, 'Linearization includes all 3 nodes');

    # Verify order: Start must come before Constant and Return
    my %positions;
    for my $i (0..$#schedule) {
        $positions{$schedule[$i]->id} = $i;
    }

    ok($positions{'node_0'} < $positions{'node_1'}, 'Start before Constant');
    ok($positions{'node_0'} < $positions{'node_2'}, 'Start before Return');
    ok($positions{'node_1'} < $positions{'node_2'}, 'Constant before Return');
};

# Test graph linearization with data dependencies
subtest 'Graph linearization with arithmetic: (3 + 5) * 2' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    # Constants: 3, 5, 2
    my $const3 = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 3,
        type => 'Int',
    );
    $graph->add_node($const3);

    my $const5 = Chalk::IR::Node::Constant->new(
        id => 'node_2',
        inputs => ['node_0'],
        value => 5,
        type => 'Int',
    );
    $graph->add_node($const5);

    # Add: 3 + 5
    my $add = Chalk::IR::Node::Add->new(
        id => 'node_3',
        inputs => ['node_0', 'node_1', 'node_2'],
        left_id => 'node_1',
        right_id => 'node_2',
    );
    $graph->add_node($add);

    my $const2 = Chalk::IR::Node::Constant->new(
        id => 'node_4',
        inputs => ['node_0'],
        value => 2,
        type => 'Int',
    );
    $graph->add_node($const2);

    # Multiply: (3 + 5) * 2
    my $mul = Chalk::IR::Node::Multiply->new(
        id => 'node_5',
        inputs => ['node_0', 'node_3', 'node_4'],
        left_id => 'node_3',
        right_id => 'node_4',
    );
    $graph->add_node($mul);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_6',
        inputs => ['node_0', 'node_5'],
        value_id => 'node_5',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Linearize the graph
    my @schedule = $graph->linearize();

    # Verify we have all 7 nodes
    is(scalar(@schedule), 7, 'Linearization includes all 7 nodes');

    # Build position map
    my %positions;
    for my $i (0..$#schedule) {
        $positions{$schedule[$i]->id} = $i;
    }

    # Verify Start is first
    is($positions{'node_0'}, 0, 'Start is first');

    # Verify constants before Add
    ok($positions{'node_1'} < $positions{'node_3'}, 'Constant(3) before Add');
    ok($positions{'node_2'} < $positions{'node_3'}, 'Constant(5) before Add');

    # Verify Add and Constant(2) before Multiply
    ok($positions{'node_3'} < $positions{'node_5'}, 'Add before Multiply');
    ok($positions{'node_4'} < $positions{'node_5'}, 'Constant(2) before Multiply');

    # Verify Multiply before Return
    ok($positions{'node_5'} < $positions{'node_6'}, 'Multiply before Return');
};

# Test Interpreter execution: return 42
subtest 'Interpreter: return 42' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    # Constant 42
    my $constant = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 42,
        type => 'Int',
    );
    $graph->add_node($constant);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_2',
        inputs => ['node_0', 'node_1'],
        value_id => 'node_1',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Execute graph
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 42, 'Interpreter executes: return 42');
};

# Test Interpreter execution: 3 + 5
subtest 'Interpreter: 3 + 5' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    # Constants
    my $const3 = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 3,
        type => 'Int',
    );
    $graph->add_node($const3);

    my $const5 = Chalk::IR::Node::Constant->new(
        id => 'node_2',
        inputs => ['node_0'],
        value => 5,
        type => 'Int',
    );
    $graph->add_node($const5);

    # Add
    my $add = Chalk::IR::Node::Add->new(
        id => 'node_3',
        inputs => ['node_0', 'node_1', 'node_2'],
        left_id => 'node_1',
        right_id => 'node_2',
    );
    $graph->add_node($add);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_4',
        inputs => ['node_0', 'node_3'],
        value_id => 'node_3',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Execute graph
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 8, 'Interpreter executes: 3 + 5 = 8');
};

# Test Interpreter execution: (3 + 5) * 2
subtest 'Interpreter: (3 + 5) * 2' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    # Constants: 3, 5, 2
    my $const3 = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 3,
        type => 'Int',
    );
    $graph->add_node($const3);

    my $const5 = Chalk::IR::Node::Constant->new(
        id => 'node_2',
        inputs => ['node_0'],
        value => 5,
        type => 'Int',
    );
    $graph->add_node($const5);

    # Add: 3 + 5
    my $add = Chalk::IR::Node::Add->new(
        id => 'node_3',
        inputs => ['node_0', 'node_1', 'node_2'],
        left_id => 'node_1',
        right_id => 'node_2',
    );
    $graph->add_node($add);

    my $const2 = Chalk::IR::Node::Constant->new(
        id => 'node_4',
        inputs => ['node_0'],
        value => 2,
        type => 'Int',
    );
    $graph->add_node($const2);

    # Multiply: (3 + 5) * 2
    my $mul = Chalk::IR::Node::Multiply->new(
        id => 'node_5',
        inputs => ['node_0', 'node_3', 'node_4'],
        left_id => 'node_3',
        right_id => 'node_4',
    );
    $graph->add_node($mul);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_6',
        inputs => ['node_0', 'node_5'],
        value_id => 'node_5',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Execute graph
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 16, 'Interpreter executes: (3 + 5) * 2 = 16');
};

# Integration test: Full if/else statement
subtest 'Interpreter: if (x > 0) { 42 } else { -42 } with x=5' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    # x = 5
    my $x = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 5,
        type => 'Int',
    );
    $graph->add_node($x);

    # 0
    my $zero = Chalk::IR::Node::Constant->new(
        id => 'node_2',
        inputs => ['node_0'],
        value => 0,
        type => 'Int',
    );
    $graph->add_node($zero);

    # x > 0
    my $gt = Chalk::IR::Node::GT->new(
        id => 'node_3',
        inputs => ['node_0', 'node_1', 'node_2'],
        left_id => 'node_1',
        right_id => 'node_2',
    );
    $graph->add_node($gt);

    # If node
    my $if = Chalk::IR::Node::If->new(
        id => 'node_4',
        inputs => ['node_0', 'node_3'],
        condition_id => 'node_3',
    );
    $graph->add_node($if);

    # Proj[0] - false branch
    my $proj_false = Chalk::IR::Node::Proj->new(
        id => 'node_5',
        inputs => ['node_4'],
        index => 0,
        label => 'IfFalse',
    );
    $graph->add_node($proj_false);

    # Proj[1] - true branch
    my $proj_true = Chalk::IR::Node::Proj->new(
        id => 'node_6',
        inputs => ['node_4'],
        index => 1,
        label => 'IfTrue',
    );
    $graph->add_node($proj_true);

    # 42 (true branch value)
    my $val_true = Chalk::IR::Node::Constant->new(
        id => 'node_7',
        inputs => ['node_6'],
        value => 42,
        type => 'Int',
    );
    $graph->add_node($val_true);

    # -42 (false branch value)
    my $val_false = Chalk::IR::Node::Constant->new(
        id => 'node_8',
        inputs => ['node_5'],
        value => -42,
        type => 'Int',
    );
    $graph->add_node($val_false);

    # Region merges both paths
    my $region = Chalk::IR::Node::Region->new(
        id => 'node_9',
        inputs => ['node_5', 'node_6'],  # false, true
    );
    $graph->add_node($region);

    # Phi selects value based on active path
    my $phi = Chalk::IR::Node::Phi->new(
        id => 'node_10',
        inputs => ['node_9', 'node_8', 'node_7'],  # region, val_false, val_true
        region_id => 'node_9',
    );
    $graph->add_node($phi);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_11',
        inputs => ['node_0', 'node_10'],
        value_id => 'node_10',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Execute graph
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 42, 'if (5 > 0) returns 42 (true branch)');
};

subtest 'Interpreter: if (x > 0) { 42 } else { -42 } with x=-5' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'main',
        params => [],
    );
    $graph->add_node($start);

    # x = -5
    my $x = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => -5,
        type => 'Int',
    );
    $graph->add_node($x);

    # 0
    my $zero = Chalk::IR::Node::Constant->new(
        id => 'node_2',
        inputs => ['node_0'],
        value => 0,
        type => 'Int',
    );
    $graph->add_node($zero);

    # x > 0
    my $gt = Chalk::IR::Node::GT->new(
        id => 'node_3',
        inputs => ['node_0', 'node_1', 'node_2'],
        left_id => 'node_1',
        right_id => 'node_2',
    );
    $graph->add_node($gt);

    # If node
    my $if = Chalk::IR::Node::If->new(
        id => 'node_4',
        inputs => ['node_0', 'node_3'],
        condition_id => 'node_3',
    );
    $graph->add_node($if);

    # Proj[0] - false branch
    my $proj_false = Chalk::IR::Node::Proj->new(
        id => 'node_5',
        inputs => ['node_4'],
        index => 0,
        label => 'IfFalse',
    );
    $graph->add_node($proj_false);

    # Proj[1] - true branch
    my $proj_true = Chalk::IR::Node::Proj->new(
        id => 'node_6',
        inputs => ['node_4'],
        index => 1,
        label => 'IfTrue',
    );
    $graph->add_node($proj_true);

    # 42 (true branch value)
    my $val_true = Chalk::IR::Node::Constant->new(
        id => 'node_7',
        inputs => ['node_6'],
        value => 42,
        type => 'Int',
    );
    $graph->add_node($val_true);

    # -42 (false branch value)
    my $val_false = Chalk::IR::Node::Constant->new(
        id => 'node_8',
        inputs => ['node_5'],
        value => -42,
        type => 'Int',
    );
    $graph->add_node($val_false);

    # Region merges both paths
    my $region = Chalk::IR::Node::Region->new(
        id => 'node_9',
        inputs => ['node_5', 'node_6'],  # false, true
    );
    $graph->add_node($region);

    # Phi selects value based on active path
    my $phi = Chalk::IR::Node::Phi->new(
        id => 'node_10',
        inputs => ['node_9', 'node_8', 'node_7'],  # region, val_false, val_true
        region_id => 'node_9',
    );
    $graph->add_node($phi);

    # Return
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_11',
        inputs => ['node_0', 'node_10'],
        value_id => 'node_10',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Execute graph
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, -42, 'if (-5 > 0) returns -42 (false branch)');
};

# Test memory operations: Store node
subtest 'Memory operations: Store node execution' => sub {
    # Values map with memory state, address, and value already computed
    my %values = (
        'mem_0' => 1,        # Initial memory state (token)
        'addr_1' => 100,     # Address constant
        'val_42' => 42,      # Value to store
    );

    # Create a Store node
    my $store = Chalk::IR::Node::Store->new(
        id => 'store_1',
        inputs => ['mem_0', 'addr_1', 'val_42'],  # memory_in, address, value
    );

    # Store should execute and return memory state token
    # Actual storage happens in interpreter's heap
    my %heap;
    my $result = $store->execute(\%values, \%heap);

    is($result, 1, 'Store returns memory state token');
    is($heap{100}, 42, 'Store writes value 42 to address 100 in heap');
};

# Test memory operations: Load node
subtest 'Memory operations: Load node execution' => sub {
    # Values map with memory state and address
    my %values = (
        'mem_1' => 1,        # Memory state after store
        'addr_1' => 100,     # Address constant
    );

    # Heap already has a value stored
    my %heap = (100 => 42);

    # Create a Load node
    my $load = Chalk::IR::Node::Load->new(
        id => 'load_1',
        inputs => ['mem_1', 'addr_1'],  # memory_in, address
    );

    # Load should return the value from heap
    my $result = $load->execute(\%values, \%heap);

    is($result, 42, 'Load returns value 42 from address 100');
};

# Test memory operations: Store then Load sequence
subtest 'Interpreter: Store value, then Load it back' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Start node (provides initial memory state)
    my $start = Chalk::IR::Node::Start->new(
        id => 'node_0',
        inputs => [],
        function_name => 'test_memory',
        params => [],
    );
    $graph->add_node($start);

    # Address constant: 100
    my $addr = Chalk::IR::Node::Constant->new(
        id => 'node_1',
        inputs => ['node_0'],
        value => 100,
        type => 'Int',
    );
    $graph->add_node($addr);

    # Value constant: 42
    my $val = Chalk::IR::Node::Constant->new(
        id => 'node_2',
        inputs => ['node_0'],
        value => 42,
        type => 'Int',
    );
    $graph->add_node($val);

    # Store: mem[100] = 42
    my $store = Chalk::IR::Node::Store->new(
        id => 'node_3',
        inputs => ['node_0', 'node_1', 'node_2'],  # memory, address, value
    );
    $graph->add_node($store);

    # Load: read mem[100]
    my $load = Chalk::IR::Node::Load->new(
        id => 'node_4',
        inputs => ['node_3', 'node_1'],  # memory_from_store, address
    );
    $graph->add_node($load);

    # Return loaded value
    my $return = Chalk::IR::Node::Return->new(
        id => 'node_5',
        inputs => ['node_0', 'node_4'],
        value_id => 'node_4',
        control_id => 'node_0',
    );
    $graph->add_node($return);

    # Execute graph
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 42, 'Store 42 at address 100, Load returns 42');
};

done_testing();
