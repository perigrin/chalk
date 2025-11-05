#!/usr/bin/env perl
# ABOUTME: Test SemanticContext class for managing compilation context
# ABOUTME: Verify context creation, scope management, and source location tracking
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::Semantic::Context;
use Chalk::IR::SourceInfo;

# Test 1: Create basic context
{
    my $ctx = Chalk::Semantic::Context->new();

    isa_ok($ctx, 'Chalk::Semantic::Context', 'Basic context created');
    isa_ok($ctx->current_scope, 'Chalk::Semantic::Scope', 'Context has current scope');
}

# Test 2: Bind and lookup variable
{
    my $ctx = Chalk::Semantic::Context->new();

    $ctx->bind('x', 42);
    is($ctx->lookup('x'), 42, 'Variable lookup through context works');
}

# Test 3: Enter and exit nested scopes
{
    my $ctx = Chalk::Semantic::Context->new();

    $ctx->bind('x', 'outer');
    my $outer_scope = $ctx->current_scope;

    $ctx->enter_scope();
    $ctx->bind('y', 'inner');

    is($ctx->lookup('x'), 'outer', 'Can lookup outer variable from inner scope');
    is($ctx->lookup('y'), 'inner', 'Can lookup inner variable');

    $ctx->exit_scope();

    is($ctx->current_scope, $outer_scope, 'Exited back to outer scope');
    is($ctx->lookup('x'), 'outer', 'Outer variable still accessible');
    is($ctx->lookup('y'), undef, 'Inner variable no longer accessible');
}

# Test 4: Context with source_info
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 1,
        start_col  => 1,
        end_line   => 1,
        end_col    => 10,
        start_pos  => 0,
        end_pos    => 9,
    );

    my $ctx = Chalk::Semantic::Context->new(source_info => $source_info);

    is($ctx->source_info, $source_info, 'Context stores source_info');
    is($ctx->source_location, 'test.chalk:1:1-10', 'Context provides source_location');
}

# Test 5: Derived context with new source location
{
    my $parent_ctx = Chalk::Semantic::Context->new();
    $parent_ctx->bind('x', 'parent');

    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 5,
        start_col  => 1,
        end_line   => 5,
        end_col    => 10,
        start_pos  => 50,
        end_pos    => 59,
    );

    my $child_ctx = $parent_ctx->derive(source_info => $source_info);

    isa_ok($child_ctx, 'Chalk::Semantic::Context', 'Derived context created');
    is($child_ctx->lookup('x'), 'parent', 'Derived context inherits bindings');
    is($child_ctx->source_location, 'test.chalk:5:1-10', 'Derived context has new source location');
}

done_testing();
