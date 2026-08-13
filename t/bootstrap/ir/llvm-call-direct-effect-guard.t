# ABOUTME: Teeth for _lower_call_direct's effectful-callee handling (Slice B
# ABOUTME: Commits 1+2-print): a straight-line Print-only control chain now
# ABOUTME: inlines; every other effect shape (Assign, Return.inputs[1..]) GAPs.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM::Context;

sub mk_ctx { Chalk::Target::LLVM::Context->new }

subtest 'pure callee (Return.control_in = Start, inputs = [value]) still inlines' => sub {
    my $f       = Chalk::IR::NodeFactory->new;
    my $start   = $f->make('Start');
    my $value   = $f->make('Constant', value => 2, const_type => 'integer');
    $value->set_representation('Int');
    my $ret     = $f->make_cfg('Return', inputs => [$value]);
    $ret->set_control_in($start);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        resolved_graph => $graph,
    );

    my $ctx = mk_ctx();
    my $out = eval { $ctx->_lower_call_direct($call) };
    ok(!$@, 'no GAP for a pure callee') or diag $@;
    ok(defined $out, 'lowering returned a value ref');
};

# Slice B Commit 2-print narrowed the guard: a STRAIGHT-LINE Print-only
# control chain (Print -> ... -> Start, no Region/Loop/If/Assign) is now
# threaded in program order rather than GAPping (see
# _collect_straight_line_effect_chain / _lower_inlined_effects_then_value).
# The GAP is preserved for every OTHER effect shape (below).
subtest 'effectful callee via Return.control_in (straight-line Print, not Start) inlines' => sub {
    my $f       = Chalk::IR::NodeFactory->new;
    my $start   = $f->make('Start');
    my $str     = $f->make('Constant', value => 'x', const_type => 'string');
    $str->set_representation('Str');
    my $print   = $f->make('Print', inputs => [$str]);
    $print->set_control_in($start);
    my $value   = $f->make('Constant', value => 2, const_type => 'integer');
    $value->set_representation('Int');
    my $ret     = $f->make_cfg('Return', inputs => [$value]);
    $ret->set_control_in($print);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        resolved_graph => $graph,
    );

    my $ctx = mk_ctx();
    my $out = eval { $ctx->_lower_call_direct($call) };
    ok(!$@, 'no GAP for a straight-line print-only callee') or diag $@;
    ok(defined $out, 'lowering returned a value ref');
};

subtest 'effectful callee via Return.control_in (Assign, not Start/Print) still GAPs' => sub {
    my $f       = Chalk::IR::NodeFactory->new;
    my $start   = $f->make('Start');
    my $name_c  = $f->make('Constant', value => 's', const_type => 'string');
    my $init    = $f->make('Constant', value => 1, const_type => 'integer');
    $init->set_representation('Int');
    my $vd      = $f->make('VarDecl', inputs => [$name_c, $init]);
    my $rhs     = $f->make('Constant', value => 5, const_type => 'integer');
    $rhs->set_representation('Int');
    my $assign  = $f->make('Assign', inputs => [$vd, $rhs]);
    $assign->set_control_in($start);
    my $value   = $f->make('Constant', value => 2, const_type => 'integer');
    $value->set_representation('Int');
    my $ret     = $f->make_cfg('Return', inputs => [$value]);
    $ret->set_control_in($assign);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        resolved_graph => $graph,
    );

    my $ctx = mk_ctx();
    my $err = eval { $ctx->_lower_call_direct($call); 1 };

    # The GUARD half: refusing is correct as long as the effect cannot be
    # carried. Silently dropping it would be a miscompile, so this assertion
    # holds regardless of whether the capability ever lands.
    ok(!$err, 'dies rather than silently dropping the effect');

    # The GAP half. An effect-carrying callee IS meant to compile one day --
    # real `define` + `call` emission (F3) closes it, at which point the
    # inliner's declination becomes a choice rather than a wall.
    #
    # TODO rather than an asserted GAP: asserting the refusal would go RED the
    # day F3 lands, punishing the fix. As a TODO the same event is a surprise
    # success.
    TODO: {
        local $TODO = 'an effect-carrying callee needs real define+call '
                    . 'emission (F3); the inliner is the only call mechanism';
        my $ctx2 = mk_ctx();
        my $ok = eval { $ctx2->_lower_call_direct($call); 1 };
        ok($ok, 'a direct call to an effect-carrying callee lowers');
    }
};

# The inputs[1..] void-statement-effect shape (a trailing void Call carried as
# an extra Return input rather than demoted to control_in) is documented at
# JSON.pm:983-988/993-997 but is NOT emitted by any live producer today:
# perl5-son moved ALL control threading (including trailing void calls) onto
# control_in at produce time (commit 344fc075, "FromOptree sets control_in at
# build time" -- superseding the earlier bab7363 flattened-inputs scheme that
# JSON.pm's comment describes). Chalk::Bootstrap::Perl::Actions.pm's three
# Return construction sites (~451, ~1069, ~1443) likewise always pass a
# single-element inputs array. This subtest hand-builds the shape defensively
# (mirroring the loader's own seed predicate at JSON.pm:993-997: a blessed
# node with a defined control_in, riding in inputs[1..]) so the guard closes
# structurally even though no corpus case can reach it via the real pipeline.
subtest 'effectful callee via Return.inputs[1..] (defensive; no live producer) GAPs' => sub {
    my $f       = Chalk::IR::NodeFactory->new;
    my $start   = $f->make('Start');
    my $str     = $f->make('Constant', value => 'x', const_type => 'string');
    my $void_call = $f->make('Call',
        dispatch_kind => 'direct',
        name          => 'main::side_effect',
        inputs        => [$str],
    );
    $void_call->set_control_in($start);
    my $value = $f->make('Constant', value => 2, const_type => 'integer');
    $value->set_representation('Int');
    # Return.control_in is Start (the pure-check alone would pass); the
    # trailing void effect rides as an EXTRA Return input, per the documented
    # convention (JSON.pm:983-988) where inputs[0] is the value and
    # inputs[1..] carries trailing void statement-effects -- exactly the
    # shape that would mis-select the effect as the return value if
    # _lower_call_direct's `inputs->[-1]` selection ran unguarded.
    my $ret = $f->make_cfg('Return', inputs => [$value, $void_call]);
    $ret->set_control_in($start);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        resolved_graph => $graph,
    );

    my $ctx = mk_ctx();
    my $err = eval { $ctx->_lower_call_direct($call); 1 };
    ok(!$err, 'dies rather than silently dropping the effect or mis-selecting it as the return value');
    like($@, qr/carried as extra Return inputs/,
        'the die names the inputs-carried variant specifically (not the control_in guard)');
};

done_testing;
