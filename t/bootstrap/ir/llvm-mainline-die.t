# ABOUTME: Regression test for the mainline-die miscompile: an Unwind on the
# ABOUTME: Return's control chain must emit an abort, not be silently dropped.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;

# ---------------------------------------------------------------------------
# REGRESSION (zhi 019fbf8d, found via corpus T2c during son-ir-divorce i5).
#
# A `die` INSIDE an if/else arm has its Unwind hanging off the arm's Proj, and
# _process_if_node finds it via _find_unwind_consumer. A MAINLINE `die` — one
# not inside a branch — puts its Unwind directly on Return.control_in instead,
# so it arrives through the control-chain walk. process_control_node ignored
# Unwind entirely, so the abort was never emitted: the program fell through and
# returned a value where perl aborts.
#
# Measured before the fix: lli exit 0 printing "Int:1"; perl exit 255 "boom".
# That is a GAP-not-miscompile INVARIANT VIOLATION — a silent wrong answer.
#
# The corpus CANNOT guard this: its equality harness cannot assert a process
# abort against the perl die-oracle (see corpus T2b/T2c, both declared GAPs for
# exactly that harness reason, not a backend one). So the guard lives here.
# ---------------------------------------------------------------------------

subtest 'a mainline die (Unwind on the control chain) emits the abort' => sub {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $msg = $f->make('Constant', value => "boom\n", const_type => 'string');
    $msg->set_representation('Str');

    my $unwind = $f->make_cfg('Unwind', inputs => [$msg]);
    $unwind->set_control_in($start);

    my $val = $f->make('Constant', value => 1, const_type => 'integer');
    $val->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$val]);
    $ret->set_control_in($unwind);     # <-- the mainline shape

    Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
    ok(!$@, 'the mainline-die graph lowers without a GAP') or diag $@;
    ok(defined $ll && length $ll, 'lowering produced IR') or return;

    my $aborts = () = $ll =~ /call void \@exit\(i32 255\)/g;
    is($aborts, 1, 'exactly one abort emitted: not dropped, and not doubled')
        or diag $ll;

    like($ll, qr/declare void \@exit\(i32\)/,
        '@exit is declared in the prologue');
};

subtest 'the abort is idempotent per Unwind node' => sub {
    # _emit_unwind_terminator guards by node id so an Unwind reachable via BOTH
    # the control chain and an If-arm Proj aborts once. Calling it twice on the
    # same node must not emit a second `call @exit`.
    my $f      = Chalk::IR::NodeFactory->new;
    my $start  = $f->make('Start');
    my $msg    = $f->make('Constant', value => "x\n", const_type => 'string');
    $msg->set_representation('Str');
    my $unwind = $f->make_cfg('Unwind', inputs => [$msg]);
    $unwind->set_control_in($start);

    my $ctx = Chalk::Target::LLVM::Context->new;
    $ctx->_emit_unwind_terminator($unwind, 'first');
    $ctx->_emit_unwind_terminator($unwind, 'second (must be suppressed)');

    my $emitted = join "\n",
        map { join "\n", ($_->{insts} // [])->@* } ($ctx->blocks // [])->@*;
    my $n = () = $emitted =~ /call void \@exit\(i32 255\)/g;
    is($n, 1, 'the second emit for the same Unwind is suppressed');
};

done_testing;
