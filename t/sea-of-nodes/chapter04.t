# ABOUTME: Test for Sea of Nodes IR generation - Chapter 4: Method Parameters and Projection Nodes
# ABOUTME: Validates Proj nodes, Start node as MultiNode, parameter passing, and $ctrl tracking

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Scope');

# Test Start node as MultiNode with projections
subtest 'Start node with control and arg projections' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    # Create Start node for method with one parameter
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'calculate',
            params => ['$arg']  # Method signature
        }
    );
    $graph->add_node($start);

    # Create Proj node for control flow ($ctrl)
    my $ctrl_proj = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],  # Projects from Start
        attributes => {
            index => 0,
            label => '$ctrl'
        }
    );
    $graph->add_node($ctrl_proj);
    $scope->define('$ctrl', 'node_1');

    # Create Proj node for arg parameter
    my $arg_proj = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],  # Projects from Start
        attributes => {
            index => 1,
            label => '$arg'
        }
    );
    $graph->add_node($arg_proj);
    $scope->define('$arg', 'node_2');

    # Verify Start node
    my $start_node = $graph->get_node('node_0');
    ok($start_node, 'Start node exists');
    is($start_node->op, 'Start', 'Node op is Start');
    cmp_deeply($start_node->attributes->{params}, ['$arg'], 'Start has params list');

    # Verify control projection
    my $ctrl_node = $graph->get_node('node_1');
    ok($ctrl_node, 'Control projection exists');
    is($ctrl_node->op, 'Proj', 'Node op is Proj');
    is($ctrl_node->attributes->{index}, 0, 'Control has index 0');
    is($ctrl_node->attributes->{label}, '$ctrl', 'Control has label $ctrl');
    cmp_deeply($ctrl_node->inputs, ['node_0'], 'Control projects from Start');

    # Verify arg projection
    my $arg_node = $graph->get_node('node_2');
    ok($arg_node, 'Arg projection exists');
    is($arg_node->op, 'Proj', 'Node op is Proj');
    is($arg_node->attributes->{index}, 1, 'Arg has index 1');
    is($arg_node->attributes->{label}, '$arg', 'Arg has label $arg');
    cmp_deeply($arg_node->inputs, ['node_0'], 'Arg projects from Start');

    # Verify scope bindings
    is($scope->lookup('$ctrl'), 'node_1', 'Scope has $ctrl binding');
    is($scope->lookup('$arg'), 'node_2', 'Scope has $arg binding');
};

# Test parameter usage in expressions
subtest 'Parameter usage in arithmetic' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'calculate',
            params => ['$arg']
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
    $scope->define('$ctrl', 'node_1');

    # Arg projection
    my $arg = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$arg' }
    );
    $graph->add_node($arg);
    $scope->define('$arg', 'node_2');

    # Add operation: $arg + 10
    my $add = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],  # Control and arg projection
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },  # Reference to arg
            right => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($add);

    # Return node
    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_1', 'node_3'],  # Control and Add result
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->node_count, 5, 'Graph has 5 nodes');

    # Verify Add node uses parameter
    my $add_node = $graph->get_node('node_3');
    is($add_node->op, 'Add', 'Add node exists');
    is($add_node->attributes->{left}{node_id}, 'node_2', 'Add left operand is arg projection');
    is($add_node->attributes->{right}{value}, 10, 'Add right operand is 10');

    # Verify Return node
    my $ret_node = $graph->get_node('node_4');
    is($ret_node->op, 'Return', 'Return node exists');
    cmp_deeply($ret_node->inputs, ['node_1', 'node_3'], 'Return links to control and Add');
};

