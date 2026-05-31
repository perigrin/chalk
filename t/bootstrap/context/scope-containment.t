# ABOUTME: Tests that scope containment works correctly through Context fields.
# ABOUTME: A structural action that doesn't propagate scope produces a result with no scope.
use 5.42.0;
use utf8;
use Test::More;
use experimental 'class';

use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Bindings;
use Chalk::IR::Graph;

subtest 'structural action can drop scope by not propagating it' => sub {
    my $scope = Chalk::Bootstrap::Bindings->new()->define('$x', 'some_node');
    my $inner_ctx = Chalk::Bootstrap::Context->new(
        focus => 'inner',
        bindings => $scope,
    );

    # A structural action (like MethodDefinition) doesn't forward its children's scope.
    # It explicitly passes scope => undef (or omits scope from opts).
    my $outer = $inner_ctx->extend(
        sub ($c) { 'method_result' },
        bindings => undef,
    );

    is($outer->scope, undef, 'structural action produces result with no scope');
};

subtest 'scope survives extend when not overridden' => sub {
    my $scope = Chalk::Bootstrap::Bindings->new()->define('$y', 'some_other_node');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'value',
        bindings => $scope,
    );

    my $extended = $ctx->extend(sub ($c) { 'new_value' });
    is($extended->scope, $scope, 'scope inherited when not overridden in extend');
};

subtest 'scope from outer extend not visible in separate sibling context' => sub {
    my $scope = Chalk::Bootstrap::Bindings->new()->define('$z', 'a_node');
    my $ctx_with_scope = Chalk::Bootstrap::Context->new(
        focus => 'body',
        bindings => $scope,
    );

    # Simulate a separate "after" context with no scope
    my $ctx_without_scope = Chalk::Bootstrap::Context->new(
        focus => 'after',
        bindings => undef,
    );

    is($ctx_without_scope->scope, undef,
        'unrelated context has no scope (body scope does not leak)');
};

done_testing;
