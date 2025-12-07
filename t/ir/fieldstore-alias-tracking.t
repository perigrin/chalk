#!/usr/bin/env perl
# ABOUTME: Test FieldStore alias tracking and peephole optimizations with references
# ABOUTME: Validates store-after-load elimination and store-to-store bypassing

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node::NewObject;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::FieldLoad;
use Chalk::IR::Node::FieldStore;
use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::Type::Maybe;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::IR::Type::Integer;
use Chalk::IR::Graph;

subtest 'FieldStore: basic store to value field' => sub {
    # Set up the Point class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => {
            x => Chalk::IR::Type::Integer->new(),
            y => Chalk::IR::Type::Integer->new(),
        },
    );
    $registry->register('Point', $point_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create a Point object
    my $new_point = Chalk::IR::Node::NewObject->new(
        class_type => $point_class,
    );
    $graph->add_node($new_point);

    # Create constant for value
    my $value_42 = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->new(),
    );
    $graph->add_node($value_42);

    # Create field name constant
    my $field_x = Chalk::IR::Node::Constant->new(
        value => 'x',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_x);

    # Store value into x field
    my $store_x = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_point->id(), $field_x->id(), $value_42->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        value_id => $value_42->id(),
    );
    $graph->add_node($store_x);

    ok $store_x, 'Created FieldStore node';
    is $store_x->object_id(), $new_point->id(), 'Object ID is correct';
    is $store_x->field_id(), $field_x->id(), 'Field ID is correct';
    is $store_x->value_id(), $value_42->id(), 'Value ID is correct';
};

subtest 'FieldStore: store reference field' => sub {
    # Set up the Node class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $node_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => {
            value => Chalk::IR::Type::Integer->new(),
            next => Chalk::Grammar::Chalk::Type::Maybe->new(
                inner_type => Chalk::Grammar::Chalk::Type::Class->new(
                    class_name => 'Node',
                    fields => undef,
                ),
            ),
        },
    );
    $registry->register('Node', $node_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create two Node objects
    my $node1 = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($node1);

    my $node2 = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($node2);

    # Create field name constant
    my $field_next = Chalk::IR::Node::Constant->new(
        value => 'next',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_next);

    # Store node2 into node1.next
    my $store_next = Chalk::IR::Node::FieldStore->new(
        inputs => [$node1->id(), $field_next->id(), $node2->id()],
        object_id => $node1->id(),
        field_id => $field_next->id(),
        value_id => $node2->id(),
    );
    $graph->add_node($store_next);

    ok $store_next, 'Created FieldStore for reference field';
    is $store_next->value_id(), $node2->id(), 'Storing reference to node2';
};

subtest 'FieldStore peephole: store-after-load elimination' => sub {
    # Set up the Point class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => {
            x => Chalk::IR::Type::Integer->new(),
        },
    );
    $registry->register('Point', $point_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create a Point object
    my $new_point = Chalk::IR::Node::NewObject->new(
        class_type => $point_class,
    );
    $graph->add_node($new_point);

    # Create field name constant
    my $field_x = Chalk::IR::Node::Constant->new(
        value => 'x',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_x);

    # Load x field
    my $load_x = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_point->id(), $field_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        alias_class => 1,
    );
    $graph->add_node($load_x);

    # Store the loaded value back to the same field (redundant)
    my $store_x = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_point->id(), $field_x->id(), $load_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        value_id => $load_x->id(),  # Storing what we just loaded
        mem_id => $load_x->id(),
        alias_class => 1,
    );
    $graph->add_node($store_x);

    # Run peephole optimization
    my $optimized = $store_x->peephole($graph);

    # Should eliminate redundant store (return the load instead)
    ok $optimized, 'Peephole returned a node';
    is $optimized->id(), $load_x->id(), 'Store-after-load eliminated (returned load)';
    ok $optimized isa Chalk::IR::Node::FieldLoad, 'Optimized to FieldLoad';
};

subtest 'FieldStore peephole: consecutive stores handled correctly' => sub {
    # Set up the Point class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => {
            x => Chalk::IR::Type::Integer->new(),
        },
    );
    $registry->register('Point', $point_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create a Point object
    my $new_point = Chalk::IR::Node::NewObject->new(
        class_type => $point_class,
    );
    $graph->add_node($new_point);

    # Create constants
    my $field_x = Chalk::IR::Node::Constant->new(
        value => 'x',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_x);

    my $value_10 = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->new(),
    );
    $graph->add_node($value_10);

    my $value_20 = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->new(),
    );
    $graph->add_node($value_20);

    # First store: x = 10
    my $store1 = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_point->id(), $field_x->id(), $value_10->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        value_id => $value_10->id(),
        alias_class => 1,
    );
    $graph->add_node($store1);

    # Second store: x = 20 (overwrites first store)
    my $store2 = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_point->id(), $field_x->id(), $value_20->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        value_id => $value_20->id(),
        mem_id => $store1->id(),  # Depends on first store
        alias_class => 1,
    );
    $graph->add_node($store2);

    # Run peephole optimization on second store
    my $optimized = $store2->peephole($graph);

    # Peephole should at minimum not crash and preserve correctness
    ok $optimized, 'Peephole returned a node';
    ok $optimized isa Chalk::IR::Node::FieldStore, 'Still a FieldStore';
    is $optimized->value_id(), $value_20->id(), 'Still storing value 20';
    is $optimized->object_id(), $new_point->id(), 'Still storing to same object';
};

