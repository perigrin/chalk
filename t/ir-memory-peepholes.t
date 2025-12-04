#!/usr/bin/env perl
# ABOUTME: Tests memory peephole optimizations for FieldStore/FieldLoad nodes
# ABOUTME: Verifies Store-Store elimination, Load-after-Store forwarding, and Store-after-Load elimination
use 5.42.0;
use lib 'lib';
use Test::More tests => 5;
use Chalk::IR::Graph;
use Chalk::IR::Node::NewObject;
use Chalk::IR::Node::FieldLoad;
use Chalk::IR::Node::FieldStore;
use Chalk::IR::Node::Constant;

# Test 1: Store-to-Store Elimination
# When two stores write to the same field with no intervening read,
# the first store is dead and should be eliminated
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new(inputs => []);
    my $field = Chalk::IR::Node::Constant->new(value => 'x', type => 'string');
    my $value1 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $value2 = Chalk::IR::Node::Constant->new(value => 20, type => 'int');

    # First store: obj.x = 10
    my $store1 = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field->id, $value1->id],
        mem_id => undef,  # No previous memory state
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $value1->id,
        alias_class => 1,
    );

    # Second store: obj.x = 20 (immediately after first store)
    my $store2 = Chalk::IR::Node::FieldStore->new(
        inputs => [$store1->id, $field->id, $value2->id],
        mem_id => $store1->id,  # Memory dependency on first store
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $value2->id,
        alias_class => 1,  # Same alias class
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($value1);
    $graph->add_node($value2);
    $graph->add_node($store1);
    $graph->add_node($store2);

    # Before peephole: store2 depends on store1
    is($store2->mem_id, $store1->id, 'Store2 initially depends on Store1');

    # Apply peephole optimization
    my $optimized = $store2->peephole($graph);

    # After peephole: store2 should bypass store1 (store1 is dead)
    # The optimized store should skip the intermediate store
    if ($optimized && $optimized != $store2) {
        # Optimization created a new node bypassing store1
        ok(1, 'Store-to-Store elimination created optimized node');
    } else {
        # TODO: This will fail until we implement the peephole
        fail('Store-to-Store elimination not yet implemented');
    }
}

# Test 2: Load-after-Store Forwarding
# When a load reads from a location just written, forward the stored value
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new(inputs => []);
    my $field = Chalk::IR::Node::Constant->new(value => 'x', type => 'string');
    my $value = Chalk::IR::Node::Constant->new(value => 42, type => 'int');

    # Store: obj.x = 42
    my $store = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field->id, $value->id],
        mem_id => undef,
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $value->id,
        alias_class => 1,
    );

    # Load: y = obj.x (immediately after store)
    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs => [$store->id, $field->id],
        mem_id => $store->id,  # Memory dependency on store
        object_id => $new_obj->id,
        field_id => $field->id,
        alias_class => 1,  # Same alias class
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($value);
    $graph->add_node($store);
    $graph->add_node($load);

    # Before peephole: load depends on store
    is($load->mem_id, $store->id, 'Load initially depends on Store');

    # Apply peephole optimization
    my $optimized = $load->peephole($graph);

    # After peephole: load should be replaced with the stored value (Constant 42)
    if ($optimized && $optimized->isa('Chalk::IR::Node::Constant')) {
        is($optimized->value, 42, 'Load-after-Store forwarding returns stored value');
    } else {
        # TODO: This will fail until we implement the peephole
        fail('Load-after-Store forwarding not yet implemented');
    }
}

# Test 3: Store-after-Load Elimination
# When storing the same value that was just loaded, the store is redundant
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new(inputs => []);
    my $field = Chalk::IR::Node::Constant->new(value => 'x', type => 'string');

    # Initial store: obj.x = 99 (to set up initial state)
    my $initial_value = Chalk::IR::Node::Constant->new(value => 99, type => 'int');
    my $initial_store = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field->id, $initial_value->id],
        mem_id => undef,
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $initial_value->id,
        alias_class => 1,
    );

    # Load: y = obj.x
    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs => [$initial_store->id, $field->id],
        mem_id => $initial_store->id,
        object_id => $new_obj->id,
        field_id => $field->id,
        alias_class => 1,
    );

    # Store back the same value: obj.x = y (redundant!)
    my $redundant_store = Chalk::IR::Node::FieldStore->new(
        inputs => [$load->id, $field->id, $load->id],  # Storing the loaded value
        mem_id => $load->id,
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $load->id,  # Value is the load itself
        alias_class => 1,
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($initial_value);
    $graph->add_node($initial_store);
    $graph->add_node($load);
    $graph->add_node($redundant_store);

    # Apply peephole optimization
    my $optimized = $redundant_store->peephole($graph);

    # After peephole: redundant store should be eliminated
    # (This is a more advanced optimization - may not implement immediately)
    if ($optimized && $optimized == $load) {
        ok(1, 'Store-after-Load elimination removed redundant store');
    } else {
        # TODO: This will fail until we implement the peephole
        fail('Store-after-Load elimination not yet implemented');
    }
}
