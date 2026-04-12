# ABOUTME: Tests cfg_state migration from SemanticAction side-table to Context annotations->{cfg}.
# ABOUTME: Verifies dual-write, annotation-read, and removal of the refaddr-keyed side-table.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::IR::NodeFactory;
use Scalar::Util 'refaddr';

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# ---------------------------------------------------------------------------
# Phase 1: Dual-write — cfg_state written to both side-table AND annotations->{cfg}
# ---------------------------------------------------------------------------

subtest 'set_cfg_state also writes cfg annotation onto Context' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new( focus => 'v' );
    my $state = {
        control => $factory->make('Start'),
        scope   => undef,
    };

    $sa->set_cfg_state( $ctx, $state );

    is_deeply(
        $ctx->annotations()->{cfg},
        $state,
        "annotations->{cfg} is set after set_cfg_state"
    );
};

subtest 'cfg_state reads cfg annotation when present' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $state = { control => $start, scope => undef };
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => 'v',
        annotations => { cfg => $state },
    );

    my $retrieved = $sa->cfg_state($ctx);

    is_deeply( $retrieved, $state, "cfg_state reads from annotations->{cfg}" );
};

subtest 'one() sets cfg annotation on singleton context' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();

    ok( defined $one->annotations()->{cfg},
        "one() context has cfg annotation" );
    ok( defined $one->annotations()->{cfg}{control},
        "one() cfg annotation has control key" );
    ok( defined $one->annotations()->{cfg}{scope},
        "one() cfg annotation has scope key" );
};

subtest 'on_skip_optional propagates cfg annotation onto placeholder' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();
    my $result = $sa->on_skip_optional( $one, 'FooOpt', 0, 5, 'Foo' );

    ok( defined $result, "on_skip_optional returns defined value" );

    # Walk children to find the placeholder (last child in the multiply tree)
    my $placeholder;
    my @stack = ($result);
    while (@stack) {
        my $node = pop @stack;
        if ( defined $node->rule() && $node->rule() eq 'Foo_opt' ) {
            $placeholder = $node;
            last;
        }
        push @stack, $node->children()->@*;
    }

    ok( defined $placeholder, "placeholder context found" );
    ok( defined $placeholder->annotations()->{cfg},
        "placeholder has cfg annotation" );
};

subtest 'multiply propagates cfg annotation to result' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $start_node = $factory->make('Start');
    my $state = { control => $start_node, scope => undef };

    my $left = Chalk::Bootstrap::Context->new( focus => 'l' );
    $sa->set_cfg_state( $left, $state );

    my $right = Chalk::Bootstrap::Context->new( focus => 'r' );

    my $result = $sa->multiply( $left, $right );

    ok( defined $result->annotations()->{cfg},
        "multiply result has cfg annotation propagated from left" );
};

subtest 'reset_cache clears cfg annotations on cached contexts' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();
    ok( defined $one->annotations()->{cfg}, "one has cfg annotation before reset" );

    $sa->reset_cache();
    my $one2 = $sa->one();

    # After reset, a new singleton is created — it should also have cfg annotation
    ok( defined $one2->annotations()->{cfg}, "new one() after reset has cfg annotation" );
    isnt( refaddr($one), refaddr($one2), "reset creates a new singleton" );
};

# ---------------------------------------------------------------------------
# Phase 2: Reader migration — cfg_state($ctx) prefers annotations->{cfg}
# ---------------------------------------------------------------------------

subtest 'cfg_state prefers annotations->{cfg} over refaddr side-table' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $annotation_state = { control => $start, scope => undef, source => 'annotation' };

    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => 'v',
        annotations => { cfg => $annotation_state },
    );

    my $retrieved = $sa->cfg_state($ctx);

    is( $retrieved->{source}, 'annotation',
        "cfg_state reads from annotations->{cfg}, not side-table" );
};

subtest 'inherited_cfg_state returns cfg annotation from context' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $start = $factory->make('Start');
    my $state = { control => $start, scope => undef, marker => 'from_annotation' };

    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => 'v',
        annotations => { cfg => $state },
    );

    my $inherited = $sa->inherited_cfg_state($ctx);

    is( $inherited->{marker}, 'from_annotation',
        "inherited_cfg_state returns cfg annotation (not side-table fallback)" );
};

done_testing();
