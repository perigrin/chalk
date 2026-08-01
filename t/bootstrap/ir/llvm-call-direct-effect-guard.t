# ABOUTME: Teeth for _lower_call_direct's effectful-callee GAP guard (Slice B
# ABOUTME: Commit 1), covering BOTH effect-attachment paths: Return.control_in
# ABOUTME: and Return.inputs[1..] (a defensive guard; see body for reachability).
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

subtest 'effectful callee via Return.control_in (Print, not Start) GAPs' => sub {
    my $f       = Chalk::IR::NodeFactory->new;
    my $start   = $f->make('Start');
    my $str     = $f->make('Constant', value => 'x', const_type => 'string');
    my $print   = $f->make('Print', inputs => [$str]);
    $print->set_control_in($start);
    my $value   = $f->make('Constant', value => 2, const_type => 'integer');
    my $ret     = $f->make_cfg('Return', inputs => [$value]);
    $ret->set_control_in($print);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        resolved_graph => $graph,
    );

    my $ctx = mk_ctx();
    my $err = eval { $ctx->_lower_call_direct($call); 1 };
    ok(!$err, 'dies rather than silently dropping the effect');
    like($@, qr/GAP: direct call to 'main::f': callee has effect/,
        'the die names the control-chain-effect GAP');
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
