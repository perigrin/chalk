# ABOUTME: Tests that variable references resolve from scope when available
# ABOUTME: Verifies ScalarVariable/ArrayVariable/HashVariable consult cfg_state scope
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Phi;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Bootstrap::Context;
my $factory = Chalk::IR::NodeFactory->new();

# Helper: build a scan context for a variable name at position 0.
# Optional %extra fields are forwarded to Context::new — e.g. pass
# scope => $s to set the scope field directly (replaces the old
# $sa->set_cfg_state(ctx, { control, scope }) which has been removed).
my sub make_scan_ctx($text, %extra) {
    return Chalk::Bootstrap::Context->new(
        focus    => $text,
        children => [],
        position => 0,
        rule     => undef,
        %extra,
    );
}

# Helper: build a complete-annotated Context for multiply() calls.
# Replaces on_complete($value, $rule_name, $alt_idx, $pos, $origin).
my $make_complete = sub ($value, $rule_name, $alt_idx, $pos, $origin) {
    $pos    //= 0;
    $origin //= 0;
    $alt_idx //= 0;
    return Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => defined($value) ? [$value] : [],
        position    => $pos,
        annotations => {
            complete  => true,
            rule_name => $rule_name,
            alt_idx   => $alt_idx,
            pos       => $pos,
            origin    => $origin,
        },
    );
};

# --- Case 1: Backward compat — variable not in scope returns Constant ---
# We test this by calling on_complete for ScalarVariable with a context that
# has no cfg_state (or empty scope), and verify a Constant is returned.
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Scan context for $unbound — no cfg_state set
    my $ctx = make_scan_ctx('$unbound');

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'ScalarVariable', 0, 0, 0));
    ok(defined $result, 'on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'result has a focus node');
    is($node->operation(), 'Constant', 'unbound variable returns Constant node');
    is($node->value(), '$unbound', 'Constant has the variable name as value');
}

# --- Case 2: Variable in scope — action returns the bound node ---
# Set up cfg_state on the input context with a scope containing $x = some_node.
# Verify on_complete for ScalarVariable returns that node.
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Create a node representing the binding for $x
    my $x_node = $factory->make('Constant', const_type => 'integer', value => '42');

    # Create scope with $x bound
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $x_node);

    # Build a Context with the scope (control-bearing) field set directly.
    # Phase 3a-infra deleted set_cfg_state — Context's scope field is now
    # the channel for control + scope state.
    my $ctx = make_scan_ctx('$x',
        scope => $scope->with_control($factory->make('Start')),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'ScalarVariable', 0, 0, 0));
    ok(defined $result, 'on_complete returns a result for in-scope variable');

    my $node = $result->extract();
    ok(defined $node, 'result has a focus node');
    is($node->operation(), 'Constant', 'in-scope $x returns its bound node');
    is($node->value(), '42', 'bound node has correct value (the integer 42)');
    is($node, $x_node, 'returned node is exactly the bound node from scope');
}

# --- Case 3: Sentinel in scope — action creates a Phi node ---
# Set up cfg_state with a scope containing a sentinel for $x.
# Verify on_complete for ScalarVariable creates and returns a Phi node.
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Create pre-loop binding and a loop node
    my $pre_value = $factory->make('Constant', const_type => 'integer', value => '0');
    my $loop = $factory->make('Loop',
        entry_ctrl   => $factory->make('Start'),
        backedge_ctrl => undef,
    );

    # Fork scope to create sentinels
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $pre_value);
    my $loop_scope = $scope->fork_for_loop($loop);

    # Verify sentinel is in place before calling action
    my $raw = $loop_scope->raw_lookup('$x');
    ok(ref $raw eq 'Chalk::Bootstrap::Scope::Sentinel', 'scope has sentinel before action runs');

    # Build a Context with the sentinel scope (control-bearing) field set.
    my $ctx = make_scan_ctx('$x',
        scope => $loop_scope->with_control($factory->make('Start')),
    );


    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'ScalarVariable', 0, 0, 0));
    ok(defined $result, 'on_complete returns a result for sentinel variable');

    my $node = $result->extract();
    ok(defined $node, 'result has a focus node');
    ok($node isa Chalk::IR::Node::Phi, 'sentinel variable resolves to a Phi node');

    # Phi: region() returns the loop node; inputs() is the values array [pre_value, undef]
    my $inputs = $node->inputs();
    is($node->region(), $loop, 'Phi region is the loop node');
    is($inputs->[0], $pre_value, 'Phi pre-value is the pre-loop binding');
    ok(!defined $inputs->[1], 'Phi backedge is undef (not yet wired)');

    # The cfg_state on the result should have the updated scope (Phi, not sentinel)
    my $state = $result->cfg_state();
    ok(defined $state, 'result context has cfg_state');
    if (defined $state) {
        my $x_after = $state->{scope}->lookup('$x');
        ok(defined $x_after, '$x is still in scope after resolution');
        ok($x_after isa Chalk::IR::Node::Phi,
            '$x binding was updated to the Phi node');
    }
}

# --- Case 4: ArrayVariable also resolves from scope ---
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $arr_node = $factory->make('Constant', const_type => 'variable', value => '@arr');

    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('@arr', $arr_node);

    my $ctx = make_scan_ctx('@arr',
        scope => $scope->with_control($factory->make('Start')),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'ArrayVariable', 0, 0, 0));
    ok(defined $result, 'ArrayVariable on_complete returns result');
    my $node = $result->extract();
    is($node, $arr_node, 'ArrayVariable returns bound node from scope');
}

# --- Case 5: HashVariable also resolves from scope ---
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $hash_node = $factory->make('Constant', const_type => 'variable', value => '%h');

    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('%h', $hash_node);

    my $ctx = make_scan_ctx('%h',
        scope => $scope->with_control($factory->make('Start')),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'HashVariable', 0, 0, 0));
    ok(defined $result, 'HashVariable on_complete returns result');
    my $node = $result->extract();
    is($node, $hash_node, 'HashVariable returns bound node from scope');
}

done_testing();
