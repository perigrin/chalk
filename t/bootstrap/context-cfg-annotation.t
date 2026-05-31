# ABOUTME: Tests the cfg_state compatibility shim on SemanticAction.
# ABOUTME: Verifies cfg_state reads control from control_head and bindings from the bindings field.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Bindings;
use Chalk::IR::NodeFactory;
use Scalar::Util 'refaddr';

my $factory = Chalk::IR::NodeFactory->new();

# ---------------------------------------------------------------------------
# Phase 3: New API — cfg_state reads from control_head + bindings field
# + individual annotations. Post scope/control divorce: control lives on
# the control_head Context field; bindings is the renamed scope field.
# ---------------------------------------------------------------------------

subtest 'cfg_state returns undef for context with no control_head' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new( focus => 'v' );
    my $state = $ctx->cfg_state();
    ok(!defined $state, 'cfg_state returns undef when no control_head on context');
};

subtest 'cfg_state reads control from control_head field' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $bindings = Chalk::Bootstrap::Bindings->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus        => 'v',
        bindings     => $bindings,
        control_head => $start,
    );

    my $state = $ctx->cfg_state();
    ok(defined $state, 'cfg_state returns state when control_head present');
    is($state->{control}, $start, 'cfg_state control comes from control_head');
    is($state->{scope}, $bindings, 'cfg_state scope is the bindings object');
};

subtest 'cfg_state reads structural annotations from context annotations' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $region  = $factory->make('Region', controls => [$if_node]);
    my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);

    my $ctx = Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => [],
        position     => 0,
        bindings     => Chalk::Bootstrap::Bindings->new(),
        control_head => $region,
        annotations => {
            if_node    => $if_node,
            then_stmts => [$then_stmt],
        },
    );

    my $state = $ctx->cfg_state();
    ok(defined $state, 'cfg_state returns state');
    is($state->{control}, $region, 'control from control_head');
    is($state->{if_node}, $if_node, 'if_node from annotations');
    is(ref($state->{then_stmts}), 'ARRAY', 'then_stmts is array');
    is($state->{then_stmts}->[0], $then_stmt, 'then_stmts contains expected node');
};

subtest 'one() sets bindings and control_head on singleton context' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();

    ok(defined $one->bindings(), 'one() context has bindings');
    ok(defined $one->control_head(), 'one() context has control_head');
    is($one->control_head()->operation(), 'Start', 'one() control_head is Start');
};

subtest 'cfg_state on one() returns state with Start control' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();
    my $state = $one->cfg_state();

    ok(defined $state, 'cfg_state on one() returns state');
    ok(defined $state->{control}, 'state has control');
    is($state->{control}->operation(), 'Start', 'one() state control is Start');
};

subtest 'cfg_state walks children to find control_head' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $bindings = Chalk::Bootstrap::Bindings->new();

    # Child has control_head, parent does not
    my $child = Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => [],
        position     => 0,
        bindings     => $bindings,
        control_head => $start,
    );
    my $parent = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$child],
        position => 0,
    );

    my $state = $parent->cfg_state();
    ok(defined $state, 'cfg_state walks children to find control_head');
    is($state->{control}, $start, 'control found via child control_head');
};

subtest 'cfg_state walks children to find structural annotations' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node = $factory->make('If', control => $start, condition => $cond);

    # Child has if_node annotation, parent does not
    my $child = Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => [],
        position     => 0,
        bindings     => Chalk::Bootstrap::Bindings->new(),
        control_head => $start,
        annotations  => { if_node => $if_node },
    );
    my $parent = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$child],
        position => 0,
    );

    my $state = $parent->cfg_state();
    ok(defined $state, 'cfg_state returns state when child has control_head+annotations');
    is($state->{if_node}, $if_node, 'if_node found via child annotations');
};

subtest 'reset_cache creates new singleton with new bindings' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();
    ok(defined $one->bindings(), 'one has bindings before reset');

    $sa->reset_cache();
    my $one2 = $sa->one();

    ok(defined $one2->bindings(), 'new one() after reset has bindings');
    isnt(refaddr($one), refaddr($one2), 'reset creates a new singleton');
    is($one2->control_head()->operation(), 'Start', 'new one() has Start control_head');
};

subtest 'update_scope and update_annotations propagate to result via multiply' => sub {
    # Verify that calling update_scope/update_annotations inside an action
    # results in the bindings and annotations being on the result context.
    {
        no warnings 'once';
        *FakeActionsForScope::Foo = sub ($self, $ctx) {
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            my $bindings = Chalk::Bootstrap::Bindings->new();
            $sa->update_scope($bindings);
            $sa->update_annotations({ from_action => 1 });
            return undef;
        };
    }

    my $sa_with_action = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => bless {}, 'FakeActionsForScope',
    );
    $sa_with_action->reset_cache();

    my $one = $sa_with_action->one();
    my $complete_ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$one],
        position    => 0,
        annotations => {
            complete  => true,
            rule_name => 'Foo',
            alt_idx   => 0,
            pos       => 0,
            origin    => 0,
        },
    );
    my $result = $sa_with_action->multiply($one, $complete_ctx);

    ok(defined $result, 'multiply with action returns result');
    ok(defined $result->bindings(), 'result has bindings from update_scope');
    is($result->control_head()->operation(), 'Start', 'result control_head is Start');
    is($result->annotations()->{from_action}, 1, 'result annotations has from_action=1');
};

done_testing();
