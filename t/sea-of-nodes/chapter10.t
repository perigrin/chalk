#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 10 - Memory Operations and Objects
# ABOUTME: Validates Load/Store nodes, memory state, and object field access

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Graph;

subtest 'Store node basic structure' => sub {
    # store x = 42
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_42 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );
    $graph->add_node($const_42);

    # Store: control input, memory state, value, address/name
    my $store = Chalk::IR::Node->new(
        id => 3,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_42->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store);

    is $store->op, 'Store', 'Store node created';
    is scalar($store->inputs->@*), 3, 'Store has control, memory, and value inputs';
    is $store->attributes->{name}, 'x', 'Store has variable name';
};

subtest 'Load node basic structure' => sub {
    # y = load x
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Assume x was stored previously (memory state from store)
    my $store_state = 2;  # ID of previous store

    # Load: control input, memory state, address/name
    my $load = Chalk::IR::Node->new(
        id => 3,
        op => 'Load',
        inputs => [$start->id, $store_state],
        attributes => { name => 'x' },
    );
    $graph->add_node($load);

    is $load->op, 'Load', 'Load node created';
    is scalar($load->inputs->@*), 2, 'Load has control and memory inputs';
    is $load->attributes->{name}, 'x', 'Load has variable name';
};

subtest 'Store then Load: data dependency' => sub {
    # x = 10; y = x;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_10 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    # Store x = 10
    my $store_x = Chalk::IR::Node->new(
        id => 3,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_10->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store_x);

    # Load x (depends on store)
    my $load_x = Chalk::IR::Node->new(
        id => 4,
        op => 'Load',
        inputs => [$start->id, $store_x->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($load_x);

    # Load's memory input points to Store
    is $load_x->inputs->[1], $store_x->id, 'Load depends on Store for memory state';
};

subtest 'Multiple stores: memory state chain' => sub {
    # x = 1; y = 2; z = 3;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_1 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $const_2 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 2 },
    );
    $graph->add_node($const_2);

    my $const_3 = Chalk::IR::Node->new(
        id => 4,
        op => 'Constant',
        inputs => [],
        attributes => { value => 3 },
    );
    $graph->add_node($const_3);

    # Store x = 1 (initial memory state from Start)
    my $store_x = Chalk::IR::Node->new(
        id => 5,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_1->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store_x);

    # Store y = 2 (memory state from store_x)
    my $store_y = Chalk::IR::Node->new(
        id => 6,
        op => 'Store',
        inputs => [$start->id, $store_x->id, $const_2->id],
        attributes => { name => 'y' },
    );
    $graph->add_node($store_y);

    # Store z = 3 (memory state from store_y)
    my $store_z = Chalk::IR::Node->new(
        id => 7,
        op => 'Store',
        inputs => [$start->id, $store_y->id, $const_3->id],
        attributes => { name => 'z' },
    );
    $graph->add_node($store_z);

    # Memory state chains through stores
    is $store_y->inputs->[1], $store_x->id, 'Second store depends on first';
    is $store_z->inputs->[1], $store_y->id, 'Third store depends on second';
};

subtest 'Object field access: load/store with field names' => sub {
    # obj.x = 5; y = obj.x;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $obj_ref = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 'obj_address' },
    );
    $graph->add_node($obj_ref);

    my $const_5 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 5 },
    );
    $graph->add_node($const_5);

    # Store to field: control, memory, value, object, field
    my $store_field = Chalk::IR::Node->new(
        id => 4,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_5->id, $obj_ref->id],
        attributes => { field => 'x' },
    );
    $graph->add_node($store_field);

    # Load from field: control, memory, object
    my $load_field = Chalk::IR::Node->new(
        id => 5,
        op => 'Load',
        inputs => [$start->id, $store_field->id, $obj_ref->id],
        attributes => { field => 'x' },
    );
    $graph->add_node($load_field);

    is $store_field->attributes->{field}, 'x', 'Store has field name';
    is $load_field->attributes->{field}, 'x', 'Load has field name';
    ok $store_field->inputs->[3], 'Store has object reference';
    ok $load_field->inputs->[2], 'Load has object reference';
};

subtest 'Array access: load/store with index' => sub {
    # arr[i] = 10; x = arr[i];
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $arr_ref = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 'array_address' },
    );
    $graph->add_node($arr_ref);

    my $index = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 5 },
    );
    $graph->add_node($index);

    my $const_10 = Chalk::IR::Node->new(
        id => 4,
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    # Store to array: control, memory, value, array, index
    my $store_array = Chalk::IR::Node->new(
        id => 5,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_10->id, $arr_ref->id, $index->id],
        attributes => { type => 'array' },
    );
    $graph->add_node($store_array);

    # Load from array: control, memory, array, index
    my $load_array = Chalk::IR::Node->new(
        id => 6,
        op => 'Load',
        inputs => [$start->id, $store_array->id, $arr_ref->id, $index->id],
        attributes => { type => 'array' },
    );
    $graph->add_node($load_array);

    is scalar($store_array->inputs->@*), 5, 'Array store has 5 inputs';
    is scalar($load_array->inputs->@*), 4, 'Array load has 4 inputs';
    is $store_array->attributes->{type}, 'array', 'Store marked as array access';
};

