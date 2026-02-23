# ABOUTME: Tests for enriched SemanticAction focus with control token and scope.
# ABOUTME: Verifies side-table approach threads control/scope without breaking Context tree.
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::NodeFactory;

# --- Test 1: cfg_state on one() context ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $one = $sa->one();
    ok(defined $one, 'one() returns a Context');

    # Focus remains undef (backward compatible)
    is($one->extract(), undef, 'one() focus is undef (backward compatible)');

    # CFG state is accessible via cfg_state
    my $state = $sa->cfg_state($one);
    ok(defined $state, 'cfg_state returns state for one() context');
    is(ref($state), 'HASH', 'cfg_state returns a hashref');
    ok(exists $state->{control}, 'state has control key');
    ok(exists $state->{scope}, 'state has scope key');
    is($state->{control}->operation(), 'Start', 'initial control is Start');
    ok($state->{scope} isa Chalk::Bootstrap::Scope, 'initial scope is a Scope');
}

# --- Test 2: cfg_state propagates through on_complete ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Create a minimal actions object that returns a bare IR node
    my $const = $factory->make('Constant', const_type => 'string', value => 'test');

    {
        package TestActions::ScopeTest;
        sub new { bless {}, shift }
        sub TestRule {
            my ($self, $ctx) = @_;
            return $const;
        }
    }

    my $actions_obj = TestActions::ScopeTest->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions_obj);

    # Build a minimal parse item
    my $one = $sa->one();
    my $item = {
        value => $one,
        rule  => _mock_rule('TestRule'),
    };

    my $result = $sa->on_complete($item, 0, 0);
    ok(defined $result, 'on_complete returns result');

    # Focus is the bare IR node (action returned it)
    is($result->extract(), $const, 'focus is the action result (bare IR node)');

    # CFG state still available
    my $state = $sa->cfg_state($result);
    ok(defined $state, 'cfg_state available on completed context');
    is($state->{control}->operation(), 'Start', 'control propagated from parent');
    ok($state->{scope} isa Chalk::Bootstrap::Scope, 'scope propagated from parent');
}

# --- Test 3: set_cfg_state allows actions to update control/scope ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $one = $sa->one();

    # Simulate an action that updates the scope
    my $node = $factory->make('Constant', const_type => 'integer', value => 42);
    my $new_scope = Chalk::Bootstrap::Scope->new()->define('$x', $node);
    my $new_control = $factory->make('If',
        control => $sa->cfg_state($one)->{control},
        condition => $node);

    $sa->set_cfg_state($one, { control => $new_control, scope => $new_scope });

    my $state = $sa->cfg_state($one);
    is($state->{control}, $new_control, 'control updated via set_cfg_state');
    is($state->{scope}->lookup('$x'), $node, 'scope updated via set_cfg_state');
}

# --- Test 4: reset_cache clears cfg state ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $one = $sa->one();

    ok(defined $sa->cfg_state($one), 'cfg_state exists before reset');

    $sa->reset_cache();

    # After reset, old contexts' state is cleared
    is($sa->cfg_state($one), undef, 'cfg_state cleared after reset');
}

done_testing();

# Mock rule object for tests
sub _mock_rule {
    my ($name) = @_;
    return bless { name => $name }, 'MockRule::ScopeTest';
}

{
    package MockRule::ScopeTest;
    sub name { return $_[0]->{name} }
}