# Test multiple parameters
subtest 'Multiple parameters' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    # Start node with two parameters
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'add_numbers',
            params => ['$a', '$b']
        }
    );
    $graph->add_node($start);

    # Control projection (index 0)
    my $ctrl = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    );
    $graph->add_node($ctrl);
    $scope->define('$ctrl', 'node_1');

    # First parameter projection (index 1)
    my $a_proj = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$a' }
    );
    $graph->add_node($a_proj);
    $scope->define('$a', 'node_2');

    # Second parameter projection (index 2)
    my $b_proj = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 2, label => '$b' }
    );
    $graph->add_node($b_proj);
    $scope->define('$b', 'node_3');

    # Add operation: $a + $b
    my $add = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Add',
        inputs => ['node_1', 'node_2', 'node_3'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'NodeRef', node_id => 'node_3' }
        }
    );
    $graph->add_node($add);

    # Verify parameters in scope
    is($scope->lookup('$a'), 'node_2', 'First parameter in scope');
    is($scope->lookup('$b'), 'node_3', 'Second parameter in scope');

    # Verify Add uses both parameters
    my $add_node = $graph->get_node('node_4');
    is($add_node->attributes->{left}{node_id}, 'node_2', 'Add uses first parameter');
    is($add_node->attributes->{right}{node_id}, 'node_3', 'Add uses second parameter');
};

# Test JSON serialization with parameters
subtest 'JSON serialization with parameters' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'calculate',
            params => ['$arg']
        }
    );
    $graph->add_node($start);

    my $ctrl = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    );
    $graph->add_node($ctrl);

    my $arg = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$arg' }
    );
    $graph->add_node($arg);

    my $add = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($add);

    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_1', 'node_3'],
        attributes => {}
    );
    $graph->add_node($return);

    # Convert to JSON
    my $json = $graph->to_json();
    ok($json, 'Graph can be serialized to JSON');
    is(scalar @{$json->{nodes}}, 5, 'JSON has 5 nodes');

    # Find nodes by ID
    my %json_nodes = map { $_->{id} => $_ } @{$json->{nodes}};

    # Verify Start node in JSON
    ok(exists $json_nodes{'node_0'}, 'Start node in JSON');
    is($json_nodes{'node_0'}{op}, 'Start', 'Start op in JSON');
    cmp_deeply($json_nodes{'node_0'}{attributes}{params}, ['$arg'], 'Start params in JSON');

    # Verify Proj nodes in JSON
    ok(exists $json_nodes{'node_1'}, 'Control Proj in JSON');
    is($json_nodes{'node_1'}{op}, 'Proj', 'Control Proj op in JSON');
    is($json_nodes{'node_1'}{attributes}{index}, 0, 'Control Proj index in JSON');

    ok(exists $json_nodes{'node_2'}, 'Arg Proj in JSON');
    is($json_nodes{'node_2'}{op}, 'Proj', 'Arg Proj op in JSON');
    is($json_nodes{'node_2'}{attributes}{index}, 1, 'Arg Proj index in JSON');
};

# Test JSON round-trip with parameters
subtest 'JSON round-trip with parameters' => sub {
    my $graph1 = Chalk::IR::Graph->new();

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'calculate', params => ['$arg'] }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$arg' }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_1', 'node_2'],
        attributes => {}
    ));

    # Serialize and deserialize
    my $json = $graph1->to_json();
    my $graph2 = Chalk::IR::Graph->from_json($json);

    # Verify reconstructed graph
    is($graph2->node_count, 4, 'Reconstructed graph has 4 nodes');
    is($graph2->entry, 'node_0', 'Reconstructed entry is correct');

    # Verify nodes match
    for my $id (qw(node_0 node_1 node_2 node_3)) {
        my $node1 = $graph1->get_node($id);
        my $node2 = $graph2->get_node($id);

        is($node2->id, $node1->id, "Node $id: ID matches");
        is($node2->op, $node1->op, "Node $id: op matches");
        cmp_deeply($node2->inputs, $node1->inputs, "Node $id: inputs match");
        cmp_deeply($node2->attributes, $node1->attributes, "Node $id: attributes match");
    }
};

