#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter context helper functions
# ABOUTME: Tests extend_ctx and $empty_ctx for functional context management
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 7;
use Chalk::Interpreter::Context qw(extend_ctx $empty_ctx);

# Test $empty_ctx is defined
ok(defined $empty_ctx, '$empty_ctx is defined');

# Test $empty_ctx is a coderef (closure)
is(ref($empty_ctx), 'CODE', '$empty_ctx is a CODE reference');

# Test $empty_ctx returns undef for any key
is($empty_ctx->('x'), undef, '$empty_ctx returns undef for key "x"');
is($empty_ctx->('foo'), undef, '$empty_ctx returns undef for key "foo"');

# Test extend_ctx returns a coderef
my $ctx1 = extend_ctx($empty_ctx, 'x', 42);
is(ref($ctx1), 'CODE', 'extend_ctx returns a CODE reference');

# Test extended context returns correct value for new key
is($ctx1->('x'), 42, 'extended context returns value for "x"');

# Test extended context chains to parent for unknown keys
is($ctx1->('y'), undef, 'extended context returns undef for unknown key');
