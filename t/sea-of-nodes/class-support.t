# ABOUTME: Test for Sea of Nodes IR generation - Class and object support (Issue #98 Phase 1)
# ABOUTME: Validates IR generation for class definitions, object instantiation, and field access

use lib 'lib';
use v5.42;
use lib 'lib';
use Test::More;
use lib 'lib';
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Builder');

# Test manual IR graph construction for a simple class
# This tests the IR infrastructure for Phase 1: Minimal class support
subtest 'Manual IR graph construction for class with fields' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node (entry point)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create ClassDef node for: class Point { field $x; field $y; }
    my $classdef = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'ClassDef',
        inputs => ['node_0'],  # Control dependency
        attributes => {
            name => 'Point',
            fields => ['x', 'y'],
        }
    );
    $graph->add_node($classdef);

    # Create constants for field values
    my $const_5 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 5, type => 'Int' }
    );
    $graph->add_node($const_5);

    my $const_10 = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 10, type => 'Int' }
    );
    $graph->add_node($const_10);

    # Create New node for: my $point = Point->new(x => 5, y => 10);
    my $new_obj = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'New',
        inputs => ['node_0', 'node_1', 'node_2', 'node_3'],  # Control, class, field values
        attributes => {
            class => 'Point',
            field_values => {
                x => { op => 'NodeRef', node_id => 'node_2' },
                y => { op => 'NodeRef', node_id => 'node_3' },
            }
        }
    );
    $graph->add_node($new_obj);

    # Create FieldAccess node for: $point->x
    my $field_access = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'FieldAccess',
        inputs => ['node_0', 'node_4'],  # Control, object
        attributes => {
            field => 'x',
            object => { op => 'NodeRef', node_id => 'node_4' }
        }
    );
    $graph->add_node($field_access);

    # Create Return node (returns the field value)
    my $return = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Return',
        inputs => ['node_0', 'node_5'],  # Control, data
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 7, 'Graph has 7 nodes');

    # Verify ClassDef node
    my $classdef_node = $graph->get_node('node_1');
    ok($classdef_node, 'ClassDef node exists');
    is($classdef_node->op, 'ClassDef', 'ClassDef node has correct op');
    is($classdef_node->attributes->{name}, 'Point', 'ClassDef has correct class name');
    cmp_deeply($classdef_node->attributes->{fields}, ['x', 'y'], 'ClassDef has correct fields');

    # Verify New node
    my $new_node = $graph->get_node('node_4');
    ok($new_node, 'New node exists');
    is($new_node->op, 'New', 'New node has correct op');
    is($new_node->attributes->{class}, 'Point', 'New node has correct class');
    ok(exists $new_node->attributes->{field_values}, 'New node has field_values');
    is($new_node->attributes->{field_values}{x}{node_id}, 'node_2', 'New node has x field value');
    is($new_node->attributes->{field_values}{y}{node_id}, 'node_3', 'New node has y field value');

    # Verify FieldAccess node
    my $access_node = $graph->get_node('node_5');
    ok($access_node, 'FieldAccess node exists');
    is($access_node->op, 'FieldAccess', 'FieldAccess node has correct op');
    is($access_node->attributes->{field}, 'x', 'FieldAccess has correct field name');
    is($access_node->attributes->{object}{node_id}, 'node_4', 'FieldAccess references correct object');
};

# Test IR Builder methods for class operations
subtest 'IR Builder methods for class support' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');
    is($start->op, 'Start', 'Builder creates Start node');

    # Build ClassDef node
    my $classdef = $builder->build_classdef_node('Point', ['x', 'y']);
    ok($classdef, 'Builder creates ClassDef node');
    is($classdef->op, 'ClassDef', 'ClassDef has correct op');
    is($classdef->attributes->{name}, 'Point', 'ClassDef has correct name');
    cmp_deeply($classdef->attributes->{fields}, ['x', 'y'], 'ClassDef has correct fields');

    # Build constants for field values
    my $const_5 = $builder->build_constant_node(5);
    my $const_10 = $builder->build_constant_node(10);

    # Build New node
    my $new_obj = $builder->build_new_node('Point', { x => $const_5, y => $const_10 });
    ok($new_obj, 'Builder creates New node');
    is($new_obj->op, 'New', 'New has correct op');
    is($new_obj->attributes->{class}, 'Point', 'New has correct class');

    # Build FieldAccess node
    my $field_access = $builder->build_field_access_node($new_obj, 'x');
    ok($field_access, 'Builder creates FieldAccess node');
    is($field_access->op, 'FieldAccess', 'FieldAccess has correct op');
    is($field_access->attributes->{field}, 'x', 'FieldAccess has correct field');

    # Verify all nodes are in the graph
    ok($graph->get_node($classdef->id), 'ClassDef in graph');
    ok($graph->get_node($new_obj->id), 'New in graph');
    ok($graph->get_node($field_access->id), 'FieldAccess in graph');
};

# Test FieldStore node for field assignment
subtest 'FieldStore node for field mutation' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create ClassDef
    my $classdef = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'ClassDef',
        inputs => ['node_0'],
        attributes => { name => 'Counter', fields => ['value'] }
    );
    $graph->add_node($classdef);

    # Create New with initial value
    my $const_0 = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 0, type => 'Int' }
    );
    $graph->add_node($const_0);

    my $new_obj = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'New',
        inputs => ['node_0', 'node_1', 'node_2'],
        attributes => {
            class => 'Counter',
            field_values => { value => { op => 'NodeRef', node_id => 'node_2' } }
        }
    );
    $graph->add_node($new_obj);

    # Create new value
    my $const_42 = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'Constant',
        inputs => ['node_0'],
        attributes => { value => 42, type => 'Int' }
    );
    $graph->add_node($const_42);

    # Create FieldStore node for: $counter->value = 42;
    my $field_store = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'FieldStore',
        inputs => ['node_0', 'node_3', 'node_4'],  # Control, object, value
        attributes => {
            field => 'value',
            object => { op => 'NodeRef', node_id => 'node_3' },
            value => { op => 'NodeRef', node_id => 'node_4' }
        }
    );
    $graph->add_node($field_store);

    # Verify FieldStore node
    my $store_node = $graph->get_node('node_5');
    ok($store_node, 'FieldStore node exists');
    is($store_node->op, 'FieldStore', 'FieldStore has correct op');
    is($store_node->attributes->{field}, 'value', 'FieldStore has correct field');
    is($store_node->attributes->{object}{node_id}, 'node_3', 'FieldStore references correct object');
    is($store_node->attributes->{value}{node_id}, 'node_4', 'FieldStore has correct value');
};

done_testing();