# Test complete example: method calculate($arg) { return $arg + 10; }
subtest 'Complete example: method calculate($arg) { return $arg + 10; }' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    # Create IR for method with parameter
    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => {
            function => 'calculate',
            params => ['$arg']
        }
    );
    $graph->add_node($start);

    # Control projection ($ctrl)
    my $ctrl = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 0, label => '$ctrl' }
    );
    $graph->add_node($ctrl);
    $scope->define('$ctrl', 'node_1');

    # Parameter projection ($arg)
    my $arg = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Proj',
        inputs => ['node_0'],
        attributes => { index => 1, label => '$arg' }
    );
    $graph->add_node($arg);
    $scope->define('$arg', 'node_2');

    # Add operation: $arg + 10
    my $add = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Add',
        inputs => ['node_1', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'Constant', value => 10, type => 'Int' }
        }
    );
    $graph->add_node($add);

    # Return node
    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_1', 'node_3'],
        attributes => {}
    );
    $graph->add_node($return);

    # Verify complete graph structure
    is($graph->node_count, 5, 'Graph has 5 nodes: Start, Ctrl, Arg, Add, Return');
    is($graph->entry, 'node_0', 'Entry is Start node');

    # Verify Start has params
    my $start_node = $graph->get_node('node_0');
    cmp_deeply($start_node->attributes->{params}, ['$arg'], 'Start node has parameter list');

    # Verify projections extract from Start
    my $ctrl_node = $graph->get_node('node_1');
    cmp_deeply($ctrl_node->inputs, ['node_0'], 'Control projection from Start');

    my $arg_node = $graph->get_node('node_2');
    cmp_deeply($arg_node->inputs, ['node_0'], 'Arg projection from Start');

    # Verify Add uses parameter
    my $add_node = $graph->get_node('node_3');
    is($add_node->attributes->{left}{node_id}, 'node_2', 'Add uses arg projection');
    is($add_node->attributes->{right}{value}, 10, 'Add uses constant 10');

    # Verify Return uses control and result
    my $ret_node = $graph->get_node('node_4');
    cmp_deeply($ret_node->inputs, ['node_1', 'node_3'], 'Return uses control and Add result');

    # Verify scope has all bindings
    is($scope->lookup('$ctrl'), 'node_1', 'Scope has control');
    is($scope->lookup('$arg'), 'node_2', 'Scope has parameter');
};

# Test IR Builder generates correct IR for method with parameter
subtest 'IR Builder generates correct IR for method calculate($arg) { return $arg + 10; }' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->build_from_code("method calculate(\$arg) { return \$arg + 10; }");

    # Verify graph structure
    ok($graph, 'Builder returns a graph');
    is($graph->node_count, 5, 'Generated graph has 5 nodes (Start, Ctrl, Arg, Add, Return)');

    # Verify Start node with params
    my $start_node = $graph->get_node('node_0');
    ok($start_node, 'Start node exists');
    is($start_node->op, 'Start', 'Start node has correct op');
    is($start_node->attributes->{function}, 'calculate', 'Start has function name calculate');
    cmp_deeply($start_node->attributes->{params}, ['$arg'], 'Start has parameter list');

    # Verify Control projection ($ctrl)
    my $ctrl_node = $graph->get_node('node_1');
    ok($ctrl_node, 'Control projection exists');
    is($ctrl_node->op, 'Proj', 'Control node is Proj');
    is($ctrl_node->attributes->{index}, 0, 'Control has index 0');
    is($ctrl_node->attributes->{label}, '$ctrl', 'Control has label $ctrl');

    # Verify Arg projection
    my $arg_node = $graph->get_node('node_2');
    ok($arg_node, 'Arg projection exists');
    is($arg_node->op, 'Proj', 'Arg node is Proj');
    is($arg_node->attributes->{index}, 1, 'Arg has index 1');
    is($arg_node->attributes->{label}, '$arg', 'Arg has label $arg');

    # Verify Add node ($arg + 10)
    my $add_node = $graph->get_node('node_3');
    ok($add_node, 'Add node exists');
    is($add_node->op, 'Add', 'Add node has correct op');
    is($add_node->attributes->{left}{node_id}, 'node_2', 'Add left operand is arg projection');
    is($add_node->attributes->{right}{value}, 10, 'Add right operand is 10');

    # Verify Return node
    my $ret_node = $graph->get_node('node_4');
    ok($ret_node, 'Return node exists');
    is($ret_node->op, 'Return', 'Return node has correct op');
    cmp_deeply($ret_node->inputs, ['node_1', 'node_3'], 'Return uses control and Add result');

    # Verify Scope tracking
    is($builder->scope->lookup('$ctrl'), 'node_1', 'Scope tracks $ctrl');
    is($builder->scope->lookup('$arg'), 'node_2', 'Scope tracks $arg');
};

done_testing();
