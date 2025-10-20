#!/usr/bin/env perl
# ABOUTME: Tests for Chalk::EvalContext comonad implementation
# ABOUTME: Validates comonad laws (extract, extend, duplicate) and basic functionality

use 5.42.0;
use warnings;
use Test::More;

use lib 'lib';
use Chalk::EvalContext;

# Test basic construction
{
    my $ctx = Chalk::EvalContext->new(
        focus => 42,
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    isa_ok($ctx, 'Chalk::EvalContext', 'constructor creates EvalContext');
    is($ctx->focus, 42, 'focus accessor works');
    is_deeply($ctx->children, [], 'children accessor works');
    is($ctx->start_pos, 0, 'start_pos accessor works');
    is($ctx->end_pos, 5, 'end_pos accessor works');
}

# Test extract (comonad operation)
{
    my $ctx = Chalk::EvalContext->new(
        focus => "hello",
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    is($ctx->extract, "hello", 'extract returns focus');
}

# Test fmap (functor operation)
{
    my $ctx = Chalk::EvalContext->new(
        focus => 10,
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $new_ctx = $ctx->fmap(sub { $_[0] * 2 });

    is($new_ctx->extract, 20, 'fmap transforms focus');
    is($ctx->extract, 10, 'original context unchanged');
    is_deeply($new_ctx->children, $ctx->children, 'children preserved by fmap');
}

# Test duplicate (comonad operation)
{
    my $child1 = Chalk::EvalContext->new(
        focus => "a",
        children => [],
        start_pos => 0,
        end_pos => 1,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $ctx = Chalk::EvalContext->new(
        focus => "parent",
        children => [$child1],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $dup = $ctx->duplicate;

    isa_ok($dup, 'Chalk::EvalContext', 'duplicate returns EvalContext');
    isa_ok($dup->extract, 'Chalk::EvalContext', 'duplicate focus is the original context');
    is($dup->extract->focus, "parent", 'duplicated focus points to original');
}

# Test extend (comonad operation)
{
    my $ctx = Chalk::EvalContext->new(
        focus => 5,
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    # extend with a function that doubles the focus
    my $extended = $ctx->extend(sub {
        my $c = shift;
        return $c->extract * 2;
    });

    is($extended->extract, 10, 'extend applies function to get new focus');
}

# Test Comonad Law 1: extract . duplicate = id
{
    my $ctx = Chalk::EvalContext->new(
        focus => "test",
        children => [],
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $duplicated = $ctx->duplicate;
    my $extracted = $duplicated->extract;

    is($extracted->focus, $ctx->focus, 'Comonad law 1: extract . duplicate = id');
}

# Test Comonad Law 2: fmap extract . duplicate = id
{
    my $ctx = Chalk::EvalContext->new(
        focus => 123,
        children => [],
        start_pos => 0,
        end_pos => 3,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $result = $ctx->duplicate->fmap(sub { $_[0]->extract });

    is($result->extract, $ctx->extract, 'Comonad law 2: fmap extract . duplicate = id');
}

# Test Comonad Law 3: duplicate . duplicate = fmap duplicate . duplicate
{
    my $ctx = Chalk::EvalContext->new(
        focus => "x",
        children => [],
        start_pos => 0,
        end_pos => 1,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $left = $ctx->duplicate->duplicate;
    my $right = $ctx->duplicate->fmap(sub { $_[0]->duplicate });

    # Both should have the same structure
    isa_ok($left->extract->extract, 'Chalk::EvalContext', 'Law 3 left side structure');
    isa_ok($right->extract->extract, 'Chalk::EvalContext', 'Law 3 right side structure');
    is($left->extract->extract->focus, $right->extract->extract->focus,
       'Comonad law 3: duplicate . duplicate = fmap duplicate . duplicate');
}

# Test child access methods
{
    my $child1 = Chalk::EvalContext->new(
        focus => "first",
        children => [],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child2 = Chalk::EvalContext->new(
        focus => "second",
        children => [],
        start_pos => 5,
        end_pos => 11,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $parent = Chalk::EvalContext->new(
        focus => "parent",
        children => [$child1, $child2],
        start_pos => 0,
        end_pos => 11,
        env => {},
        grammar => undef,
        rule => undef
    );

    is($parent->child(0), "first", 'child(0) extracts first child');
    is($parent->child(1), "second", 'child(1) extracts second child');
    is($parent->child(2), undef, 'child(n) returns undef for out of bounds');

    isa_ok($parent->child_context(0), 'Chalk::EvalContext', 'child_context(0) returns context');
    is($parent->child_context(0)->focus, "first", 'child_context returns correct context');
    is($parent->child_context(99), undef, 'child_context returns undef for out of bounds');
}

# Test with nested children
{
    my $grandchild = Chalk::EvalContext->new(
        focus => "gc",
        children => [],
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $child = Chalk::EvalContext->new(
        focus => "c",
        children => [$grandchild],
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $parent = Chalk::EvalContext->new(
        focus => "p",
        children => [$child],
        start_pos => 0,
        end_pos => 10,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Test extend propagates through children
    my $extended = $parent->extend(sub {
        my $ctx = shift;
        return uc($ctx->extract);
    });

    is($extended->extract, "P", 'extend transforms parent');
    is($extended->child_context(0)->extract, "C", 'extend transforms children');
    is($extended->child_context(0)->child_context(0)->extract, "GC", 'extend transforms grandchildren');
}

done_testing();
