# ABOUTME: Tests lazy Phi sentinel mechanism in Scope for loop-carried dependencies
# ABOUTME: Covers fork_for_loop, resolve_sentinel, raw_lookup, and sentinel lifecycle
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Scope;
use Chalk::IR::NodeFactory;

my $factory = Chalk::IR::NodeFactory->new();

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
    ok(ref $sentinel_a eq 'Chalk::Bootstrap::Scope::Sentinel', '$a binding is a blessed sentinel');
    is($sentinel_a->pre_value(), $node_a, 'sentinel pre_value is original node');
    is($sentinel_a->loop(), $loop, 'sentinel loop is the Loop node');
}

# --- resolve_sentinel: creates Phi on first read ---
{
    my $node_x = $factory->make('Constant', const_type => 'integer', value => '42');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $node_x);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    my ($value, $new_scope) = $forked->resolve_sentinel('$x', $factory);
    ok(defined $value, 'resolve_sentinel returns a value');
    ok($value isa Chalk::IR::Node::Phi, 'value is a Phi node');
    ok(defined $new_scope, 'new scope returned (sentinel was resolved)');

    # Phi: region() is the Loop node, inputs() is values [pre_value, undef]
    is($value->region(), $loop, 'Phi region is the Loop node');
    my $inputs = $value->inputs();
    ok(ref $inputs eq 'ARRAY', 'Phi values is an arrayref');
    is($inputs->[0], $node_x, 'Phi first value is pre-loop value');
    ok(!defined $inputs->[1], 'Phi backedge is undef (not yet wired)');

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
    ok(ref $raw eq 'Chalk::Bootstrap::Scope::Sentinel', 'raw_lookup returns sentinel');

    # regular lookup also returns sentinel (no auto-resolve)
    my $regular = $forked->lookup('$x');
    ok(ref $regular eq 'Chalk::Bootstrap::Scope::Sentinel', 'lookup returns sentinel too');
}

# --- Sentinel is a proper class with accessor methods ---
{
    my $node = $factory->make('Constant', const_type => 'integer', value => '99');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$v', $node);

    my $loop = $factory->make('Loop', entry_ctrl => $factory->make('Start'), backedge_ctrl => undef);
    my $forked = $scope->fork_for_loop($loop);

    my $sentinel = $forked->raw_lookup('$v');
    ok($sentinel isa Chalk::Bootstrap::Scope::Sentinel, 'sentinel isa Chalk::Bootstrap::Scope::Sentinel');
    is($sentinel->loop(), $loop, 'sentinel->loop() returns the Loop node');
    is($sentinel->pre_value(), $node, 'sentinel->pre_value() returns the pre-loop binding');
}

done_testing();
