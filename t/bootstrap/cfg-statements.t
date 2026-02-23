# ABOUTME: Tests that cfg_state carries statement lists per control region.
# ABOUTME: Verifies the eager pinning approach for Sea of Nodes code generation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;

# --- Test 1: cfg_state accepts and returns statements field ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    my $stmt1 = $factory->make('Constant', const_type => 'string', value => 'hello');

    $sa->set_cfg_state($ctx, {
        control    => $start,
        scope      => Chalk::Bootstrap::Scope->new(),
        statements => [$stmt1],
    });

    my $state = $sa->cfg_state($ctx);
    ok(defined $state, 'cfg_state returns state with statements');
    is(ref($state->{statements}), 'ARRAY', 'statements is an arrayref');
    is(scalar($state->{statements}->@*), 1, 'statements has one entry');
    is($state->{statements}->[0], $stmt1, 'statement is the expected node');
}

# --- Test 2: cfg_state accepts if_node, true_proj, false_proj references ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
    my $else_stmt = $factory->make('Constant', const_type => 'integer', value => 99);

    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        then_stmts => [$then_stmt],
        else_stmts => [$else_stmt],
        if_node    => $if_node,
        true_proj  => $true_proj,
        false_proj => $false_proj,
    });

    my $state = $sa->cfg_state($ctx);
    ok(defined $state, 'cfg_state with if structure exists');
    is($state->{control}->operation(), 'Region', 'control is Region');
    is($state->{if_node}->operation(), 'If', 'if_node is If');
    is($state->{true_proj}->operation(), 'Proj', 'true_proj is Proj');
    is($state->{false_proj}->operation(), 'Proj', 'false_proj is Proj');
    is(ref($state->{then_stmts}), 'ARRAY', 'then_stmts is array');
    is(ref($state->{else_stmts}), 'ARRAY', 'else_stmts is array');
    is($state->{then_stmts}->[0], $then_stmt, 'then_stmts contains expected node');
    is($state->{else_stmts}->[0], $else_stmt, 'else_stmts contains expected node');
}

# --- Test 3: cfg_state accepts loop structure references ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop      = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);
    my $region    = $factory->make('Region', controls => [$exit_proj]);

    my $body_stmt = $factory->make('Constant', const_type => 'string', value => 'body');
    my $iterator  = $factory->make('Constant', const_type => 'string', value => '$x');
    my $list_node = $factory->make('Constant', const_type => 'string', value => 'list');

    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        body_stmts => [$body_stmt],
        loop       => $loop,
        loop_if    => $loop_if,
        body_proj  => $body_proj,
        exit_proj  => $exit_proj,
        iterator   => $iterator,
        list       => $list_node,
    });

    my $state = $sa->cfg_state($ctx);
    ok(defined $state, 'cfg_state with loop structure exists');
    is($state->{control}->operation(), 'Region', 'control is Region');
    is($state->{loop}->operation(), 'Loop', 'loop is Loop');
    is($state->{loop_if}->operation(), 'If', 'loop_if is If');
    is($state->{body_proj}->operation(), 'Proj', 'body_proj is Proj');
    is($state->{exit_proj}->operation(), 'Proj', 'exit_proj is Proj');
    is(ref($state->{body_stmts}), 'ARRAY', 'body_stmts is array');
    is($state->{body_stmts}->[0], $body_stmt, 'body_stmts contains expected node');
    is($state->{iterator}, $iterator, 'iterator stored');
    is($state->{list}, $list_node, 'list stored');
}

done_testing();
