#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes lazy phi creation with sentinel values (Issue #246)
# ABOUTME: Validates that phi nodes are created lazily on lookup, not eagerly

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Node::Scope;

# Test 1: Sentinel marking when entering loop
subtest 'enter_loop() marks all variables with sentinel' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create initial scope with some bindings
    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $const_10 = Chalk::IR::Node->new(
        id => 'const_10',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => {
            '$i' => $const_0,
            '$n' => $const_10,
        },
        current_control => 'start_1',
    );

    # Create loop node
    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($loop);

    # Enter loop - should mark all variables with sentinel
    my $loop_scope = $scope->enter_loop($loop);

    # The loop scope should have sentinel values (the scope itself or a marker)
    ok($loop_scope, 'enter_loop returns a new scope');
    isnt($loop_scope, $scope, 'enter_loop returns a different scope');

    # Check that loop_node is tracked
    ok($loop_scope->can('loop_node'), 'loop scope has loop_node accessor');
    is($loop_scope->loop_node, $loop, 'loop_node returns the Loop node');

    # Check that bindings are sentinels (the scope or a marker)
    my $i_binding = $loop_scope->local_bindings->{'$i'};
    my $n_binding = $loop_scope->local_bindings->{'$n'};

    ok($loop_scope->is_sentinel($i_binding), '$i binding is a sentinel');
    ok($loop_scope->is_sentinel($n_binding), '$n binding is a sentinel');
};

# Test 2: Lazy phi creation on lookup
subtest 'lookup() creates phi lazily when sentinel is found' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create initial value
    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => { '$i' => $const_0 },
        current_control => 'start_1',
    );

    # Create loop node
    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($loop);

    # Enter loop
    my $loop_scope = $scope->enter_loop($loop);

    # Now lookup $i - this should create a phi lazily
    my $phi = $loop_scope->lookup('$i');

    ok($phi, 'lookup returns a value');
    is($phi->op, 'Phi', 'lookup returns a Phi node');

    # The phi should have the loop as its region (first input)
    my @inputs = $phi->inputs->@*;
    is($inputs[0], $loop->id, 'Phi input[0] is region (loop)');
    is($inputs[1], $const_0->id, 'Phi input[1] is initial value');

    # Backedge placeholder should be present or null
    # (will be filled in when variable is assigned)
};

# Test 3: Subsequent lookups return same phi
subtest 'lookup() returns existing phi on subsequent calls' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => { '$i' => $const_0 },
        current_control => 'start_1',
    );

    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($loop);

    my $loop_scope = $scope->enter_loop($loop);

    # First lookup creates phi
    my $phi1 = $loop_scope->lookup('$i');

    # Second lookup returns same phi
    my $phi2 = $loop_scope->lookup('$i');

    is($phi1->id, $phi2->id, 'Same phi returned on subsequent lookups');
};

# Test 4: Variables not accessed don't get phis
subtest 'Unaccessed variables do not get phi nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $const_10 = Chalk::IR::Node->new(
        id => 'const_10',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => {
            '$i' => $const_0,
            '$n' => $const_10,  # This one won't be accessed
        },
        current_control => 'start_1',
    );

    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($loop);

    my $loop_scope = $scope->enter_loop($loop);

    # Only lookup $i
    my $phi_i = $loop_scope->lookup('$i');

    # Check $n is still a sentinel (no phi created)
    my $n_binding = $loop_scope->local_bindings->{'$n'};
    ok($loop_scope->is_sentinel($n_binding), '$n remains a sentinel (no phi needed)');
};

# Test 5: with_binding updates phi backedge
subtest 'with_binding() updates phi backedge when variable assigned' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => { '$i' => $const_0 },
        current_control => 'start_1',
    );

    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($loop);

    my $loop_scope = $scope->enter_loop($loop);

    # Lookup $i - creates phi with backedge placeholder
    my $phi = $loop_scope->lookup('$i');

    # Now assign to $i with a new value (simulating $i = $i + 1)
    my $add_node = Chalk::IR::Node->new(
        id => 'add_1',
        op => 'Add',
        inputs => [$phi->id, 'const_1'],
        attributes => {},
    );
    $graph->add_node($add_node);

    # with_binding should update the phi's backedge
    my $updated_scope = $loop_scope->with_binding('$i', $add_node);

    # Check that the phi now has the backedge value
    my @inputs = $phi->inputs->@*;
    is(scalar(@inputs), 3, 'Phi now has 3 inputs (region, init, backedge)');
    is($inputs[2], $add_node->id, 'Phi backedge is the new value');
};

# Test 6: Nested loops create phis at correct level
subtest 'Nested loops create phis at correct nesting level' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => { '$i' => $const_0 },
        current_control => 'start_1',
    );

    # Outer loop
    my $outer_loop = Chalk::IR::Node->new(
        id => 'outer_loop',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($outer_loop);

    my $outer_scope = $scope->enter_loop($outer_loop);

    # Inner loop
    my $inner_loop = Chalk::IR::Node->new(
        id => 'inner_loop',
        op => 'Loop',
        inputs => [$outer_loop->id],
        attributes => {},
    );
    $graph->add_node($inner_loop);

    my $inner_scope = $outer_scope->enter_loop($inner_loop);

    # Lookup $i from inner loop - should create phi at outer loop level first
    my $phi = $inner_scope->lookup('$i');

    ok($phi, 'lookup returns a value from inner loop');
    is($phi->op, 'Phi', 'lookup returns a Phi node');

    # The phi should be associated with the correct loop level
    # (In Simple, this creates phis recursively at each level that needs them)
};

# Test 7: exit_loop cleans up unused sentinels
subtest 'exit_loop() replaces remaining sentinels with parent values' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $const_0 = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $const_10 = Chalk::IR::Node->new(
        id => 'const_10',
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    my $scope = Chalk::IR::Node::Scope->new(
        bindings => {
            '$i' => $const_0,
            '$n' => $const_10,  # Not accessed in loop
        },
        current_control => 'start_1',
    );

    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => ['start_1'],
        attributes => {},
    );
    $graph->add_node($loop);

    my $loop_scope = $scope->enter_loop($loop);

    # Only access $i
    my $phi_i = $loop_scope->lookup('$i');

    # Exit the loop
    my $exit_scope = $loop_scope->exit_loop();

    # $i should have the phi
    my $final_i = $exit_scope->lookup('$i');
    is($final_i->id, $phi_i->id, '$i lookup returns the phi after exit');

    # $n should have original value (sentinel replaced)
    my $final_n = $exit_scope->lookup('$n');
    is($final_n->id, $const_10->id, '$n lookup returns original value (not accessed in loop)');
};
