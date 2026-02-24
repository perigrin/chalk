# ABOUTME: Tests lazy Phi sentinel mechanism in Scope for loop-carried dependencies
# ABOUTME: Covers fork_for_loop, resolve_sentinel, raw_lookup, and sentinel lifecycle
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::NodeFactory;

my $factory = Chalk::Bootstrap::IR::NodeFactory->new();

# --- fork_for_loop: replaces bindings with sentinels ---
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my $node_a = $factory->make('Constant', const_type => 'integer', value => '1');
    my $node_b = $factory->make('Constant', const_type => 'integer', value => '2');
    $scope = $scope->define('$a', $node_a);
    $scope = $scope->define('$b', $node_b);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    isnt($forked, $scope, 'fork_for_loop returns new Scope');
    ok(defined $forked->raw_lookup('$a'), 'forked scope has $a');
    ok(defined $forked->raw_lookup('$b'), 'forked scope has $b');

    # raw_lookup returns sentinel hashref, not original node
    my $sentinel_a = $forked->raw_lookup('$a');
    ok(ref $sentinel_a eq 'HASH', '$a binding is a sentinel hashref');
    ok($sentinel_a->{sentinel}, 'sentinel flag is set');
    is($sentinel_a->{pre_value}, $node_a, 'sentinel pre_value is original node');
    is($sentinel_a->{loop}, $loop, 'sentinel loop is the Loop node');
}

# --- resolve_sentinel: creates Phi on first read ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $node_x = $factory->make('Constant', const_type => 'integer', value => '42');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node_x);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    my ($value, $new_scope) = $forked->resolve_sentinel('$x', $factory);
    ok(defined $value, 'resolve_sentinel returns a value');
    ok($value isa Chalk::Bootstrap::IR::Node::Phi, 'value is a Phi node');
    ok(defined $new_scope, 'new scope returned (sentinel was resolved)');

    # Phi inputs: [loop, [pre_value, undef]]
    my $inputs = $value->inputs();
    is($inputs->[0], $loop, 'Phi region is the Loop node');
    ok(ref $inputs->[1] eq 'ARRAY', 'Phi values is an arrayref');
    is($inputs->[1][0], $node_x, 'Phi first value is pre-loop value');
    ok(!defined $inputs->[1][1], 'Phi backedge is undef (not yet wired)');

    # Second resolve_sentinel on same name returns Phi directly, no new scope
    my ($value2, $new_scope2) = $new_scope->resolve_sentinel('$x', $factory);
    is($value2, $value, 'second resolve returns same Phi');
    ok(!defined $new_scope2, 'no new scope (already resolved)');
}

# --- resolve_sentinel: unbound variable returns undef ---
{
    my $scope = Chalk::Bootstrap::Scope->new();
    my ($value, $new_scope) = $scope->resolve_sentinel('$unknown', $factory);
    ok(!defined $value, 'unbound variable returns undef');
    ok(!defined $new_scope, 'no new scope for unbound variable');
}

# --- resolve_sentinel: non-sentinel binding returns value, no new scope ---
{
    my $node = $factory->make('Constant', const_type => 'string', value => 'hello');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node);

    my ($value, $new_scope) = $scope->resolve_sentinel('$x', $factory);
    is($value, $node, 'non-sentinel returns the bound node');
    ok(!defined $new_scope, 'no new scope (no sentinel to resolve)');
}

# --- raw_lookup: returns binding without resolving ---
{
    my $node = $factory->make('Constant', const_type => 'integer', value => '1');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    # raw_lookup returns the sentinel, not a Phi
    my $raw = $forked->raw_lookup('$x');
    ok(ref $raw eq 'HASH' && $raw->{sentinel}, 'raw_lookup returns sentinel');

    # regular lookup also returns sentinel (no auto-resolve)
    my $regular = $forked->lookup('$x');
    ok(ref $regular eq 'HASH' && $regular->{sentinel}, 'lookup returns sentinel too');
}

done_testing();
