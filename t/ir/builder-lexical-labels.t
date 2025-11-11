#!/usr/bin/env perl
# ABOUTME: Test Builder uses lexical: labels in context for variables
# ABOUTME: Verify Builder stores and retrieves variables with proper namespace
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 4;
use Chalk::IR::Builder;

# Test 1: Builder stores variable with lexical: label
{
    my $builder = Chalk::IR::Builder->new();

    # Build: my $x = 42;
    $builder->build_start_node();
    my $const = $builder->build_constant_node(42);
    $builder->build_store_node('$x', $const);

    # Check that context contains 'lexical:$x'
    my $value = $builder->context->('lexical:$x');
    ok(defined($value), 'Builder stores variable with lexical: label');
}

# Test 2: Builder retrieves variable using lexical: label
{
    my $builder = Chalk::IR::Builder->new();

    # Build: my $x = 10; return $x;
    $builder->build_start_node();
    my $const = $builder->build_constant_node(10);
    $builder->build_store_node('$x', $const);
    my $loaded = $builder->build_load_node('$x');

    # The loaded node should reference the value stored at lexical:$x
    ok(defined($loaded), 'Builder can retrieve variable using lexical: label');
}

# Test 3: Multiple variables with different labels
{
    my $builder = Chalk::IR::Builder->new();

    $builder->build_start_node();
    my $const1 = $builder->build_constant_node(1);
    my $const2 = $builder->build_constant_node(2);
    $builder->build_store_node('$x', $const1);
    $builder->build_store_node('$y', $const2);

    # Both should be in context with lexical: prefix
    my $x_val = $builder->context->('lexical:$x');
    my $y_val = $builder->context->('lexical:$y');

    ok(defined($x_val), 'First variable stored with lexical: label');
    ok(defined($y_val), 'Second variable stored with lexical: label');
}
