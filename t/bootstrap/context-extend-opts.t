# ABOUTME: Tests for extend() accepting optional rule and annotations overrides.
# ABOUTME: RED phase TDD — tests 1-3 must fail until extend() supports %opts.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';
use Chalk::Bootstrap::Context;
use Scalar::Util 'refaddr';

subtest 'extend with rule override' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => "original",
        rule  => "OldRule",
    );

    my $new_ctx = $ctx->extend(sub { "transformed" }, rule => "NewRule");

    is( $new_ctx->focus(), "transformed", "focus is transformed" );
    is( $new_ctx->rule(),  "NewRule",     "rule is overridden to NewRule" );
    is( refaddr( $new_ctx->children()->[0] ),
        refaddr($ctx), "children->[0] is the original context" );
};

subtest 'extend with annotations override' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => "original",
        annotations => { old => 1 },
    );

    my $new_ctx = $ctx->extend(
        sub { "transformed" },
        annotations => { type => 'Int' }
    );

    is_deeply( $new_ctx->annotations(), { type => 'Int' },
        "annotations is overridden" );
    is_deeply( $ctx->annotations(), { old => 1 },
        "original context annotations are unchanged" );
};

subtest 'extend with both rule and annotations override' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => "orig",
        rule        => "R1",
        annotations => {},
    );

    my $new_ctx = $ctx->extend(
        sub { "new" },
        rule        => "R2",
        annotations => { valid => 1 },
    );

    is( $new_ctx->rule(), "R2", "rule is overridden to R2" );
    is_deeply( $new_ctx->annotations(), { valid => 1 },
        "annotations is overridden" );
};

subtest 'extend without opts preserves existing behavior' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => "orig",
        rule        => "Keep",
        annotations => { k => 1 },
    );

    my $new_ctx = $ctx->extend( sub { "new" } );

    is( $new_ctx->focus(), "new",   "focus is updated" );
    is( $new_ctx->rule(),  "Keep",  "rule is preserved when no opts given" );
    is_deeply( $new_ctx->annotations(), { k => 1 },
        "annotations preserved when no opts given" );
};

done_testing();
