# ABOUTME: Tests that TryCatchStatement produces cfg_state with try_node key.
# ABOUTME: Verifies Perl target emits try { ... } catch ($e) { ... } from cfg_state.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::Context;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Bindings;
use Chalk::Bootstrap::Perl::Target::Perl;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;

# --- Test 1: cfg_state accepts try_node, catch_var, try_stmts, catch_stmts ---
{
    my $factory = Chalk::IR::NodeFactory->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 1);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'error');
    # Use a Constant as a marker node for try_node in cfg_state
    my $try_marker = $factory->make('Constant', const_type => 'string', value => '__try__');

    # Build context with scope (Start as control) and structural annotations directly.
    my $ctx = Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => [],
        position     => 0,
        bindings        => Chalk::Bootstrap::Bindings->new(),
        control_head => $start,
        annotations  => {
            try_node    => $try_marker,
            try_stmts   => [$try_stmt],
            catch_var   => '$e',
            catch_stmts => [$catch_stmt],
        },
    );

    my $state = $ctx->cfg_state();
    ok(defined $state, 'cfg_state returns state with try_node');
    ok(defined $state->{try_node}, 'state has try_node');
    is($state->{catch_var}, '$e', 'state has catch_var');
    is(ref($state->{try_stmts}), 'ARRAY', 'try_stmts is array');
    is(ref($state->{catch_stmts}), 'ARRAY', 'catch_stmts is array');
}

# --- Test 2: emit_from_cfg_state dispatches try/catch ---
{
    my $factory = Chalk::IR::NodeFactory->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $start = $factory->make('Start');
    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 42);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'handle_error');
    my $try_marker = $factory->make('Constant', const_type => 'string', value => '__try__');

    # Build context with scope (Start as control) and structural annotations directly.
    my $ctx = Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => [],
        position     => 0,
        bindings        => Chalk::Bootstrap::Bindings->new(),
        control_head => $start,
        annotations  => {
            try_node    => $try_marker,
            try_stmts   => [$try_stmt],
            catch_var   => '$e',
            catch_stmts => [$catch_stmt],
        },
    );

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_from_cfg_state($sa, $ctx);
    ok(defined $code, 'emit_from_cfg_state returns code for try/catch');
    like($code, qr/try\s*\{/, 'emitted code contains try {');
    like($code, qr/catch\s*\(\$e\)\s*\{/, 'emitted code contains catch ($e) {');
    like($code, qr/42/, 'emitted code contains try body value');
    like($code, qr/handle_error/, 'emitted code contains catch body value');
}

# --- Test 3: emit_cfg_try_catch method directly ---
{
    my $factory = Chalk::IR::NodeFactory->new();

    my $try_stmt = $factory->make('Constant', const_type => 'integer', value => 10);
    my $catch_stmt = $factory->make('Constant', const_type => 'string', value => 'rescued');

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new();
    my $code = $target->emit_cfg_try_catch([$try_stmt], '$err', [$catch_stmt]);
    ok(defined $code, 'emit_cfg_try_catch returns code');
    like($code, qr/try\s*\{/, 'code has try {');
    like($code, qr/catch\s*\(\$err\)\s*\{/, 'code has catch ($err) {');
    like($code, qr/10/, 'code has try body value');
    like($code, qr/'rescued'/, 'code has catch body value');
}

# --- Test 4: Full pipeline: parse try/catch and emit Perl ---
{
    my $ir = perl_pipeline();

    SKIP: {
        skip 'Perl grammar failed to parse', 6 unless defined $ir;

        my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
        my $generated = $target->generate($ir);
        $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgTryCatchTest/g;
        eval $generated;
        skip "Generated code failed to compile: $@", 6 if $@;

        my $gen_grammar = Chalk::Grammar::Perl::CfgTryCatchTest::grammar();
        my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
        skip 'IR parser not built', 6 unless defined $parser;

        my $semiring = $parser->semiring();
        my $sa = $semiring->semirings()->[4];

        # Parse simple try/catch wrapped in a class+method so the
        # production MOP+scheduler codegen path can handle it.
        # (Phase 5b migration: bare top-level snippets are out of
        # Chalk's purview; see docs/plans/2026-05-24-class-as-
        # builtin-rejected.md.)
        {
            $semiring->reset_cache();
            my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();

            my $source = <<'END';
class TestTC {
    method m {
        try {
            my $x = 1;
        } catch ($e) {
            die $e;
        }
    }
}
END
            my $result = $parser->parse_value($source);
            ok(defined $result && !$result->is_zero(), 'try/catch parses to IR');
            ok(defined $mop, 'MOP populated');

            # Generate Perl from the MOP via the production path.
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my $out = $perl_target->generate($mop);
            ok(ref($out) eq 'HASH', 'generate returns HashRef[Str]');

            my $code = (values $out->%*)[0] // '';
            ok(length $code, 'Perl code generated from try/catch IR');
            like($code, qr/try\s*\{/, 'generated Perl has try block');
            like($code, qr/catch\s*\(\$e\)\s*\{/, 'generated Perl has catch ($e)');
        }
    }
}

done_testing();