subtest 'Memory phi: merging memory states at control flow join' => sub {
    # if (cond) { x = 1; } else { x = 2; } y = x;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $cond = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($cond);

    my $if_node = Chalk::IR::Node->new(
        id => 3,
        op => 'If',
        inputs => [$start->id, $cond->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    my $if_true = Chalk::IR::Node->new(
        id => 4,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 0 },
    );
    $graph->add_node($if_true);

    my $if_false = Chalk::IR::Node->new(
        id => 5,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 1 },
    );
    $graph->add_node($if_false);

    my $const_1 = Chalk::IR::Node->new(
        id => 6,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $const_2 = Chalk::IR::Node->new(
        id => 7,
        op => 'Constant',
        inputs => [],
        attributes => { value => 2 },
    );
    $graph->add_node($const_2);

    # True branch: x = 1
    my $store_true = Chalk::IR::Node->new(
        id => 8,
        op => 'Store',
        inputs => [$if_true->id, $start->id, $const_1->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store_true);

    # False branch: x = 2
    my $store_false = Chalk::IR::Node->new(
        id => 9,
        op => 'Store',
        inputs => [$if_false->id, $start->id, $const_2->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store_false);

    # Merge control
    my $merge_region = Chalk::IR::Node->new(
        id => 10,
        op => 'Region',
        inputs => [$if_true->id, $if_false->id],
        attributes => {},
    );
    $graph->add_node($merge_region);

    # Memory phi: merges memory states from both branches
    my $mem_phi = Chalk::IR::Node->new(
        id => 11,
        op => 'Phi',
        inputs => [$merge_region->id, $store_true->id, $store_false->id],
        attributes => { type => 'memory' },
    );
    $graph->add_node($mem_phi);

    # Load uses merged memory state
    my $load_x = Chalk::IR::Node->new(
        id => 12,
        op => 'Load',
        inputs => [$merge_region->id, $mem_phi->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($load_x);

    is $mem_phi->op, 'Phi', 'Memory phi created';
    is scalar($mem_phi->inputs->@*), 3, 'Memory phi has control and two memory states';
    is $load_x->inputs->[1], $mem_phi->id, 'Load uses merged memory state';
};

subtest 'Store to same variable twice: last store wins' => sub {
    # x = 1; x = 2; y = x;  (y should be 2)
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_1 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $const_2 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 2 },
    );
    $graph->add_node($const_2);

    # First store: x = 1
    my $store1 = Chalk::IR::Node->new(
        id => 4,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_1->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store1);

    # Second store: x = 2 (overwrites first)
    my $store2 = Chalk::IR::Node->new(
        id => 5,
        op => 'Store',
        inputs => [$start->id, $store1->id, $const_2->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store2);

    # Load: should get value from store2
    my $load_x = Chalk::IR::Node->new(
        id => 6,
        op => 'Load',
        inputs => [$start->id, $store2->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($load_x);

    is $load_x->inputs->[1], $store2->id, 'Load uses most recent store';
};

subtest 'Memory aliasing: different variables' => sub {
    # x = 1; y = 2; a = x; b = y;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_1 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $const_2 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 2 },
    );
    $graph->add_node($const_2);

    # Store x = 1
    my $store_x = Chalk::IR::Node->new(
        id => 4,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_1->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store_x);

    # Store y = 2
    my $store_y = Chalk::IR::Node->new(
        id => 5,
        op => 'Store',
        inputs => [$start->id, $store_x->id, $const_2->id],
        attributes => { name => 'y' },
    );
    $graph->add_node($store_y);

    # Load x (after both stores)
    my $load_x = Chalk::IR::Node->new(
        id => 6,
        op => 'Load',
        inputs => [$start->id, $store_y->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($load_x);

    # Load y
    my $load_y = Chalk::IR::Node->new(
        id => 7,
        op => 'Load',
        inputs => [$start->id, $store_y->id],
        attributes => { name => 'y' },
    );
    $graph->add_node($load_y);

    # Both loads use same memory state (store_y)
    # But they load different variables
    is $load_x->inputs->[1], $store_y->id, 'Load x uses final memory state';
    is $load_y->inputs->[1], $store_y->id, 'Load y uses final memory state';
    isnt $load_x->attributes->{name}, $load_y->attributes->{name}, 'Different variable names';
};

subtest 'JSON serialization with Load/Store' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_42 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );
    $graph->add_node($const_42);

    my $store = Chalk::IR::Node->new(
        id => 3,
        op => 'Store',
        inputs => [$start->id, $start->id, $const_42->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($store);

    my $load = Chalk::IR::Node->new(
        id => 4,
        op => 'Load',
        inputs => [$start->id, $store->id],
        attributes => { name => 'x' },
    );
    $graph->add_node($load);

    my $json = $graph->to_json();

    my $has_store = scalar(grep { $_->{op} eq 'Store' } $json->{nodes}->@*);
    my $has_load = scalar(grep { $_->{op} eq 'Load' } $json->{nodes}->@*);

    ok $has_store, 'Store node in JSON';
    ok $has_load, 'Load node in JSON';
};
