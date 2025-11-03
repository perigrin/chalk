#!/usr/bin/env perl
# ABOUTME: Test that Context stores IR node objects, not node ID strings
# ABOUTME: Verify build_store_node stores nodes directly and build_load_node returns them
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 8;
use Chalk::IR::Builder;

# Test 1: build_store_node stores node object in context (not node ID string)
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(42);

    $builder->build_store_node('x', $constant);

    # Context should contain the node object itself
    my $stored_value = $builder->context->('lexical:x');
    ok(ref($stored_value), 'context stores an object, not a string');
    isa_ok($stored_value, 'Chalk::IR::Node::Constant', 'context stores IR node object');
}

# Test 2: Stored node object has correct value
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(100);

    $builder->build_store_node('x', $constant);

    my $stored_node = $builder->context->('lexical:x');
    is($stored_node->attributes->{value}, 100, 'stored node preserves value');
}

# Test 3: build_load_node returns node directly from context (no graph lookup)
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(42);

    $builder->build_store_node('x', $constant);
    my $loaded = $builder->build_load_node('x');

    # Loaded node should be the same object (not just same ID)
    is($loaded, $constant, 'load returns same node object from context');
}

# Test 4: Multiple variables store different node objects
{
    my $builder = Chalk::IR::Builder->new();
    my $const1 = $builder->build_constant_node(10);
    my $const2 = $builder->build_constant_node(20);

    $builder->build_store_node('x', $const1);
    $builder->build_store_node('y', $const2);

    my $loaded_x = $builder->context->('lexical:x');
    my $loaded_y = $builder->context->('lexical:y');

    is($loaded_x->attributes->{value}, 10, 'x stores correct node');
    is($loaded_y->attributes->{value}, 20, 'y stores correct node');
}

# Test 5: Rebinding updates to new node object
{
    my $builder = Chalk::IR::Builder->new();
    my $const1 = $builder->build_constant_node('first');
    my $const2 = $builder->build_constant_node('second');

    $builder->build_store_node('x', $const1);
    my $initial = $builder->context->('lexical:x');
    is($initial->attributes->{value}, 'first', 'initial binding works');

    $builder->build_store_node('x', $const2);
    my $updated = $builder->context->('lexical:x');
    is($updated->attributes->{value}, 'second', 'rebinding updates node object');
}
