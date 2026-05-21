# ABOUTME: Tests that Context carries factory as a first-class field.
# ABOUTME: Verifies extend propagates it and allows overrides via opts.
use 5.42.0;
use utf8;
use Test::More;
use experimental 'class';

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::IR::NodeFactory;

subtest 'Context has a factory field' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(focus => undef);
    can_ok($ctx, 'factory');
    is($ctx->factory, undef, 'factory defaults to undef');
};

subtest 'Context accepts a factory at construction' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $ctx = Chalk::Bootstrap::Context->new(
        focus   => undef,
        factory => $f,
    );
    is($ctx->factory, $f, 'factory returns the provided factory');
};

subtest 'extend preserves factory field' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $ctx = Chalk::Bootstrap::Context->new(
        focus   => 'original',
        factory => $f,
    );
    my $extended = $ctx->extend(sub ($c) { 'new_focus' });
    is($extended->factory, $f, 'extend propagates factory to result');
};

subtest 'extend opts can override factory' => sub {
    my $f1 = Chalk::IR::NodeFactory->new;
    my $f2 = Chalk::IR::NodeFactory->new;
    my $ctx = Chalk::Bootstrap::Context->new(
        focus   => 'original',
        factory => $f1,
    );
    my $extended = $ctx->extend(sub ($c) { 'new_focus' }, factory => $f2);
    is($extended->factory, $f2, 'extend factory opt overrides inherited factory');
};

subtest 'siblings can have independent factories' => sub {
    my $f1 = Chalk::IR::NodeFactory->new;
    my $f2 = Chalk::IR::NodeFactory->new;
    my $base = Chalk::Bootstrap::Context->new(focus => 'base');
    my $a = $base->extend(sub ($c) { 'a' }, factory => $f1);
    my $b = $base->extend(sub ($c) { 'b' }, factory => $f2);
    is($a->factory, $f1, 'sibling a carries f1');
    is($b->factory, $f2, 'sibling b carries f2');
    isnt($a->factory, $b->factory, 'siblings see different factories');
};

done_testing;
