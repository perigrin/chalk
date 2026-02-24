# ABOUTME: Tests that the Perl target can emit code from cfg_state structure.
# ABOUTME: Verifies emit_from_cfg_state dispatches to emit_cfg_if and emit_cfg_loop.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Perl::Target::Perl;

# --- Test 1: emit_from_cfg_state for if/else ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
    my $else_stmt = $factory->make('Constant', const_type => 'integer', value => 99);

    my $ctx = $sa->one();
    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        then_stmts => [$then_stmt],
        else_stmts => [$else_stmt],
        if_node    => $if_node,
        true_proj  => $true_proj,
        false_proj => $false_proj,
    });

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(defined $code, 'emit_from_cfg_state returns code for if/else');
    like($code, qr/if\s*\(/, 'emitted code contains if');
    like($code, qr/42/, 'emitted code contains then body value');
    like($code, qr/99/, 'emitted code contains else body value');
    like($code, qr/else/, 'emitted code contains else keyword');
}

# --- Test 2: emit_from_cfg_state for if without else ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
    my $region     = $factory->make('Region', controls => [$true_proj, $false_proj]);

    my $then_stmt = $factory->make('Constant', const_type => 'integer', value => 42);

    my $ctx = $sa->one();
    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        then_stmts => [$then_stmt],
        else_stmts => undef,
        if_node    => $if_node,
        true_proj  => $true_proj,
        false_proj => $false_proj,
    });

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(defined $code, 'emit_from_cfg_state returns code for if-no-else');
    like($code, qr/if\s*\(/, 'contains if');
    like($code, qr/42/, 'contains then body');
}

# --- Test 3: emit_from_cfg_state for loop ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop      = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);
    my $region    = $factory->make('Region', controls => [$exit_proj]);

    my $body_stmt = $factory->make('Constant', const_type => 'string', value => 'body_work');

    my $ctx = $sa->one();
    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        body_stmts => [$body_stmt],
        loop       => $loop,
        loop_if    => $loop_if,
        body_proj  => $body_proj,
        exit_proj  => $exit_proj,
    });

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(defined $code, 'emit_from_cfg_state returns code for loop');
    like($code, qr/while/, 'emitted code contains while');
}

# --- Test 4: emit_from_cfg_state for foreach loop ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $loop_cond = $factory->make('Constant', const_type => 'string', value => '__loop_bound__');
    my $loop      = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);
    my $loop_if   = $factory->make('If', control => $loop, condition => $loop_cond);
    my $body_proj = $factory->make('Proj', source => $loop_if, index => 0);
    my $exit_proj = $factory->make('Proj', source => $loop_if, index => 1);
    my $region    = $factory->make('Region', controls => [$exit_proj]);

    my $iterator = $factory->make('Constant', const_type => 'string', value => '$x');
    my $list = [
        $factory->make('Constant', const_type => 'integer', value => 1),
        $factory->make('Constant', const_type => 'integer', value => 2),
    ];

    my $ctx = $sa->one();
    $sa->set_cfg_state($ctx, {
        control    => $region,
        scope      => Chalk::Bootstrap::Scope->new(),
        body_stmts => [],
        loop       => $loop,
        loop_if    => $loop_if,
        body_proj  => $body_proj,
        exit_proj  => $exit_proj,
        iterator   => $iterator,
        list       => $list,
    });

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(defined $code, 'emit_from_cfg_state returns code for foreach');
    like($code, qr/for\s+my\s+\$x/, 'foreach via emit_from_cfg_state uses for my syntax');
    unlike($code, qr/while/, 'foreach via emit_from_cfg_state does NOT fall back to while');
}

# --- Test 5: emit_from_cfg_state returns undef for plain state ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    my $start = $factory->make('Start');
    $sa->set_cfg_state($ctx, {
        control => $start,
        scope   => Chalk::Bootstrap::Scope->new(),
    });

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(!defined $code, 'emit_from_cfg_state returns undef for plain state (no control flow)');
}

# --- Test 6: emit_from_cfg_state returns undef when no cfg_state exists ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = $sa->one();
    # No cfg_state set at all
    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(!defined $code, 'emit_from_cfg_state returns undef when no cfg_state exists');
}

# --- Test 7: emit_cfg_if with empty stmts produces no body content ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $start = $factory->make('Start');
    my $cond  = $factory->make('Constant', const_type => 'integer', value => 1);
    my $if_node    = $factory->make('If', control => $start, condition => $cond);
    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_cfg_if($if_node, $true_proj, $false_proj, [], []);
    ok(defined $code, 'emit_cfg_if with empty stmts returns code');
    like($code, qr/if\s*\(/, 'empty-stmts if has condition');
    unlike($code, qr/else/, 'empty-stmts if has no else');
}

done_testing();
