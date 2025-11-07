#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter context helper functions
# ABOUTME: Tests IR::Context methods for functional context management
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 7;
use Chalk::IR::Context;

# Test empty_context returns a coderef
my $empty_ctx = Chalk::IR::Context->empty_context();
ok(defined $empty_ctx, 'empty_context() is defined');

# Test empty_context is a coderef (closure)
is(ref($empty_ctx), 'CODE', 'empty_context() is a CODE reference');

# Test empty_context returns undef for any key
is($empty_ctx->('x'), undef, 'empty_context() returns undef for key "x"');
is($empty_ctx->('foo'), undef, 'empty_context() returns undef for key "foo"');

# Test extend_context returns a coderef
my $ctx1 = Chalk::IR::Context->extend_context($empty_ctx, 'x', 42);
is(ref($ctx1), 'CODE', 'extend_context() returns a CODE reference');

# Test extended context returns correct value for new key
is($ctx1->('x'), 42, 'extended context returns value for "x"');

# Test extended context chains to parent for unknown keys
is($ctx1->('y'), undef, 'extended context returns undef for unknown key');
