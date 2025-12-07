#!/usr/bin/env perl
# ABOUTME: Test NewObject support for class instances with reference fields
# ABOUTME: Validates initialization of reference fields to null and memory allocation

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

subtest 'NewObject: basic allocation without class type' => sub {
    # Existing behavior - no class type specified
    my $new_obj = Chalk::IR::Node::NewObject->new();

    ok $new_obj, 'Created NewObject node';
    is $new_obj->op(), 'NewObject', 'Op is NewObject';
    ok !defined($new_obj->class_type()), 'No class type specified';
};

subtest 'NewObject: with class type (no reference fields)' => sub {
    # Register a simple class with no reference fields
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

    # Create NewObject with class type
    my $new_point = Chalk::IR::Node::NewObject->new(
        class_type => $point_class,
    );

    ok $new_point, 'Created NewObject with class type';
    ok defined($new_point->class_type()), 'Class type is defined';
    is $new_point->class_type()->class_name(), 'Point', 'Class type is Point';
};

subtest 'NewObject: with reference fields auto-initialized to null' => sub {
    # Register a class with reference fields
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Node class has reference to next
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

    # Create NewObject with reference field
    my $new_node = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );

    ok $new_node, 'Created NewObject with reference field';
    ok defined($new_node->class_type()), 'Class type is defined';

    # Check that it will initialize the 'next' field to null
    my $init_fields = $new_node->initialized_fields();
    ok exists($init_fields->{next}), "'next' field is in initialization map";

    # The initialized value should be a null constant
    my $next_init = $init_fields->{next};
    ok $next_init isa Chalk::IR::Node::Constant, "Initialized value is a Constant node";
    is $next_init->value(), undef, "Initialized value is undef (null)";
    ok $next_init->type() isa Chalk::Grammar::Chalk::Type::Maybe, "Initialized type is Maybe";
};

subtest 'NewObject: execute initializes reference fields in heap' => sub {
    # Set up the class
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

    # Create graph and NewObject node
    my $graph = Chalk::IR::Graph->new();
    my $new_node = Chalk::IR::Node::NewObject->new(
        class_type => $node_class,
    );
    $graph->add_node($new_node);

    # Create environment for execution
    use Chalk::Interpreter::Environment;
    my $env = Chalk::Interpreter::Environment->new();

    # Create context (declare first for recursion)
    my $context;
    $context = sub {
        my $key = shift;
        if ($key eq 'env:') {
            return $env;
        }
        elsif ($key =~ /^node:(\d+)$/) {
            my $node_id = $1;
            my $node = $graph->get_node($node_id);
            return $node->execute($context) if $node;
        }
        elsif ($key =~ /^graph:(\d+)$/) {
            my $node_id = $1;
            return $graph->get_node($node_id);
        }
        return undef;
    };

    # Execute NewObject
    my $heap_id = $new_node->execute($context);

    ok defined($heap_id), 'NewObject returned a heap ID';

    # Verify that 'next' field is initialized to null in the heap
    my $next_value = $env->lookup_heap($heap_id, 'next');
    is $next_value, undef, "'next' field is initialized to undef (null)";
};
