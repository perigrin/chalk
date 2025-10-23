# ABOUTME: Test for Sea of Nodes IR generation - Chapter 3: Local Variables and SSA Form
# ABOUTME: Validates variable declarations, Store/Load nodes, and SSA properties with scope management

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Scope');

# Test Scope basic operations
subtest 'Scope basic operations' => sub {
    my $scope = Chalk::IR::Scope->new();

    # Should start with one global scope
    is($scope->depth, 1, 'Scope starts with depth 1 (global scope)');

    # Define a variable in global scope
    $scope->define('$x', 'node_1');
    is($scope->lookup('$x'), 'node_1', 'Can define and lookup variable in global scope');

    # Push a new scope
    $scope->push_scope();
    is($scope->depth, 2, 'Depth increases after push_scope');

    # Define same variable in inner scope (shadowing)
    $scope->define('$x', 'node_2');
    is($scope->lookup('$x'), 'node_2', 'Inner scope shadows outer scope');

    # Define a new variable in inner scope
    $scope->define('$y', 'node_3');
    is($scope->lookup('$y'), 'node_3', 'Can define new variable in inner scope');

    # Pop inner scope
    $scope->pop_scope();
    is($scope->depth, 1, 'Depth decreases after pop_scope');
    is($scope->lookup('$x'), 'node_1', 'Outer scope variable restored after pop');
    is($scope->lookup('$y'), undef, 'Inner scope variable no longer accessible');
};

# Test nested scopes
subtest 'Nested scope lookup' => sub {
    my $scope = Chalk::IR::Scope->new();

    # Define in global scope
    $scope->define('$a', 'node_1');

    # Push first inner scope
    $scope->push_scope();
    $scope->define('$b', 'node_2');

    # Push second inner scope
    $scope->push_scope();
    $scope->define('$c', 'node_3');

    # Should be able to see all three variables
    is($scope->lookup('$a'), 'node_1', 'Can see global scope variable');
    is($scope->lookup('$b'), 'node_2', 'Can see parent scope variable');
    is($scope->lookup('$c'), 'node_3', 'Can see current scope variable');

    is($scope->depth, 3, 'Depth is 3 with two pushed scopes');
};

# Test Store node creation
subtest 'Store node creation' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Store node: my $x = 5
    # Store stores a constant value
    my $store = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],  # Control dependency on Start
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 5, type => 'Int' }
        }
    );
    $graph->add_node($store);

    # Verify Store node structure
    my $store_node = $graph->get_node('node_1');
    ok($store_node, 'Store node exists');
    is($store_node->op, 'Store', 'Node op is Store');
    is($store_node->attributes->{name}, '$x', 'Store has variable name');
    is($store_node->attributes->{value}{value}, 5, 'Store has value 5');
};

# Test Load node creation and linkage to Store
subtest 'Load node creation and Store linkage' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Store node: my $x = 5
    my $store = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 5, type => 'Int' }
        }
    );
    $graph->add_node($store);

    # Create Load node: read $x
    my $load = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_0', 'node_1'],  # Control from Start, data from Store
        attributes => {
            name => '$x',
            store_id => 'node_1'  # Reference to the Store that defined it
        }
    );
    $graph->add_node($load);

    # Verify Load node structure
    my $load_node = $graph->get_node('node_2');
    ok($load_node, 'Load node exists');
    is($load_node->op, 'Load', 'Node op is Load');
    is($load_node->attributes->{name}, '$x', 'Load references variable name');
    is($load_node->attributes->{store_id}, 'node_1', 'Load links to Store node');
    cmp_deeply($load_node->inputs, ['node_0', 'node_1'], 'Load has inputs from Start and Store');
};

# Test SSA property: each assignment creates a separate node
subtest 'SSA property: multiple assignments' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    # Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # First assignment: my $x = 1
    my $store1 = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 1, type => 'Int' }
        }
    );
    $graph->add_node($store1);
    $scope->define('$x', 'node_1');

    # Load $x (reads first version)
    my $load1 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_0', 'node_1'],
        attributes => {
            name => '$x',
            store_id => 'node_1'
        }
    );
    $graph->add_node($load1);

    # Second assignment: $x = 2 (creates new version in SSA)
    my $store2 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 2, type => 'Int' }
        }
    );
    $graph->add_node($store2);
    $scope->define('$x', 'node_3');  # Updates scope to point to new version

    # Load $x (reads second version)
    my $load2 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Load',
        inputs => ['node_0', 'node_3'],
        attributes => {
            name => '$x',
            store_id => 'node_3'
        }
    );
    $graph->add_node($load2);

    # Verify both Store nodes exist (SSA property)
    ok($graph->get_node('node_1'), 'First Store node exists');
    ok($graph->get_node('node_3'), 'Second Store node exists');
    isnt($graph->get_node('node_1'), $graph->get_node('node_3'),
         'Two Store nodes are distinct');

    # Verify Load nodes reference correct Store versions
    is($load1->attributes->{store_id}, 'node_1', 'First Load references first Store');
    is($load2->attributes->{store_id}, 'node_3', 'Second Load references second Store');

    # Verify scope tracks latest version
    is($scope->lookup('$x'), 'node_3', 'Scope tracks latest version of variable');
};

