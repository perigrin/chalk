# ABOUTME: Tests comonad operations (extract, extend, duplicate) for threading context through parser
# ABOUTME: Verifies comonad laws: left identity, right identity, associativity
use 5.42.0;
use utf8;
use Test::More tests => 14;

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Node::Constant;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: Simple extract
{
    my $node = $factory->make('Constant', const_type => 'string', value => 'test');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'TestRule',
    );

    is($ctx->extract(), $node, 'extract returns focus value');
}

# Test 2: extend with identity (right identity law)
# extend(extract, w) ≡ w
{
    my $node = $factory->make('Constant', const_type => 'string', value => 'identity');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'IdentityTest',
    );

    my $extended = $ctx->extend(sub ($c) { return $c->extract() });

    is($extended->extract(), $node, 'extend(extract, ctx) preserves focus');
    is($extended->position(), 0, 'extend preserves position');
    is($extended->rule(), 'IdentityTest', 'extend preserves rule');
}

# Test 3: extract after extend (left identity law)
# extract(extend(f, w)) ≡ f(w)
{
    my $node1 = $factory->make('Constant', const_type => 'string', value => 'test1');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'LeftIdentity',
    );

    my $f = sub ($c) {
        my $value = $c->extract();
        return $factory->make('Constant', const_type => 'string', value => 'transformed');
    };

    my $extended = $ctx->extend($f);
    my $result = $extended->extract();

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'extended focus is Constant node');
    is($result->value(), 'transformed', 'extract(extend(f, w)) = f(w)');
}

# Test 4: Associativity law
# extend(f, extend(g, w)) ≡ extend(f ∘ g, w)
{
    my $node = $factory->make('Constant', const_type => 'integer', value => '5');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'Associativity',
    );

    my $g = sub ($c) {
        return $factory->make('Constant', const_type => 'integer', value => '10');
    };

    my $f = sub ($c) {
        my $val = $c->extract();
        return $factory->make('Constant', const_type => 'integer', value => '20');
    };

    # Left side: extend(f, extend(g, w))
    my $left = $ctx->extend($g)->extend($f);

    # Right side: extend(f ∘ g, w)
    my $composed = sub ($c) { return $f->($c->extend($g)) };
    my $right = $ctx->extend($composed);

    is($left->extract()->id(), $right->extract()->id(),
       'extend(f, extend(g, w)) = extend(f ∘ g, w)');
}

# Test 5: duplicate creates context of contexts
{
    my $node1 = $factory->make('Constant', const_type => 'string', value => 'child1');
    my $node2 = $factory->make('Constant', const_type => 'string', value => 'child2');

    my $child_ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Child1',
    );

    my $child_ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Child2',
    );

    my $parent_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$child_ctx1, $child_ctx2],
        position => 0,
        rule     => 'Parent',
    );

    my $ctx_of_ctxs = $parent_ctx->duplicate();

    is(scalar($ctx_of_ctxs->children()->@*), 2, 'duplicate preserves children count');
    is($ctx_of_ctxs->children()->[0]->extract()->value(), 'child1',
       'duplicate preserves first child');
}

# Test 6: annotations field defaults to empty hashref
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'test',
        children => [],
        position => 0,
    );

    is_deeply($ctx->annotations(), {}, 'annotations defaults to empty hashref');
}

# Test 7: annotations field can be set via constructor
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => 'test',
        children    => [],
        position    => 0,
        annotations => { return_type => 'Void', valid => true },
    );

    is($ctx->annotations()->{return_type}, 'Void', 'annotations can be set via constructor');
    is($ctx->annotations()->{valid}, true, 'annotations preserves all keys');
}

# Test 8: extend preserves annotations
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => 'original',
        children    => [],
        position    => 0,
        rule        => 'TestRule',
        annotations => { return_type => 'Any', type => 'Scalar' },
    );

    my $extended = $ctx->extend(sub ($c) { return 'transformed' });

    is($extended->extract(), 'transformed', 'extend changes focus');
    is($extended->annotations()->{return_type}, 'Any',
       'extend preserves annotations');
}

done_testing();
