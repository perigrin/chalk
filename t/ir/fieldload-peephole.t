#!/usr/bin/env perl
# ABOUTME: Test FieldLoad peephole optimizations for load-after-store with references
# ABOUTME: Validates that FieldLoad.peephole() optimizes redundant loads after stores

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

subtest 'FieldLoad peephole: load-after-store forwarding for value field' => sub {
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
        alias_class => 1,  # Alias class for optimization tracking
    );
    $graph->add_node($store_x);

    # Load the x field immediately after storing (should be optimized)
    my $load_x = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_point->id(), $field_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        mem_id => $store_x->id(),  # Depends on the store
        alias_class => 1,  # Same alias class
    );
    $graph->add_node($load_x);

    # Run peephole optimization
    my $optimized = $load_x->peephole($graph);

    # Should forward directly to the stored value (constant 42)
    ok $optimized, 'Peephole returned a node';
    is $optimized->id(), $value_42->id(), 'Load-after-store forwarded to stored value';
    ok $optimized isa Chalk::IR::Node::Constant, 'Optimized to constant';
    is $optimized->value(), 42, 'Value is correct';
};

subtest 'FieldLoad peephole: load-after-store with different alias classes (no optimization)' => sub {
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
        alias_class => 1,
    );
    $graph->add_node($store_x);

    # Load with different alias class (conservative - may alias with other stores)
    my $load_x = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_point->id(), $field_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        mem_id => $store_x->id(),
        alias_class => 2,  # Different alias class!
    );
    $graph->add_node($load_x);

    # Run peephole optimization
    my $optimized = $load_x->peephole($graph);

    # Should NOT optimize due to alias class mismatch
    is $optimized->id(), $load_x->id(), 'No optimization with different alias classes';
    ok $optimized isa Chalk::IR::Node::FieldLoad, 'Still a FieldLoad';
};

subtest 'FieldLoad peephole: load-after-store for reference field' => sub {
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
        alias_class => 1,
    );
    $graph->add_node($store_next);

    # Load node1.next immediately after (should forward to node2)
    my $load_next = Chalk::IR::Node::FieldLoad->new(
        inputs => [$node1->id(), $field_next->id()],
        object_id => $node1->id(),
        field_id => $field_next->id(),
        mem_id => $store_next->id(),
        alias_class => 1,
    );
    $graph->add_node($load_next);

    # Run peephole optimization
    my $optimized = $load_next->peephole($graph);

    # Should forward to node2
    ok $optimized, 'Peephole returned a node';
    is $optimized->id(), $node2->id(), 'Load-after-store forwarded to stored reference';
    ok $optimized isa Chalk::IR::Node::NewObject, 'Optimized to NewObject node';
};

subtest 'FieldLoad peephole: no optimization without mem_id' => sub {
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

    # Load without any memory dependency
    my $load_x = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_point->id(), $field_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
        # No mem_id - independent load
    );
    $graph->add_node($load_x);

    # Run peephole optimization
    my $optimized = $load_x->peephole($graph);

    # Should not optimize (returns self)
    is $optimized->id(), $load_x->id(), 'No optimization without mem_id';
    ok $optimized isa Chalk::IR::Node::FieldLoad, 'Still a FieldLoad';
};
