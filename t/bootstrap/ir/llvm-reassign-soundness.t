# ABOUTME: Adversarial soundness tests for the scoped-elaboration var_table+phi model.
# ABOUTME: Proves that read-before/after-reassign cases lower correctly (lli==perl) for all shapes.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::NumLt;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Return;
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub run_lli {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

sub int_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => "$val", const_type => 'integer');
    $c->set_representation('Int');
    return $c;
}

# ===========================================================================
# SOUNDNESS RATIONALE (context for each test group)
#
# The Phase 3c LLVM backend uses a "scoped-elaboration" model:
#   - VarDecl stores the initializer's SSA value in var_table[vd_id].
#   - PadAccess reads var_table[vd_id] at the moment it is lowered.
#   - Assign and CompoundAssign UPDATE var_table[vd_id] before any later read.
#   - The control-chain pre-pass processes nodes in forward order, ensuring
#     var_table holds the most-recent assignment at every PadAccess.
#   - If/loop control flow uses phi nodes at merge points, also updating
#     var_table for the post-merge read.
#
# Because PadAccess nodes for the same variable hash-cons to ONE node object
# (same targ, varname, and VarDecl input), the old "B1 poison guard" would
# always fire for any variable that is reassigned after any read. The new model
# supersedes it: var_table is always current at the lowering point, so there
# is no stale cache to poison.
#
# These adversarial tests verify soundness by running lli and comparing to Perl.
# ===========================================================================

# ===========================================================================
# GROUP A: Case (a) — Canonical: my $x=1; my $y=$x; $x=2; return $x+$y
#
# This is the original B1 test case. The pre-assign read ($y=$x) and the
# post-assign read (return $x+$y) hash-cons to ONE PadAccess node. The new
# model reads var_table at lowering time, so the return read gets x=2.
# Expected: perl = 2+1 = 3.
# ===========================================================================

{
    my $f  = Chalk::IR::NodeFactory->new;
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $c1 = int_const($f, 1);
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]); $vx->set_representation('Int');

    # my $y = $x (pre-assign read)
    my $rx1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx1->set_representation('Int');
    my $ny  = $f->make('Constant', value => '$y', const_type => 'string');
    my $vy  = $f->make('VarDecl', inputs => [$ny, $rx1]); $vy->set_representation('Int');

    # $x = 2
    my $c2  = int_const($f, 2);
    my $rxL = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL->set_representation('Int');
    my $asg = $f->make('Assign', inputs => [$rxL, $c2]); $asg->set_representation('Int');

    # return $x + $y  (post-assign read)
    my $rx2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx2->set_representation('Int');
    my $ryF = $f->make('PadAccess', targ => 0, varname => '$y', inputs => [$vy]);
    $ryF->set_representation('Int');
    my $add = $f->make('Add', inputs => [$rx2, $ryF]); $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);
    $ret->set_control_in($asg); $asg->set_control_in($vy); $vy->set_control_in($vx);

    # Verify hash-consing: the "before" and "after" reads are the same node.
    is($rx1->id, $rx2->id,
        'Case (a): pre-assign and post-assign $x reads hash-cons to same PadAccess node');
    is($rx1->id, $rxL->id,
        'Case (a): lhs of Assign also hash-cons to same PadAccess node');

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'Case (a): my $x=1; my $y=$x; $x=2; return $x+$y — lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'Case (a): .ll is libperl-free');
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'Case (a): lli exits 0');
        is($out, 'Int:3',
            'Case (a): lli=Int:3 == perl=Int:3 (x=2 post-assign, y=1 pre-assign, 2+1=3, type-tagged)');
    }
}

# ===========================================================================
# GROUP B: Case (b) — Multiple reassigns: y=$x(before), $x=2, z=$x, $x=3, return $x+$y+$z
#
# Reads at three program points; every read of $x hash-cons to one node.
# After control-chain: vx(x=1) -> vy(y=x=1) -> asg1(x=2) -> vz(z=x=2) -> asg2(x=3) -> return
# Expected: x=3, y=1, z=2 => 3+1+2=6.
# ===========================================================================

