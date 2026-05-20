# ABOUTME: Tests the cfg_state compatibility shim on SemanticAction.
# ABOUTME: Verifies that cfg_state reads from scope field and individual annotations.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::NodeFactory;
use Scalar::Util 'refaddr';

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# ---------------------------------------------------------------------------
# Phase 3: New API — cfg_state reads from scope field + individual annotations
# ---------------------------------------------------------------------------

subtest 'cfg_state returns undef for context with no scope' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new( focus => 'v' );
    my $state = $ctx->cfg_state();
    ok(!defined $state, 'cfg_state returns undef when no scope on context');
};

subtest 'cfg_state reads control from scope field' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $scope = Chalk::Bootstrap::Scope->new()->with_control($start);
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'v',
        scope => $scope,
    );

    my $state = $ctx->cfg_state();
    ok(defined $state, 'cfg_state returns state when scope present');
    is($state->{control}, $start, 'cfg_state control comes from scope->control()');
    is($state->{scope}, $scope, 'cfg_state scope is the scope object');
};

subtest 'cfg_state reads structural annotations from context annotations' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node = $factory->make('If', control => $start, condition => $cond);
    my $region  = $factory->make('Region', controls => [$if_node]);
    my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);

    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [],
        position    => 0,
        scope       => Chalk::Bootstrap::Scope->new()->with_control($region),
        annotations => {
            if_node    => $if_node,
            then_stmts => [$then_stmt],
        },
    );

    my $state = $ctx->cfg_state();
    ok(defined $state, 'cfg_state returns state');
    is($state->{control}, $region, 'control from scope');
    is($state->{if_node}, $if_node, 'if_node from annotations');
    is(ref($state->{then_stmts}), 'ARRAY', 'then_stmts is array');
    is($state->{then_stmts}->[0], $then_stmt, 'then_stmts contains expected node');
};

subtest 'one() sets scope on singleton context' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();

    ok(defined $one->scope(), 'one() context has scope');
    ok(defined $one->scope()->control(), 'one() scope has control');
    is($one->scope()->control()->operation(), 'Start', 'one() control is Start');
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

subtest 'cfg_state walks children to find scope' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $scope = Chalk::Bootstrap::Scope->new()->with_control($start);

    # Child has scope, parent does not
    my $child = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [],
        position => 0,
        scope    => $scope,
    );
    my $parent = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$child],
        position => 0,
    );

    my $state = $parent->cfg_state();
    ok(defined $state, 'cfg_state walks children to find scope');
    is($state->{control}, $start, 'control found via child scope');
};

subtest 'cfg_state walks children to find structural annotations' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node = $factory->make('If', control => $start, condition => $cond);

    # Child has if_node annotation, parent does not
    my $child = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [],
        position    => 0,
        scope       => Chalk::Bootstrap::Scope->new()->with_control($start),
        annotations => { if_node => $if_node },
    );
    my $parent = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$child],
        position => 0,
    );

    my $state = $parent->cfg_state();
    ok(defined $state, 'cfg_state returns state when child has scope+annotations');
    is($state->{if_node}, $if_node, 'if_node found via child annotations');
};

subtest 'reset_cache creates new singleton with new scope' => sub {
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();
    $sa->reset_cache();

    my $one = $sa->one();
    ok(defined $one->scope(), 'one has scope before reset');

    $sa->reset_cache();
    my $one2 = $sa->one();

    ok(defined $one2->scope(), 'new one() after reset has scope');
    isnt(refaddr($one), refaddr($one2), 'reset creates a new singleton');
    is($one2->scope()->control()->operation(), 'Start', 'new one() has Start control');
};

subtest 'update_scope and update_annotations propagate to result via multiply' => sub {
    # Verify that calling update_scope/update_annotations inside an action
    # results in the scope and annotations being on the result context.
    {
        no warnings 'once';
        *FakeActionsForScope::Foo = sub ($self, $ctx) {
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
            my $start = $factory->make('Start');
            my $scope = Chalk::Bootstrap::Scope->new()->with_control($start);
            $sa->update_scope($scope);
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
    ok(defined $result->scope(), 'result has scope from update_scope');
    is($result->scope()->control()->operation(), 'Start', 'result scope has Start control');
    is($result->annotations()->{from_action}, 1, 'result annotations has from_action=1');
};

done_testing();
