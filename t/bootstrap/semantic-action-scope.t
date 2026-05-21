# ABOUTME: Tests for cfg_state threading in SemanticAction via Context annotations.
# ABOUTME: Verifies control/scope state propagates correctly through parse operations.
use 5.42.0;
use utf8;
use Test::More;

use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Context;

# Helper: build a complete-annotated Context for multiply() calls.
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

# --- Test 1: cfg_state on one() context ---
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $one = $sa->one();
    ok(defined $one, 'one() returns a Context');

    # Focus remains undef (backward compatible)
    is($one->extract(), undef, 'one() focus is undef (backward compatible)');

    # CFG state is accessible via cfg_state
    my $state = $one->cfg_state();
    ok(defined $state, 'cfg_state returns state for one() context');
    is(ref($state), 'HASH', 'cfg_state returns a hashref');
    ok(exists $state->{control}, 'state has control key');
    ok(exists $state->{scope}, 'state has scope key');
    is($state->{control}->operation(), 'Start', 'initial control is Start');
    ok($state->{scope} isa Chalk::Bootstrap::Scope, 'initial scope is a Scope');
}

# --- Test 2: cfg_state propagates through multiply with complete Context ---
{
    my $factory = Chalk::IR::NodeFactory->new();

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

    my $result = $sa->multiply($one, $make_complete->($one, 'TestRule', 0, 0, 0));
    ok(defined $result, 'multiply with complete Context returns result');

    # Focus is the bare IR node (action returned it)
    is($result->extract(), $const, 'focus is the action result (bare IR node)');

    # CFG state still available
    my $state = $result->cfg_state();
    ok(defined $state, 'cfg_state available on completed context');
    is($state->{control}->operation(), 'Start', 'control propagated from parent');
    ok($state->{scope} isa Chalk::Bootstrap::Scope, 'scope propagated from parent');
}

# --- Test 3: set_cfg_state allows actions to update control/scope ---
{
    my $factory = Chalk::IR::NodeFactory->new();

    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $one = $sa->one();

    # Simulate an action that updates the scope
    my $node = $factory->make('Constant', const_type => 'integer', value => 42);
    my $new_scope = Chalk::Bootstrap::Scope->new()->define('$x', $node);
    my $new_control = $factory->make('If',
        control => $one->cfg_state()->{control},
        condition => $node);

    $sa->set_cfg_state($one, { control => $new_control, scope => $new_scope });

    my $state = $one->cfg_state();
    is($state->{control}, $new_control, 'control updated via set_cfg_state');
    is($state->{scope}->lookup('$x'), $node, 'scope updated via set_cfg_state');
}

# --- Test 4: reset_cache creates a fresh singleton with cfg state ---
# Context annotations are part of the Context object itself, so resetting the
# cache causes the NEXT one() call to return a new singleton — not to clear
# annotations on the old one.
{
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $old_one = $sa->one();

    ok(defined $old_one->cfg_state(), 'cfg_state exists before reset');

    $sa->reset_cache();

    # After reset, next one() call returns a NEW singleton
    my $new_one = $sa->one();
    isnt($old_one, $new_one, 'reset_cache creates a new singleton');
    ok(defined $new_one->cfg_state(), 'new singleton has fresh cfg_state');
}

done_testing();
