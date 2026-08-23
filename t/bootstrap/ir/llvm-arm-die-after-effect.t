# ABOUTME: Regression test for the effect-before-die miscompile (F2): a `die`
# ABOUTME: preceded by another effect in an if-arm must still emit the abort.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Target::LLVM;

# ---------------------------------------------------------------------------
# THE BUG (F2): _find_unwind_consumer($proj) in _process_branch_from_if does a
# ONE-HOP consumer scan of the arm's Proj to find the arm's Unwind. That only
# works when `die` is the FIRST statement in the arm -- then Unwind.control_in
# IS the Proj, so Unwind is a direct consumer of it.
#
# When an effect (e.g. Print) precedes the die, the producer sets
# Unwind.control_in to THAT EFFECT (the current control at the point of the
# die), not to the Proj. Unwind is then a consumer of the Print, not of the
# Proj -- so the one-hop scan returns undef, the abort is never emitted, and
# the arm falls through to a plain `br` to the merge block.
#
#   my $x = 1; if ($x > 0) { print "t\n"; die "d\n" } else { print "e\n" }
#   print "end\n";
#     -> perl : exit 255, stdout "t\n"
#     -> chalk (before fix): exit 0, stdout "t\nend\n"  WRONG
#
# No corpus case can catch this: son-corpus-wide.t:88 turns any nonzero lli
# exit into "lli exited N" — a lowering failure — so a case whose correct
# behavior IS a nonzero exit cannot be pinned there, and the taken-die legs are
# GAP-declared. This unit test is the only guard. (The same defect in the
# file-scoring path has been removed; ProgramRunner compares exit status.)
# ---------------------------------------------------------------------------

subtest 'an if-arm die preceded by a Print still emits the abort' => sub {
    my $f     = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');

    my $xn = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$xn, do {
        my $one = $f->make('Constant', value => 1, const_type => 'integer');
        $one->set_representation('Int');
        $one;
    }]);
    $vx->set_representation('Int');
    $vx->set_control_in($start);

    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $zero = $f->make('Constant', value => 0, const_type => 'integer');
    $zero->set_representation('Int');
    my $cmp = $f->make('NumGt', inputs => [$rx, $zero]);
    $cmp->set_representation('Boolean');

    my $if_node = $f->make('If', inputs => [$vx, $cmp]);
    my $proj0   = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);
    $if_node->set_control_in($vx);

    # then-arm: print "t\n"; die "d\n"   (effect BEFORE die)
    my $tmsg  = $f->make('Constant', value => "t\n", const_type => 'string');
    $tmsg->set_representation('Str');
    my $print = $f->make('Print', inputs => [$tmsg]);
    $print->set_control_in($proj0);

    my $dmsg   = $f->make('Constant', value => "d\n", const_type => 'string');
    $dmsg->set_representation('Str');
    my $unwind = $f->make_cfg('Unwind', inputs => [$dmsg]);
    $unwind->set_control_in($print);   # <-- the effect-before-die shape

    # else-arm: print "e\n"
    my $emsg   = $f->make('Constant', value => "e\n", const_type => 'string');
    $emsg->set_representation('Str');
    my $eprint = $f->make('Print', inputs => [$emsg]);
    $eprint->set_control_in($proj1);

    # print "end\n" after the if, on the merge Region's control.
    my $endmsg = $f->make('Constant', value => "end\n", const_type => 'string');
    $endmsg->set_representation('Str');
    my $endprint = $f->make('Print', inputs => [$endmsg]);
    $endprint->set_control_in($region);

    my $val = $f->make('Constant', value => 42, const_type => 'integer');
    $val->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$val]);
    $ret->set_control_in($endprint);

    Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $ll = eval { Chalk::Target::LLVM->lower($ret) };
    ok(!$@, 'the effect-before-die graph lowers without a GAP') or diag $@;
    ok(defined $ll && length $ll, 'lowering produced IR') or return;

    like($ll, qr/call void \@exit\(i32 255\)/,
        'the abort (exit 255) is emitted for the die arm');
    like($ll, qr/unreachable/,
        'the taken arm terminates with unreachable, not a fallthrough br');
};

done_testing;
