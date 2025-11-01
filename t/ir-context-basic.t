#!/usr/bin/env perl
# ABOUTME: Test basic Context abstraction (context-as-closure pattern)
# ABOUTME: Verify empty_context, extend_context, and lookup operations work correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 20;
use Chalk::IR::Context;

# Test 1: empty_context returns a closure
{
    my $ctx = Chalk::IR::Context->empty_context();

    ok(ref($ctx) eq 'CODE', 'empty_context returns a code reference');
    is($ctx->('any-label'), undef, 'empty context returns undef for any label');
}

# Test 2: extend_context creates new context with single binding
{
    my $empty = Chalk::IR::Context->empty_context();
    my $ctx1 = Chalk::IR::Context->extend_context($empty, 'x', 42);

    ok(ref($ctx1) eq 'CODE', 'extend_context returns a code reference');
    is($ctx1->('x'), 42, 'extended context returns correct value for label');
    is($ctx1->('y'), undef, 'extended context returns undef for unknown label');
}

# Test 3: extend_context preserves parent bindings
{
    my $empty = Chalk::IR::Context->empty_context();
    my $ctx1 = Chalk::IR::Context->extend_context($empty, 'x', 10);
    my $ctx2 = Chalk::IR::Context->extend_context($ctx1, 'y', 20);

    is($ctx2->('x'), 10, 'child context finds parent binding');
    is($ctx2->('y'), 20, 'child context finds own binding');
    is($ctx2->('z'), undef, 'child context returns undef for unknown label');
}

# Test 4: extend_context shadows parent bindings
{
    my $empty = Chalk::IR::Context->empty_context();
    my $ctx1 = Chalk::IR::Context->extend_context($empty, 'x', 100);
    my $ctx2 = Chalk::IR::Context->extend_context($ctx1, 'x', 200);

    is($ctx2->('x'), 200, 'child binding shadows parent binding');
    is($ctx1->('x'), 100, 'parent context unchanged after extension');
}

# Test 5: context works with various value types
{
    my $empty = Chalk::IR::Context->empty_context();
    my $ctx = Chalk::IR::Context->extend_context($empty, 'str', 'hello');
    $ctx = Chalk::IR::Context->extend_context($ctx, 'num', 3.14);
    $ctx = Chalk::IR::Context->extend_context($ctx, 'ref', { key => 'value' });

    is($ctx->('str'), 'hello', 'context stores strings');
    is($ctx->('num'), 3.14, 'context stores numbers');
    is_deeply($ctx->('ref'), { key => 'value' }, 'context stores references');
}

# Test 6: namespaced labels prevent collisions
{
    my $empty = Chalk::IR::Context->empty_context();

    # Create labels with namespace helper
    my $var_x_label = Chalk::IR::Context->make_label('var', 'x');
    my $temp_x_label = Chalk::IR::Context->make_label('temp', 'x');

    # Add bindings with different namespaces but same name
    my $ctx = Chalk::IR::Context->extend_context($empty, $var_x_label, 100);
    $ctx = Chalk::IR::Context->extend_context($ctx, $temp_x_label, 200);

    # Verify namespace isolation
    is($ctx->($var_x_label), 100, 'var:x has correct value');
    is($ctx->($temp_x_label), 200, 'temp:x has correct value');
    is($ctx->('var:x'), 100, 'direct namespace lookup works');
    is($ctx->('temp:x'), 200, 'direct namespace lookup works');

    # Verify they are different labels
    isnt($ctx->($var_x_label), $ctx->($temp_x_label), 'namespaced labels are isolated');
}

# Test 7: mixing namespaced and non-namespaced labels
{
    my $empty = Chalk::IR::Context->empty_context();
    my $ctx = Chalk::IR::Context->extend_context($empty, 'x', 1);
    $ctx = Chalk::IR::Context->extend_context($ctx, 'var:x', 2);

    is($ctx->('x'), 1, 'non-namespaced label preserved');
    is($ctx->('var:x'), 2, 'namespaced label coexists');
}