# Test complete example: my $x = 5; return $x * 2;
subtest 'Complete example: my $x = 5; return $x * 2' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $scope = Chalk::IR::Scope->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create Store node: my $x = 5
    my $store = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 5, type => 'Int' }
        }
    );
    $graph->add_node($store);
    $scope->define('$x', 'node_1');

    # Create Load node: read $x
    my $load = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_0', 'node_1'],
        attributes => {
            name => '$x',
            store_id => 'node_1'
        }
    );
    $graph->add_node($load);

    # Create Multiply node: $x * 2
    # Left operand is a NodeRef to the Load, right operand is Constant 2
    my $mul = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Multiply',
        inputs => ['node_0', 'node_2'],
        attributes => {
            left => { op => 'NodeRef', node_id => 'node_2' },
            right => { op => 'Constant', value => 2, type => 'Int' }
        }
    );
    $graph->add_node($mul);

    # Create Return node
    my $return = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Return',
        inputs => ['node_0', 'node_3'],
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->node_count, 5, 'Graph has 5 nodes');
    is($graph->entry, 'node_0', 'Entry is Start node');

    # Verify Store node
    my $store_node = $graph->get_node('node_1');
    is($store_node->op, 'Store', 'Store node exists');
    is($store_node->attributes->{name}, '$x', 'Store has variable name $x');

    # Verify Load node
    my $load_node = $graph->get_node('node_2');
    is($load_node->op, 'Load', 'Load node exists');
    is($load_node->attributes->{store_id}, 'node_1', 'Load references Store');

    # Verify Multiply node
    my $mul_node = $graph->get_node('node_3');
    is($mul_node->op, 'Multiply', 'Multiply node exists');
    is($mul_node->attributes->{left}{node_id}, 'node_2', 'Multiply left operand is Load');
    is($mul_node->attributes->{right}{value}, 2, 'Multiply right operand is 2');

    # Verify Return node
    my $ret_node = $graph->get_node('node_4');
    is($ret_node->op, 'Return', 'Return node exists');
    cmp_deeply($ret_node->inputs, ['node_0', 'node_3'], 'Return links to Start and Multiply');
};

# Test JSON serialization of variables
subtest 'JSON serialization with variables' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    my $store = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 42, type => 'Int' }
        }
    );
    $graph->add_node($store);

    my $load = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_0', 'node_1'],
        attributes => {
            name => '$x',
            store_id => 'node_1'
        }
    );
    $graph->add_node($load);

    my $return = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_0', 'node_2'],
        attributes => {}
    );
    $graph->add_node($return);

    # Convert to JSON
    my $json = $graph->to_json();
    ok($json, 'Graph can be serialized to JSON');
    is($json->{version}, '1.0', 'JSON has version');
    is(scalar @{$json->{nodes}}, 4, 'JSON has 4 nodes');

    # Find nodes by ID
    my %json_nodes = map { $_->{id} => $_ } @{$json->{nodes}};

    # Verify Store node in JSON
    ok(exists $json_nodes{'node_1'}, 'Store node in JSON');
    is($json_nodes{'node_1'}{op}, 'Store', 'Store op in JSON');
    is($json_nodes{'node_1'}{attributes}{name}, '$x', 'Store name in JSON');
    is($json_nodes{'node_1'}{attributes}{value}{value}, 42, 'Store value in JSON');

    # Verify Load node in JSON
    ok(exists $json_nodes{'node_2'}, 'Load node in JSON');
    is($json_nodes{'node_2'}{op}, 'Load', 'Load op in JSON');
    is($json_nodes{'node_2'}{attributes}{name}, '$x', 'Load name in JSON');
    is($json_nodes{'node_2'}{attributes}{store_id}, 'node_1', 'Load store_id in JSON');
};

# Test JSON round-trip with variables
subtest 'JSON round-trip with variables' => sub {
    my $graph1 = Chalk::IR::Graph->new();

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 10, type => 'Int' }
        }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_0', 'node_1'],
        attributes => {
            name => '$x',
            store_id => 'node_1'
        }
    ));

    $graph1->add_node(Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Return',
        inputs => ['node_0', 'node_2'],
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

# Test Load node optimization (constant folding through Load)
subtest 'Load node constant folding' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Store a constant
    my $store = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'Store',
        inputs => ['node_0'],
        attributes => {
            name => '$x',
            value => { op => 'Constant', value => 7, type => 'Int' }
        }
    );
    $graph->add_node($store);

    # Load the variable
    my $load = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Load',
        inputs => ['node_0', 'node_1'],
        attributes => {
            name => '$x',
            store_id => 'node_1'
        }
    );

    # Apply peephole optimization
    my $optimized = $load->peephole($graph);

    # Should fold to a Constant
    ok($optimized, 'Peephole returned a node');
    is($optimized->op, 'Constant', 'Load of constant Store folded to Constant');
    is($optimized->attributes->{value}, 7, 'Folded constant has value 7');
};

done_testing();
