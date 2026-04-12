# ABOUTME: TDD test for Context->extend wrapping behavior.
# ABOUTME: Verifies that extend grows the tree by wrapping self as a child, not copying children.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use Scalar::Util 'refaddr';

use Chalk::Bootstrap::Context;

subtest 'extend wraps self as child' => sub {
    my $original = Chalk::Bootstrap::Context->new(
        focus    => 'original',
        children => [],
        position => 0,
        rule     => 'TestRule',
    );

    my $result = $original->extend(sub ($ctx) { return 'transformed' });

    is( $result->extract(), 'transformed', 'result has correct focus' );

    my @children = $result->children()->@*;
    is( scalar @children, 1, 'result has exactly 1 child (self wrapped, not empty [] copied)' );

    if (@children) {
        is( $children[0]->extract(), 'original', 'single child is the original context' );
        is( refaddr($children[0]), refaddr($original), 'child IS the original context by identity' );
    }
};

subtest 'extend preserves tree depth through multiple extends' => sub {
    my $leaf = Chalk::Bootstrap::Context->new(
        focus    => 'leaf',
        children => [],
        position => 0,
        rule     => 'Leaf',
    );

    my $ctx1 = $leaf->extend(sub ($ctx) { return 'level1' });
    my $ctx2 = $ctx1->extend(sub ($ctx) { return 'level2' });

    is( $ctx2->extract(), 'level2', 'ctx2 has focus level2' );

    my @ctx2_children = $ctx2->children()->@*;
    is( scalar @ctx2_children, 1, 'ctx2 has exactly 1 child (ctx1)' );

    if (@ctx2_children) {
        is( $ctx2_children[0]->extract(), 'level1', 'ctx2 child has focus level1' );

        my @ctx1_children = $ctx2_children[0]->children()->@*;
        is( scalar @ctx1_children, 1, 'ctx1 has exactly 1 child (leaf)' );

        if (@ctx1_children) {
            is( $ctx1_children[0]->extract(), 'leaf', 'ctx1 child is the leaf context' );
        }
    }
};

subtest 'extended context wraps self when original has existing children' => sub {
    my $child1 = Chalk::Bootstrap::Context->new(
        focus    => 'c1',
        children => [],
        position => 0,
        rule     => 'Child',
    );
    my $child2 = Chalk::Bootstrap::Context->new(
        focus    => 'c2',
        children => [],
        position => 1,
        rule     => 'Child',
    );

    my $ctx_a = Chalk::Bootstrap::Context->new(
        focus    => 'A',
        children => [ $child1, $child2 ],
        position => 0,
        rule     => 'Parent',
    );

    my $result = $ctx_a->extend(sub ($ctx) { return 'B' });

    is( $result->extract(), 'B', 'result has focus B' );

    my @result_children = $result->children()->@*;
    is( scalar @result_children, 1, 'result has 1 child (ctx_a itself), not 2 copied children' );

    if ( scalar @result_children == 1 ) {
        is( $result_children[0]->extract(), 'A', 'single child is ctx_a (focus = A)' );
        is( refaddr($result_children[0]), refaddr($ctx_a), 'child IS ctx_a by identity' );

        # The original tree (ctx_a's children) is preserved inside ctx_a
        my @a_children = $result_children[0]->children()->@*;
        is( scalar @a_children, 2, 'ctx_a still has its original 2 children preserved' );
        is( $a_children[0]->extract(), 'c1', 'ctx_a first child still has focus c1' )
            if @a_children >= 1;
        is( $a_children[1]->extract(), 'c2', 'ctx_a second child still has focus c2' )
            if @a_children >= 2;
    }
    else {
        # Failing state: wrong child count — skip inner checks to avoid crash
        pass('skipping inner child checks (child count wrong)') for 1 .. 4;
    }
};

subtest 'comonad right identity: extend(extract) wraps self as child' => sub {
    my $w = Chalk::Bootstrap::Context->new(
        focus    => 'x',
        children => [],
        position => 0,
        rule     => 'TestRule',
    );

    # Right identity: extend(extract) should behave like duplicate wrapping
    my $result = $w->extend(sub ($ctx) { return $ctx->extract() });

    is( $result->extract(), 'x', 'focus preserved after extend(extract)' );

    my @children = $result->children()->@*;
    is( scalar @children, 1, 'extend(extract) produces 1 child wrapping original' );

    if (@children) {
        is( refaddr($children[0]), refaddr($w), 'child is the original context $w' );
    }
};

done_testing();