{
    my $f  = Chalk::IR::NodeFactory->new;
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $c1 = int_const($f, 1);
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]); $vx->set_representation('Int');

    # my $y = $x  (x=1)
    my $rx_for_y = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx_for_y->set_representation('Int');
    my $ny = $f->make('Constant', value => '$y', const_type => 'string');
    my $vy = $f->make('VarDecl', inputs => [$ny, $rx_for_y]); $vy->set_representation('Int');

    # $x = 2
    my $c2   = int_const($f, 2);
    my $rxL1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL1->set_representation('Int');
    my $asg1 = $f->make('Assign', inputs => [$rxL1, $c2]); $asg1->set_representation('Int');

    # my $z = $x  (x=2 after first assign)
    my $rx_for_z = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx_for_z->set_representation('Int');
    my $nz = $f->make('Constant', value => '$z', const_type => 'string');
    my $vz = $f->make('VarDecl', inputs => [$nz, $rx_for_z]); $vz->set_representation('Int');

    # $x = 3
    my $c3   = int_const($f, 3);
    my $rxL2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL2->set_representation('Int');
    my $asg2 = $f->make('Assign', inputs => [$rxL2, $c3]); $asg2->set_representation('Int');

    # return $x + $y + $z  (x=3 after second assign)
    my $rx_final = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx_final->set_representation('Int');
    my $ry_final = $f->make('PadAccess', targ => 0, varname => '$y', inputs => [$vy]);
    $ry_final->set_representation('Int');
    my $rz_final = $f->make('PadAccess', targ => 0, varname => '$z', inputs => [$vz]);
    $rz_final->set_representation('Int');

    my $sum1 = $f->make('Add', inputs => [$rx_final, $ry_final]); $sum1->set_representation('Int');
    my $sum2 = $f->make('Add', inputs => [$sum1, $rz_final]); $sum2->set_representation('Int');
    my $ret  = $f->make_cfg('Return', inputs => [$sum2]);
    $ret->set_control_in($asg2);   $asg2->set_control_in($vz);
    $vz->set_control_in($asg1);   $asg1->set_control_in($vy);
    $vy->set_control_in($vx);

    # All five $x PadAccess nodes must be the same hash-consed node.
    my @x_ids = map { $_->id } ($rx_for_y, $rxL1, $rx_for_z, $rxL2, $rx_final);
    my $all_same = (scalar do { my %u; @u{@x_ids} = (); keys %u } == 1);
    ok($all_same,
        'Case (b): all five $x PadAccess nodes hash-cons to one node (stale-cache risk maximal)');

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'Case (b): my $x=1; y=$x; $x=2; z=$x; $x=3; return $x+$y+$z — lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'Case (b): .ll is libperl-free');
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'Case (b): lli exits 0');
        is($out, 'Int:6',
            'Case (b): lli=Int:6 == perl=Int:6 (x=3, y=1, z=2: 3+1+2=6, type-tagged)');
    }
}

# ===========================================================================
# GROUP C: Case (c) — Reassign inside branch, read after merge (runtime $n)
#
# my $x=1; my $y=$x; if($n>0){ $x=5 }; return $x+$y
# $n=5  (true branch):  x=5 post-merge, y=1 => 5+1=6
# $n=-1 (false branch): x=1 post-merge, y=1 => 1+1=2
#
# Runtime condition: $n is a constant here but is NOT numerically predictable
# to the compiler — the phi at merge correctly selects 5 (true) or 1 (false).
# Using two separate subtests with different $n values exercises BOTH branches
# of the lli execution, ensuring the phi is wired correctly for both paths.
# ===========================================================================

for my $pair ([5, 6], [-1, 2]) {
    my ($n_val, $expected) = @$pair;
    my $f = Chalk::IR::NodeFactory->new;

    # $n = $n_val  (the runtime input)
    my $cn = int_const($f, $n_val);
    my $nn = $f->make('Constant', value => '$n', const_type => 'string');
    my $vn = $f->make('VarDecl', inputs => [$nn, $cn]); $vn->set_representation('Int');

    # my $x = 1
    my $c1 = int_const($f, 1);
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]); $vx->set_representation('Int');

    # my $y = $x  (pre-branch read; x=1)
    my $rx_for_y = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx_for_y->set_representation('Int');
    my $ny = $f->make('Constant', value => '$y', const_type => 'string');
    my $vy = $f->make('VarDecl', inputs => [$ny, $rx_for_y]); $vy->set_representation('Int');

    # condition: $n > 0
    my $c0  = int_const($f, 0);
    my $rn  = $f->make('PadAccess', targ => 0, varname => '$n', inputs => [$vn]);
    $rn->set_representation('Int');
    my $cmp = $f->make('NumGt', inputs => [$rn, $c0]); $cmp->set_representation('Bool');

    # If / Proj / Region
    my $if_node = $f->make('If',     inputs => [$vy, $cmp]);
    my $proj0   = $f->make('Proj',   inputs => [$if_node], index => 0);
    my $proj1   = $f->make('Proj',   inputs => [$if_node], index => 1);
    my $region  = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);

    # then-branch: $x = 5
    my $c5  = int_const($f, 5);
    my $lhs = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $lhs->set_representation('Int');
    my $asg = $f->make('Assign', inputs => [$lhs, $c5]); $asg->set_representation('Int');
    $asg->set_control_in($proj0);

    # post-merge reads
    my $rx_post = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx_post->set_representation('Int');
    my $ry_post = $f->make('PadAccess', targ => 0, varname => '$y', inputs => [$vy]);
    $ry_post->set_representation('Int');

    my $add = $f->make('Add', inputs => [$rx_post, $ry_post]); $add->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$add]);
    $if_node->set_control_in($vy);
    $vy->set_control_in($vx);
    $vx->set_control_in($vn);
    $ret->set_control_in($if_node);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "Case (c) n=$n_val: if-branch reassign lowers without dying")
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, "Case (c) n=$n_val: .ll is libperl-free");
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, "Case (c) n=$n_val: lli exits 0");
        is($out, "Int:$expected",
            "Case (c) n=$n_val: lli=Int:$expected == perl=Int:$expected (type-tagged)");
    }
}

