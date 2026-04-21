# ABOUTME: Tests for unified Context fields: token, is_zero, annotations slots.
# ABOUTME: Part of the unified Context design (#703) — TDD RED phase.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';
use Chalk::Bootstrap::Context;
use Scalar::Util 'refaddr';

subtest 'token field — accepts param and has reader' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "val",
        token => "Identifier",
    );

    is( $ctx->token(), "Identifier", "token reader returns value" );
};

subtest 'token field — defaults to undef' => sub {
    my $ctx = Chalk::Bootstrap::Context->new( focus => "val" );

    is( $ctx->token(), undef, "token defaults to undef" );
};

subtest 'is_zero field — accepts param and has reader' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus   => "val",
        is_zero => true,
    );

    ok( $ctx->is_zero(), "is_zero reader returns true" );
};

subtest 'is_zero field — defaults to false' => sub {
    my $ctx = Chalk::Bootstrap::Context->new( focus => "val" );

    ok( !$ctx->is_zero(), "is_zero defaults to false" );
};

subtest 'extend passes through token' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "orig",
        token => "Expression",
    );

    my $new = $ctx->extend( sub { "new" } );

    is( $new->token(), "Expression", "token preserved through extend" );
};

subtest 'extend passes through is_zero' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus   => "orig",
        is_zero => true,
    );

    my $new = $ctx->extend( sub { "new" } );

    ok( $new->is_zero(), "is_zero preserved through extend" );
};

subtest 'extend with token override' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "orig",
        token => "OldToken",
    );

    my $new = $ctx->extend( sub { "new" }, token => "NewToken" );

    is( $new->token(), "NewToken", "token overridden via opts" );
    is( $ctx->token(), "OldToken", "original token unchanged" );
};

subtest 'extend with is_zero override' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus   => "orig",
        is_zero => false,
    );

    my $new = $ctx->extend( sub { "new" }, is_zero => true );

    ok( $new->is_zero(),  "is_zero overridden to true" );
    ok( !$ctx->is_zero(), "original is_zero unchanged" );
};

subtest 'annotations can hold cfg, precedence, type, structural slots' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => "val",
        annotations => {
            cfg        => { control => 'start', scope => 'top' },
            precedence => 5,
            type       => { valid => true, type => 'Int' },
            structural => 0x03,
        },
    );

    is_deeply( $ctx->annotations()->{cfg},
        { control => 'start', scope => 'top' },
        "cfg annotation preserved" );
    is( $ctx->annotations()->{precedence}, 5,
        "precedence annotation preserved" );
    is_deeply( $ctx->annotations()->{type},
        { valid => true, type => 'Int' },
        "type annotation preserved" );
    is( $ctx->annotations()->{structural}, 0x03,
        "structural annotation preserved" );
};

subtest 'extend preserves all fields together' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => "orig",
        token       => "Atom",
        is_zero     => false,
        rule        => "Expression",
        position    => 42,
        annotations => { precedence => 3 },
    );

    my $new = $ctx->extend( sub { "new" } );

    is( $new->token(),    "Atom",       "token preserved" );
    ok( !$new->is_zero(),               "is_zero preserved" );
    is( $new->rule(),     "Expression", "rule preserved" );
    is( $new->position(), 42,           "position preserved" );
    is_deeply( $new->annotations(), { precedence => 3 },
        "annotations preserved" );
};

subtest 'extend copies annotations — child mutation does not affect parent' => sub {
    my $parent = Chalk::Bootstrap::Context->new(
        focus       => "orig",
        annotations => { cfg => { control => 'start' } },
    );

    my $child = $parent->extend( sub { "new" } );

    # Mutate child's annotations
    $child->annotations()->{cfg} = { control => 'changed' };

    is( $parent->annotations()->{cfg}{control}, 'start',
        "parent annotations not mutated by child write" );
    is( $child->annotations()->{cfg}{control}, 'changed',
        "child annotations reflect the write" );
};

subtest 'error field — accepts param and has reader' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "val",
        error => "invariant violated",
    );

    is( $ctx->error(), "invariant violated", "error reader returns value" );
};

subtest 'error field — defaults to undef' => sub {
    my $ctx = Chalk::Bootstrap::Context->new( focus => "val" );

    is( $ctx->error(), undef, "error defaults to undef" );
};

subtest 'extend passes through error' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "orig",
        error => "upstream failure",
    );

    my $new = $ctx->extend( sub { "new" } );

    is( $new->error(), "upstream failure", "error preserved through extend" );
};

subtest 'extend with error override' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "orig",
        error => undef,
    );

    my $new = $ctx->extend( sub { "new" }, error => "new failure" );

    is( $new->error(), "new failure",  "error overridden via opts" );
    is( $ctx->error(), undef,          "original error unchanged" );
};

subtest 'error is independent of is_zero' => sub {
    # is_zero is algebraic parse-rejection; error is system-failure.
    # A Context can be errored without is_zero being true, and vice versa.
    my $errored_not_zero = Chalk::Bootstrap::Context->new(
        focus   => "val",
        error   => "bad thing",
        is_zero => false,
    );
    ok( defined $errored_not_zero->error(), "errored context has error" );
    ok( !$errored_not_zero->is_zero(),       "errored context can be non-zero" );

    my $zero_not_errored = Chalk::Bootstrap::Context->new(
        focus   => "val",
        error   => undef,
        is_zero => true,
    );
    ok( !defined $zero_not_errored->error(), "zero context can have no error" );
    ok( $zero_not_errored->is_zero(),         "zero context is_zero" );
};

done_testing();
