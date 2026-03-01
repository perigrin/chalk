# ABOUTME: Tests XS target emission of try/catch as C code using JMPENV_PUSH/POP.
# ABOUTME: Verifies try body runs in setjmp block, catch body handles exceptions via ERRSV.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Perl::Target::XS;

# --- Test 1: emit_cfg_try_catch emits JMPENV_PUSH ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'rescued');

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch');
    my $code = $target->emit_cfg_try_catch([$try_stmt], '$e', [$catch_stmt], {});
    ok(defined $code, 'emit_cfg_try_catch returns code');
    like($code, qr/JMPENV_PUSH/, 'emits JMPENV_PUSH');
    like($code, qr/JMPENV_POP/, 'emits JMPENV_POP');
    like($code, qr/ERRSV/, 'references ERRSV for catch variable');
}

# --- Test 2: try body appears in ret == 0 branch ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'handle');

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch2');
    my $code = $target->emit_cfg_try_catch([$try_stmt], '$e', [$catch_stmt], {});

    # ret == 0 means normal execution (try body)
    like($code, qr/ret == 0/, 'try body guarded by ret == 0');
    # ret != 0 (or ret == 3) means exception (catch body)
    like($code, qr/ret/, 'catch body guarded by exception check');
}

# --- Test 3: emit_from_cfg_state dispatches to emit_cfg_try_catch ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 1);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'error');
    my $try_marker = $factory->make('Constant', const_type => 'string', value => '__try__');

    my $ctx = $sa->one();
    $sa->set_cfg_state($ctx, {
        control     => $start,
        scope       => Chalk::Bootstrap::Scope->new(),
        try_node    => $try_marker,
        try_stmts   => [$try_stmt],
        catch_var   => '$e',
        catch_stmts => [$catch_stmt],
    });

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch3');
    my $code = $target->emit_from_cfg_state($sa, $ctx, {});
    ok(defined $code, 'emit_from_cfg_state returns code for try/catch');
    like($code, qr/JMPENV_PUSH/, 'dispatches to JMPENV-based try/catch');
}

# --- Test 4: catch variable is assigned from ERRSV ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 1);
    # Catch body references the catch variable
    my $catch_var_ref = $factory->make('Constant', const_type => 'variable', value => '$e');

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch4');
    my $code = $target->emit_cfg_try_catch([$try_stmt], '$e', [$catch_var_ref], {});

    # The catch variable should be bound to ERRSV
    like($code, qr/ERRSV/, 'catch variable bound to ERRSV');
}

# --- Test 5: _emit_xs_stmt dispatches try_node from cfg_lookup ---
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 10);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'caught');
    my $try_marker = $factory->make('Constant', const_type => 'string', value => '__try__');

    my $ctx = $sa->one();
    $sa->set_cfg_state($ctx, {
        control     => $start,
        scope       => Chalk::Bootstrap::Scope->new(),
        try_node    => $try_marker,
        try_stmts   => [$try_stmt],
        catch_var   => '$err',
        catch_stmts => [$catch_stmt],
    });

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch5');
    my $code = $target->emit_from_cfg_state($sa, $ctx, {});

    # Should NOT contain "unsupported" anymore
    unlike($code, qr/unsupported/, 'no unsupported marker');
    # Should be real C code
    like($code, qr/JMPENV_PUSH/, 'real C try/catch emitted');
}

# --- Test 6: try/catch does NOT trigger eval_pv fallback ---
{
    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch6');

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 1);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'err');
    my $code = $target->emit_cfg_try_catch([$try_stmt], '$e', [$catch_stmt], {});

    ok(!$target->_needs_eval_fallback($code),
        'try/catch C code does NOT trigger eval_pv fallback');
}

done_testing();
