#!/usr/bin/env perl
# ABOUTME: Test IR Builder variable loading using Reference->ref_read
# ABOUTME: Verify build_load_node integrates with Context+Heap for variable retrieval
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 9;
use Chalk::IR::Builder;
use Chalk::IR::Reference;

# Test 1: build_load_node retrieves stored variable
{
    my $builder = Chalk::IR::Builder->new();
    my $constant = $builder->build_constant_node(42);

    $builder->build_store_node('x', $constant);
    my $loaded = $builder->build_load_node('x');

    ok(defined($loaded), 'load returns a value for stored variable');
    is($loaded->id, $constant->id, 'loaded node matches stored node');
}

# Test 2: build_load_node returns undef for non-existent variable
{
    my $builder = Chalk::IR::Builder->new();

    my $loaded = $builder->build_load_node('nonexistent');

    is($loaded, undef, 'load returns undef for non-existent variable');
}

# Test 3: Multiple loads retrieve correct variables
{
    my $builder = Chalk::IR::Builder->new();
    my $const1 = $builder->build_constant_node(10);
    my $const2 = $builder->build_constant_node(20);
    my $const3 = $builder->build_constant_node(30);

    $builder->build_store_node('x', $const1);
    $builder->build_store_node('y', $const2);
    $builder->build_store_node('z', $const3);

    my $loaded_x = $builder->build_load_node('x');
    my $loaded_y = $builder->build_load_node('y');
    my $loaded_z = $builder->build_load_node('z');

    is($loaded_x->id, $const1->id, 'x loads correctly');
    is($loaded_y->id, $const2->id, 'y loads correctly');
    is($loaded_z->id, $const3->id, 'z loads correctly');
}

# Test 4: Load after rebinding gets latest value
{
    my $builder = Chalk::IR::Builder->new();
    my $const1 = $builder->build_constant_node('first');
    my $const2 = $builder->build_constant_node('second');

    $builder->build_store_node('x', $const1);
    my $loaded1 = $builder->build_load_node('x');
    is($loaded1->id, $const1->id, 'initial load gets first value');

    $builder->build_store_node('x', $const2);
    my $loaded2 = $builder->build_load_node('x');
    is($loaded2->id, $const2->id, 'load after rebinding gets latest value');
}

# Test 5: Load-store-load workflow
{
    my $builder = Chalk::IR::Builder->new();
    my $const_a = $builder->build_constant_node(100);
    my $const_b = $builder->build_constant_node(200);

    $builder->build_store_node('a', $const_a);
    my $loaded_a = $builder->build_load_node('a');

    $builder->build_store_node('b', $const_b);
    my $loaded_b = $builder->build_load_node('b');

    # Verify 'a' still loads correctly after 'b' is stored
    my $loaded_a_again = $builder->build_load_node('a');

    is($loaded_a_again->id, $const_a->id, 'original variable still loads correctly after new stores');
}
