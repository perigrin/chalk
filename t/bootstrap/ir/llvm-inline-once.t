# ABOUTME: Regression test -- an inlined direct-call callee must lower ONCE.
# ABOUTME: _lower_call_direct is reached from both process_control_node (the
# ABOUTME: Call's own statement position) and lower_value (the Return's value
# ABOUTME: input, the same Call node); without caching its result, the
# ABOUTME: callee's effects and result subgraph are inlined twice.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

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
    my $callee_start = $f->make('Start');
    my $msg = $f->make('Constant', value => "x\n", const_type => 'string');
    $msg->set_representation('Str');
    my $print = $f->make('Print', inputs => [$msg]);
    $print->set_control_in($callee_start);
    my $two = $f->make('Constant', value => 2, const_type => 'integer');
    $two->set_representation('Int');
    my $callee_ret = $f->make_cfg('Return', inputs => [$two]);
    $callee_ret->set_control_in($print);
    my $callee_graph = Chalk::IR::Graph->new(
        start   => $callee_start,
        returns => [$callee_ret],
    );

    # Caller: my $r = f(); $r;
    my $start = $f->make('Start');
    my $call = $f->make('Call',
        dispatch_kind  => 'direct',
        name           => 'main::f',
        target         => mk_target($callee_graph),
    );
    $call->set_representation('Int');
    $call->set_control_in($start);

    my $rname = $f->make('Constant', value => '$r', const_type => 'string');
    my $vdecl = $f->make('VarDecl', inputs => [$rname, $call]);
    $vdecl->set_representation('Int');
    $vdecl->set_control_in($call);

    my $rread = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vdecl]);
    $rread->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$rread]);
    $ret->set_control_in($vdecl);

    Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, 'the graph lowers without a GAP') or diag $@;
    ok(defined $ll && length $ll, 'lowering produced IR') or return;

    # Exactly ONE printf: the callee's inlined `print "x\n"`. The bug doubles
    # it (the Call is reached both as a statement and as the Return's value),
    # producing two. program_mode emits no result-print epilogue, so this
    # count is the callee's print alone.
    my $printf_calls = () = $ll =~ /call i32 \(i8\*, \.\.\.\) \@printf/g;
    is($printf_calls, 1, 'exactly one printf call: the callee print is inlined once')
        or diag $ll;

    # Count in the IR is static; RUN it to prove the effect fires once.
    require File::Temp;
    my ($lfh, $lf) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll;
    close $lfh;
    my $out  = qx($LLI $lf 2>&1);
    my $exit = $? >> 8;
    is($exit, 0, 'lli exits 0');
    is($out, "x\n", 'the inlined callee print runs exactly once at runtime');

    my $string_globals = () = $ll =~ /\@str_const_\d+ = /g;
    is($string_globals, 1, 'exactly one string constant global for the "x\n" literal')
        or diag $ll;
};

done_testing;
