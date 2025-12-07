#!/usr/bin/env perl
# ABOUTME: Test FieldLoad support for chained field access through nullable references
# ABOUTME: Validates loading fields through reference chains and null-safety

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
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::IR::Type::Integer;
use Chalk::IR::Graph;
use Chalk::IR::Context;
use Chalk::Interpreter::Environment;

subtest 'FieldLoad: simple field access from object' => sub {
    # Set up the class
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

    # Create a new Point object
    my $new_point = Chalk::IR::Node::NewObject->new(
        class_type => $point_class,
    );
    $graph->add_node($new_point);

    # Create field name constant
    use Chalk::Grammar::Chalk::Type::Str;
    my $field_x = Chalk::IR::Node::Constant->new(
        value => 'x',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_x);

    # Create FieldLoad for x field
    my $load_x = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_point->id(), $field_x->id()],
        object_id => $new_point->id(),
        field_id => $field_x->id(),
    );
    $graph->add_node($load_x);

    ok $load_x, 'Created FieldLoad node';
    is $load_x->object_id(), $new_point->id(), 'Object ID is correct';
    is $load_x->field_id(), $field_x->id(), 'Field ID is correct';
};

subtest 'FieldLoad: nullable reference field' => sub {
    # Set up the Node class with nullable next field
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $node_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => {
            value => Chalk::IR::Type::Integer->new(),
            next => Chalk::Grammar::Chalk::Type::Maybe->new(
                inner_type => Chalk::Grammar::Chalk::Type::Class->new(
                    class_name => 'Node',
                    fields => undef,  # Forward reference
                ),
            ),
        },
    );
    $registry->register('Node', $node_class);

    # Create graph
    my $graph = Chalk::IR::Graph->new();

    # Create a new Node object
    my $new_node = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($new_node);

    # Create field name constant
    use Chalk::Grammar::Chalk::Type::Str;
    my $field_next = Chalk::IR::Node::Constant->new(
        value => 'next',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_next);

    # Create FieldLoad for next field (nullable)
    my $load_next = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_node->id(), $field_next->id()],
        object_id => $new_node->id(),
        field_id => $field_next->id(),
    );
    $graph->add_node($load_next);

    ok $load_next, 'Created FieldLoad for nullable field';
    is $load_next->object_id(), $new_node->id(), 'Object ID is correct';
    is $load_next->field_id(), $field_next->id(), 'Field ID is correct';
};

subtest 'FieldLoad: execute returns null for uninitialized reference' => sub {
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

    # Create a new Node object (next will be initialized to null)
    my $new_node = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($new_node);

    # Create field name constant
    use Chalk::Grammar::Chalk::Type::Str;
    my $field_next = Chalk::IR::Node::Constant->new(
        value => 'next',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_next);

    # Create FieldLoad for next field
    my $load_next = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_node->id(), $field_next->id()],
        object_id => $new_node->id(),
        field_id => $field_next->id(),
    );
    $graph->add_node($load_next);

    # Create environment and context
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

    # Execute NewObject to allocate and initialize the node
    my $heap_id = $new_node->execute($context);
    ok defined($heap_id), 'NewObject returned heap ID';

    # Execute FieldLoad to get the next field (should be null)
    my $next_value = $load_next->execute($context);
    is $next_value, undef, 'Loading uninitialized reference field returns null';
};

subtest 'FieldLoad: chained field access through reference' => sub {
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

    # Create field name constants
    use Chalk::Grammar::Chalk::Type::Str;
    my $field_value = Chalk::IR::Node::Constant->new(
        value => 'value',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_value);

    my $field_next = Chalk::IR::Node::Constant->new(
        value => 'next',
        type => Chalk::Grammar::Chalk::Type::Str->new(),
    );
    $graph->add_node($field_next);

    # Store value in node2
    my $value_const = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->new(),
    );
    $graph->add_node($value_const);

    my $store_value = Chalk::IR::Node::FieldStore->new(
        inputs => [$node2->id(), $field_value->id(), $value_const->id()],
        object_id => $node2->id(),
        field_id => $field_value->id(),
        value_id => $value_const->id(),
    );
    $graph->add_node($store_value);

    # Link node1.next -> node2
    my $store_next = Chalk::IR::Node::FieldStore->new(
        inputs => [$node1->id(), $field_next->id(), $node2->id()],
        object_id => $node1->id(),
        field_id => $field_next->id(),
        value_id => $node2->id(),
    );
    $graph->add_node($store_next);

    # Load node1.next
    my $load_next = Chalk::IR::Node::FieldLoad->new(
        inputs => [$node1->id(), $field_next->id()],
        object_id => $node1->id(),
        field_id => $field_next->id(),
    );
    $graph->add_node($load_next);

    # Load node1.next.value (chained access)
    my $load_next_value = Chalk::IR::Node::FieldLoad->new(
        inputs => [$load_next->id(), $field_value->id()],
        object_id => $load_next->id(),
        field_id => $field_value->id(),
    );
    $graph->add_node($load_next_value);

    # Create environment and context
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

    # Execute the graph to set up the chain
    $node1->execute($context);
    $node2->execute($context);
    $store_value->execute($context);
    $store_next->execute($context);

    # Now execute the chained load: node1.next.value
    my $chained_value = $load_next_value->execute($context);
    is $chained_value, 42, 'Chained field access returns correct value';
};