subtest 'FieldStore peephole: no store-to-store bypass with multiple uses' => sub {
    # Set up the Point class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => {
            x => Chalk::IR::Type::Integer->new(),
        },
    );
    $registry->register('Point', $point_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create a Point object
    my $new_point = Chalk::IR::Node::NewObject->new(
        class_type => $point_class,
    );
    $graph->add_node($new_point);

    # Create constants
    my $field_x = Chalk::IR::Node::Constant->new(
        value => 'x',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_x);

    my $value_10 = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->new(),
    );
    $graph->add_node($value_10);

    my $value_20 = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->new(),
    );
    $graph->add_node($value_20);

    # First store: x = 10
    my $store1 = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_point->id(), $field_x->id(), $value_10->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        value_id => $value_10->id(),
        alias_class => 1,
    );
    $graph->add_node($store1);

    # Second store: x = 20
    my $store2 = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_point->id(), $field_x->id(), $value_20->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        value_id => $value_20->id(),
        mem_id => $store1->id(),
        alias_class => 1,
    );
    $graph->add_node($store2);

    # Create a dummy FieldLoad that uses store1 (to give it multiple uses)
    my $dummy_load = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_point->id(), $field_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        mem_id => $store1->id(),  # This creates a use of store1
        alias_class => 1,
    );
    $graph->add_node($dummy_load);

    # Now store1 has TWO uses: store2 and dummy_load

    # Run peephole optimization
    my $optimized = $store2->peephole($graph);

    # Should NOT bypass because store1 has multiple uses
    ok $optimized, 'Peephole returned a node';
    is $optimized->id(), $store2->id(), 'No bypass with multiple uses';
    is $optimized->mem_id(), $store1->id(), 'mem_id unchanged';
};

subtest 'FieldStore: execute stores reference in heap' => sub {
    # Set up the Node class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $node_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => {
            value => Chalk::IR::Type::Integer->new(),
            next => Chalk::Grammar::Chalk::Type::Maybe->new(
                inner_type => Chalk::Grammar::Chalk::Type::Class->new(
                    class_name => 'Node',
                    fields => undef,
                ),
            ),
        },
    );
    $registry->register('Node', $node_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create two Node objects
    my $node1 = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($node1);

    my $node2 = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($node2);

    # Create field name constant
    my $field_next = Chalk::IR::Node::Constant->new(
        value => 'next',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_next);

    # Store node2 into node1.next
    my $store_next = Chalk::IR::Node::FieldStore->new(
        inputs => [$node1->id(), $field_next->id(), $node2->id()],
        object_id => $node1->id(),
        field_id => $field_next->id(),
        value_id => $node2->id(),
    );
    $graph->add_node($store_next);

    # Create environment and context
    use Chalk::Interpreter::Environment;
    my $env = Chalk::Interpreter::Environment->new();
    my $context;
    $context = sub {
        my $key = shift;
        if ($key eq 'env:') {
            return $env;
        }
        elsif ($key =~ /^node:(\d+)$/) {
            my $node_id = $1;

            # Check if result is already cached
            my $cached = $env->lookup_node($node_id);
            return $cached if defined $cached;

            # Execute and cache the result
            my $node = $graph->get_node($node_id);
            if ($node) {
                my $result = $node->execute($context);
                $env->set_node($node_id, $result);
                return $result;
            }
        }
        elsif ($key =~ /^graph:(\d+)$/) {
            my $node_id = $1;
            return $graph->get_node($node_id);
        }
        return undef;
    };

    # Execute nodes and cache results
    my $heap_id1 = $node1->execute($context);
    $env->set_node($node1->id(), $heap_id1);

    my $heap_id2 = $node2->execute($context);
    $env->set_node($node2->id(), $heap_id2);

    ok defined($heap_id1), 'node1 allocated';
    ok defined($heap_id2), 'node2 allocated';

    # Execute store
    my $result = $store_next->execute($context);
    is $result, $heap_id1, 'FieldStore returns object heap ID';

    # Verify the reference was stored
    my $stored_next = $env->lookup_heap($heap_id1, 'next');
    is $stored_next, $heap_id2, 'Reference to node2 stored in node1.next';
};
