#!/usr/bin/env perl
# ABOUTME: Tests field operation type computation with alias classes
# ABOUTME: Verifies FieldLoad/FieldStore compute() returns correct Memory types
use 5.42.0;
use lib 'lib';
use Test::More tests => 8;
use Chalk::IR::Graph;
use Chalk::IR::Node::NewObject;
use Chalk::IR::Node::FieldLoad;
use Chalk::IR::Node::FieldStore;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Memory;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Top;

# Test 1: FieldStore compute() returns Memory type with alias_class
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new();
    my $field = Chalk::IR::Node::Constant->new(value => 'x', type => Chalk::IR::Type::Top->top());
    my $value = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->TOP());

    # Field "x" assigned alias_class 1
    my $store = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field->id, $value->id],
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $value->id,
        alias_class => 1,
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($value);
    $graph->add_node($store);

    my $type = $store->compute($graph);

    isa_ok($type, 'Chalk::IR::Type::Memory', 'FieldStore compute() returns Memory type');
    is($type->alias_class, 1, 'Memory type has correct alias_class');
}

# Test 2: FieldLoad compute() returns Memory type with alias_class
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new();
    my $field = Chalk::IR::Node::Constant->new(value => 'y', type => Chalk::IR::Type::Top->top());

    # Field "y" assigned alias_class 2
    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs => [$new_obj->id, $field->id],
        object_id => $new_obj->id,
        field_id => $field->id,
        alias_class => 2,
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($load);

    my $type = $load->compute($graph);

    isa_ok($type, 'Chalk::IR::Type::Memory', 'FieldLoad compute() returns Memory type');
    is($type->alias_class, 2, 'Memory type has correct alias_class');
}

# Test 3: Different fields have different alias classes
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new();
    my $field_x = Chalk::IR::Node::Constant->new(value => 'x', type => Chalk::IR::Type::Top->top());
    my $field_y = Chalk::IR::Node::Constant->new(value => 'y', type => Chalk::IR::Type::Top->top());
    my $value = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->TOP());

    my $store_x = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field_x->id, $value->id],
        object_id => $new_obj->id,
        field_id => $field_x->id,
        value_id => $value->id,
        alias_class => 1,
    );

    my $store_y = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field_y->id, $value->id],
        object_id => $new_obj->id,
        field_id => $field_y->id,
        value_id => $value->id,
        alias_class => 2,
    );

    $graph->add_node($new_obj);
    $graph->add_node($field_x);
    $graph->add_node($field_y);
    $graph->add_node($value);
    $graph->add_node($store_x);
    $graph->add_node($store_y);

    my $type_x = $store_x->compute($graph);
    my $type_y = $store_y->compute($graph);

    # Different fields don't alias
    my $meet = $type_x->meet($type_y);
    ok($meet->is_top, 'Different field alias classes meet to TOP (no aliasing)');
}

# Test 4: Same field across operations uses same alias class
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new();
    my $field = Chalk::IR::Node::Constant->new(value => 'x', type => Chalk::IR::Type::Top->top());
    my $value = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->TOP());

    my $store = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field->id, $value->id],
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $value->id,
        alias_class => 1,
    );

    my $load = Chalk::IR::Node::FieldLoad->new(
        inputs => [$store->id, $field->id],
        object_id => $store->id,
        field_id => $field->id,
        alias_class => 1,
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($value);
    $graph->add_node($store);
    $graph->add_node($load);

    my $store_type = $store->compute($graph);
    my $load_type = $load->compute($graph);

    # Same field CAN alias
    my $meet = $store_type->meet($load_type);
    is($meet->alias_class, 1, 'Same field alias classes meet to that class (can alias)');
}

# Test 5: Missing alias_class defaults to undefined (TOP)
{
    my $graph = Chalk::IR::Graph->new();
    my $new_obj = Chalk::IR::Node::NewObject->new();
    my $field = Chalk::IR::Node::Constant->new(value => 'x', type => Chalk::IR::Type::Top->top());
    my $value = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->TOP());

    # No alias_class specified
    my $store = Chalk::IR::Node::FieldStore->new(
        inputs => [$new_obj->id, $field->id, $value->id],
        object_id => $new_obj->id,
        field_id => $field->id,
        value_id => $value->id,
    );

    $graph->add_node($new_obj);
    $graph->add_node($field);
    $graph->add_node($value);
    $graph->add_node($store);

    my $type = $store->compute($graph);

    isa_ok($type, 'Chalk::IR::Type::Memory', 'FieldStore without alias_class returns Memory');
    ok(!defined($type->alias_class), 'Missing alias_class defaults to undefined (TOP)');
}
