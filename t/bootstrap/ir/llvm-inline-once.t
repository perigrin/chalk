# ABOUTME: Regression test -- an inlined direct-call callee must lower ONCE.
# ABOUTME: _lower_call_direct is reached from both process_control_node (the
# ABOUTME: Call's own statement position) and lower_value (the Return's value
# ABOUTME: input, the same Call node); without caching its result, the
# ABOUTME: callee's effects and result subgraph are inlined twice.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use Chalk::CodeGen::Harness::Rooted qw(rooted);

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;

my $LLI = q{/usr/lib/llvm-15/bin/lli};
unless (-x $LLI) {
    plan skip_all => qq{lli not found at $LLI};
}

# ---------------------------------------------------------------------------
# THE BUG: _lower_call_direct never writes its result into $self->{cache}, so
# a Call node reached twice (once as a statement via process_control_node,
# once as the Return's value via lower_value) re-runs the inline from
# scratch. Source shape: `sub f { print "x\n"; 2 } my $r = f(); $r;` -- f()
# is a statement (its print effect must run) AND its result feeds $r, which
# is returned. Measured before the fix: two `call i32 @printf` and two
# separate string-constant globals for the one "x\n" literal.
# ---------------------------------------------------------------------------

# A direct Call carries its callee METAOBJECT (step 1d), not a bare graph --
# the backend reads target->graph.
sub mk_target {
    my ($graph) = @_;
    require Chalk::MOP;
    my $mop = Chalk::MOP->new;
    return $mop->for_class('main')->declare_sub('f', graph => $graph);
}

subtest 'an inlined effectful callee used as both a statement and a value lowers once' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Callee: sub f { print "x\n"; 2 }
    # Each graph its own Start (make_cfg): `make('Start')` hash-conses to ONE
    # node, which hung the caller's Call and the callee's Print off the same
    # control -- a fork the backend refuses rather than drop one of them.
    my $callee_start = $f->make_cfg('Start');
    my $msg = $f->make('Constant', value => "x\n", const_type => 'string');
    $msg->set_stamp('Str');
    my $print = $f->make('Print', inputs => [$msg]);
    $print->set_control_in($callee_start);
    my $two = $f->make('Constant', value => 2, const_type => 'integer');
    $two->set_stamp('Int');
    my $callee_ret = $f->make_cfg('Return', inputs => [$two]);
    $callee_ret->set_control_in($print);
    my $callee_graph = Chalk::IR::Graph->new(
        start   => $callee_start,
        returns => [$callee_ret],
    );

    # Caller: my $r = f(); $r;
    my $start = $f->make_cfg('Start');
    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        target         => mk_target($callee_graph),
    );
    $call->set_stamp('Int');
    $call->set_control_in($start);

    my $rname = $f->make('Constant', value => '$r', const_type => 'string');
    my $vdecl = $f->make('VarDecl', inputs => [$rname, $call]);
    $vdecl->set_stamp('Int');
    $vdecl->set_control_in($call);

    my $rread = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 'r', inputs => [$vdecl]);
    $rread->set_stamp('Int');

    my $ret = $f->make_cfg('Return', inputs => [$rread]);
    $ret->set_control_in($vdecl);

    Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    # T2 REFUSES IT, by its reason (only the retired fallback lowered this
    # graph): refused by name, never lowered wrong.
    my $t2_ll = eval { Chalk::Target::LLVM->lower(rooted($ret), program_mode => 1) };
    ok(!defined $t2_ll, 'T2 lowers no module for it');
    like($@, qr/GAP: T2: out of its slices \(\Qa statement VarDecl\E\)/, "refused by T2's reason");
};

done_testing;
