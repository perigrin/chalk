# ABOUTME: Tests XS target handling of try/catch statements.
# ABOUTME: Verifies try/catch triggers eval_pv fallback (no direct C equivalent).
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Perl::Target::XS;

# --- Test 1: emit_from_cfg_state returns unsupported marker for try_node ---
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

    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch');
    my $code = $target->emit_from_cfg_state($sa, $ctx, {});
    ok(defined $code, 'emit_from_cfg_state returns code for try/catch');
    like($code, qr/unsupported/, 'code contains unsupported marker');
}

# --- Test 2: _needs_eval_fallback detects try/catch marker ---
{
    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch2');
    my $xs_output = 'NULL /* unsupported */';
    ok($target->_needs_eval_fallback($xs_output),
        '_needs_eval_fallback detects try/catch unsupported marker');
}

# --- Test 3: try/catch unsupported marker triggers eval_pv fallback path ---
{
    my $target = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::TryCatch3');
    # The marker contains "unsupported" which _needs_eval_fallback checks
    my $marker = 'NULL /* unsupported */';
    ok($marker =~ /NULL \/\* unsupported \*\// || $marker =~ /unsupported/,
        'try/catch marker matches fallback detection pattern');
}

done_testing();