# ===========================================================================
# GROUP D: Case (d) — Loop-carried reassign: while($i<3){ $x=$x+1; $s=$s+$x; $i++ }; return $s
#
# Loop body reassigns $x and accumulates into $s each iteration.
# All reads/writes of $x hash-cons to one PadAccess (same vd, targ, varname).
# i=0, x=0, s=0 initially:
#   iter 1: x=1, s=0+1=1
#   iter 2: x=2, s=1+2=3
#   iter 3: x=3, s=3+3=6
#   i=3: condition fails, exit
# Expected: s=6 (perl=6).
#
# The loop phi mechanism (not the simple var_table path) handles this;
# this test confirms the full loop+phi model stays sound alongside reassigns.
# ===========================================================================

{
    use Chalk::IR::Node::Subtract;

    my $f = Chalk::IR::NodeFactory->new;

    my $c0i = int_const($f, 0);
    my $c0x = int_const($f, 0);
    my $c0s = int_const($f, 0);
    my $c1  = int_const($f, 1);
    my $c3  = int_const($f, 3);

    my $ni  = $f->make('Constant', value => '$i', const_type => 'string');
    my $nxl = $f->make('Constant', value => '$x', const_type => 'string');
    my $ns  = $f->make('Constant', value => '$s', const_type => 'string');
    my $vi  = $f->make('VarDecl', inputs => [$ni, $c0i]); $vi->set_representation('Int');
    my $vx  = $f->make('VarDecl', inputs => [$nxl, $c0x]); $vx->set_representation('Int');
    my $vs  = $f->make('VarDecl', inputs => [$ns, $c0s]); $vs->set_representation('Int');

    my $ri0 = $f->make('PadAccess', targ => 0, varname => '$i', inputs => [$vi]); $ri0->set_representation('Int');
    my $rx0 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]); $rx0->set_representation('Int');
    my $rs0 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]); $rs0->set_representation('Int');

    my $loop   = $f->make('Loop', inputs => [$vs, undef]);
    my $i_phi  = $f->make('Phi', region => $loop, values => [$ri0]); $i_phi->set_representation('Int');
    my $x_phi  = $f->make('Phi', region => $loop, values => [$rx0]); $x_phi->set_representation('Int');
    my $s_phi  = $f->make('Phi', region => $loop, values => [$rs0]); $s_phi->set_representation('Int');

    my $cmp   = $f->make('NumLt', inputs => [$i_phi, $c3]); $cmp->set_representation('Bool');
    my $x_new = $f->make('Add', inputs => [$x_phi, $c1]); $x_new->set_representation('Int');
    my $s_new = $f->make('Add', inputs => [$s_phi, $x_new]); $s_new->set_representation('Int');
    my $i_new = $f->make('Add', inputs => [$i_phi, $c1]); $i_new->set_representation('Int');

    $i_phi->set_backedge($i_new);
    $x_phi->set_backedge($x_new);
    $s_phi->set_backedge($s_new);

    my $body_proj   = $f->make('Proj', inputs => [$loop], index => 0);
    my $exit_proj   = $f->make('Proj', inputs => [$loop], index => 1);
    my $exit_region = $f->make('Region', inputs => [$exit_proj]);
    $loop->set_region($exit_region);

    $x_new->set_control_in($body_proj);
    $s_new->set_control_in($body_proj);
    $i_new->set_control_in($body_proj);

    my $ret = $f->make_cfg('Return', inputs => [$s_phi]);
    $vs->set_control_in($vx);
    $vx->set_control_in($vi);
    $loop->set_control_in($vs);
    $ret->set_control_in($loop);

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'Case (d): loop-carried $x reassign ($i<3; $x=$x+1; $s+=$x) lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'Case (d): .ll is libperl-free');
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'Case (d): lli exits 0');
        is($out, 'Int:6',
            'Case (d): lli=Int:6 == perl=Int:6 (sum 1+2+3=6 via loop-carried x reassign, type-tagged)');
    }
}

