# ABOUTME: Tests that Context carries graph and scope as first-class fields.
# ABOUTME: Verifies multiply propagates them left-to-right and extend propagates from children.
use 5.42.0;
use utf8;
use Test::More;
use experimental 'class';

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Bindings;
use Chalk::IR::Graph;

# --- graph field tests ---

subtest 'Context has a graph field' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(focus => undef);
    can_ok($ctx, 'graph');
    is($ctx->graph, undef, 'graph defaults to undef');
};

subtest 'Context accepts a graph at construction' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => undef,
        graph => $graph,
    );
    is($ctx->graph, $graph, 'graph returns the provided graph');
};

# --- scope field tests ---

subtest 'Context has a scope field' => sub {
    my $ctx = Chalk::Bootstrap::Context->new(focus => undef);
    can_ok($ctx, 'scope');
    is($ctx->scope, undef, 'scope defaults to undef');
};

subtest 'Context accepts a scope at construction' => sub {
    my $scope = Chalk::Bootstrap::Bindings->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => undef,
        bindings => $scope,
    );
    is($ctx->scope, $scope, 'scope returns the provided scope');
};

# --- extend propagation ---

subtest 'extend preserves graph field' => sub {
    my $graph = Chalk::IR::Graph->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'original',
        graph => $graph,
    );
    my $extended = $ctx->extend(sub ($c) { 'new_focus' });
    is($extended->graph, $graph, 'extend propagates graph to result');
};

subtest 'extend preserves scope field' => sub {
    my $scope = Chalk::Bootstrap::Bindings->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'original',
        bindings => $scope,
    );
    my $extended = $ctx->extend(sub ($c) { 'new_focus' });
    is($extended->scope, $scope, 'extend propagates scope to result');
};

subtest 'extend opts can override graph' => sub {
    my $graph1 = Chalk::IR::Graph->new();
    my $graph2 = Chalk::IR::Graph->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'original',
        graph => $graph1,
    );
    my $extended = $ctx->extend(sub ($c) { 'new_focus' }, graph => $graph2);
    is($extended->graph, $graph2, 'extend graph opt overrides inherited graph');
};

subtest 'extend opts can override scope' => sub {
    my $scope1 = Chalk::Bootstrap::Bindings->new();
    my $scope2 = Chalk::Bootstrap::Bindings->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'original',
        bindings => $scope1,
    );
    my $extended = $ctx->extend(sub ($c) { 'new_focus' }, bindings => $scope2);
    is($extended->scope, $scope2, 'extend scope opt overrides inherited scope');
};

done_testing;
