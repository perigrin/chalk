#!/usr/bin/env perl
# ABOUTME: Test IR Builder variable storage using Reference->ref_new
# ABOUTME: Verify build_store_node integrates with Context+Heap for variable bindings
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 12;
use Chalk::IR::Builder;

# Test 1: build_store_node updates Builder's context
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(42);

    $builder->build_store_node('x', $constant);

    # After store, context should have binding for 'lexical:x'
    my $node_id = $builder->context->('lexical:x');
    ok(defined($node_id), 'context has binding for stored variable');
}

# Test 2: build_store_node stores node object in context
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(100);

    $builder->build_store_node('x', $constant);

    # After store, can read node object from context with lexical: label
    my $stored_node = $builder->context->('lexical:x');
    ok(defined($stored_node), 'context contains stored node object');
    is($stored_node->id, $constant->id, 'context stores correct node object');
}

# Test 3: Multiple stores create independent bindings
{
    my $builder = Chalk::IR::Builder->new();
    my $const1 = $builder->build_constant_node(10);
    my $const2 = $builder->build_constant_node(20);
    my $const3 = $builder->build_constant_node(30);

    $builder->build_store_node('x', $const1);
    $builder->build_store_node('y', $const2);
    $builder->build_store_node('z', $const3);

    my $x_node = $builder->context->('lexical:x');
    my $y_node = $builder->context->('lexical:y');
    my $z_node = $builder->context->('lexical:z');

    is($x_node->id, $const1->id, 'x stores correct node object');
    is($y_node->id, $const2->id, 'y stores correct node object');
    is($z_node->id, $const3->id, 'z stores correct node object');
}

# Test 4: Store updates existing variable (rebinding)
{
    my $builder = Chalk::IR::Builder->new();
    my $const1 = $builder->build_constant_node('first');
    my $const2 = $builder->build_constant_node('second');

    $builder->build_store_node('x', $const1);
    my $initial_node = $builder->context->('lexical:x');
    is($initial_node->id, $const1->id, 'initial store works');

    $builder->build_store_node('x', $const2);
    my $updated_node = $builder->context->('lexical:x');
    is($updated_node->id, $const2->id, 'rebinding updates to new node object');
}

# Test 5: Store preserves other variables when rebinding
{
    my $builder = Chalk::IR::Builder->new();
    my $const_x = $builder->build_constant_node(100);
    my $const_y = $builder->build_constant_node(200);
    my $const_x2 = $builder->build_constant_node(999);

    $builder->build_store_node('x', $const_x);
    $builder->build_store_node('y', $const_y);
    $builder->build_store_node('x', $const_x2);  # Rebind x

    my $x_node = $builder->context->('lexical:x');
    my $y_node = $builder->context->('lexical:y');

    is($x_node->id, $const_x2->id, 'x rebinding works');
    is($y_node->id, $const_y->id, 'y unchanged after x rebinding');
}

# Test 6: build_store_node still returns value node (backward compatibility)
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(42);

    my $result = $builder->build_store_node('x', $constant);

    ok(defined($result), 'build_store_node returns a value');
    is($result->id, $constant->id, 'returns the stored value node');
}