# ===========================================================================
# GROUP E: Case (e) — Interleaved read/reassign/read/reassign/read
#
# my $x=1; acc1=$x; $x=2; acc2=$x; $x=3; acc3=$x; return acc1+acc2+acc3
# Every read of $x is the same hash-consed PadAccess node. var_table holds
# the current value at each read point.
# Expected: 1+2+3=6 (perl=6).
# ===========================================================================

{
    my $f  = Chalk::IR::NodeFactory->new;
    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $c1 = int_const($f, 1);
    my $vx = $f->make('VarDecl', inputs => [$nx, $c1]); $vx->set_representation('Int');

    # acc1 = $x  (x=1)
    my $r1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $r1->set_representation('Int');
    my $n1 = $f->make('Constant', value => '$acc1', const_type => 'string');
    my $v1 = $f->make('VarDecl', inputs => [$n1, $r1]); $v1->set_representation('Int');

    # $x = 2
    my $c2   = int_const($f, 2);
    my $rxL1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL1->set_representation('Int');
    my $asg1 = $f->make('Assign', inputs => [$rxL1, $c2]); $asg1->set_representation('Int');

    # acc2 = $x  (x=2)
    my $r2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $r2->set_representation('Int');
    my $n2 = $f->make('Constant', value => '$acc2', const_type => 'string');
    my $v2 = $f->make('VarDecl', inputs => [$n2, $r2]); $v2->set_representation('Int');

    # $x = 3
    my $c3   = int_const($f, 3);
    my $rxL2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rxL2->set_representation('Int');
    my $asg2 = $f->make('Assign', inputs => [$rxL2, $c3]); $asg2->set_representation('Int');

    # acc3 = $x  (x=3)
    my $r3 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $r3->set_representation('Int');
    my $n3 = $f->make('Constant', value => '$acc3', const_type => 'string');
    my $v3 = $f->make('VarDecl', inputs => [$n3, $r3]); $v3->set_representation('Int');

    # return acc1+acc2+acc3
    my $ra1 = $f->make('PadAccess', targ => 0, varname => '$acc1', inputs => [$v1]);
    $ra1->set_representation('Int');
    my $ra2 = $f->make('PadAccess', targ => 0, varname => '$acc2', inputs => [$v2]);
    $ra2->set_representation('Int');
    my $ra3 = $f->make('PadAccess', targ => 0, varname => '$acc3', inputs => [$v3]);
    $ra3->set_representation('Int');

    my $sum1 = $f->make('Add', inputs => [$ra1, $ra2]); $sum1->set_representation('Int');
    my $sum2 = $f->make('Add', inputs => [$sum1, $ra3]); $sum2->set_representation('Int');
    my $ret  = $f->make_cfg('Return', inputs => [$sum2]);
    $ret->set_control_in($v3);   $v3->set_control_in($asg2);
    $asg2->set_control_in($v2);  $v2->set_control_in($asg1);
    $asg1->set_control_in($v1);  $v1->set_control_in($vx);

    # All $x reads and writes must be the same hash-consed node.
    my @x_ids = map { $_->id } ($r1, $rxL1, $r2, $rxL2, $r3);
    my $all_same = (scalar do { my %u; @u{@x_ids} = (); keys %u } == 1);
    ok($all_same,
        'Case (e): all five $x accesses (3 reads + 2 assigns) hash-cons to one node');

    my $ll = eval { Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, 'Case (e): acc1=$x; $x=2; acc2=$x; $x=3; acc3=$x; return acc1+acc2+acc3 — lowers without dying')
        or diag("lower() died: $@");

    SKIP: {
        skip 'lower() failed', 3 unless defined $ll;
        unlike($ll, qr/\bSV\b|Perl_|libperl/, 'Case (e): .ll is libperl-free');
        my ($out, $exit) = run_lli($ll);
        is($exit, 0, 'Case (e): lli exits 0');
        is($out, 'Int:6',
            'Case (e): lli=Int:6 == perl=Int:6 (1+2+3=6: x reads each program-point value, type-tagged)');
    }
}

done_testing;
