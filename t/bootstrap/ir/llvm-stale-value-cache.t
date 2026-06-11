# ABOUTME: Pure nodes over mutable-location reads (PadAccess/Subscript/FieldAccess) must
# ABOUTME: re-lower per consumption point; serving them from the value cache reads stale state.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# The lower_value cache memoizes SSA refs by node id. PadAccess was already
# excluded (llvm-reassign-soundness.t), but a PURE node whose transitive
# inputs read a mutable location (PadAccess pad slot, Subscript element,
# FieldAccess field) hash-conses across a mutation and the cache then serves
# the pre-mutation SSA ref at the post-mutation consumption point
# (whole-branch review C1/C2). Such nodes must re-lower at every consumption.
# Side-effecting ops STAY cached: they execute once at their control
# position; re-lowering would double the effect.

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

# my $x = 1; my $y = $x + 10; $x = 2; my $z = $x + 10; return $y + $z;
# The two `$x + 10` Adds hash-cons to ONE node; the cache must not serve
# the pre-assign SSA ref at the $z position. perl: 11 + 12 = 23.
subtest 'pure Add over reassigned PadAccess re-lowers per consumption (C1)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$nx, int_const($f, 1)]);
    $vx->set_representation('Int');

    my $rx1 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx1->set_representation('Int');
    my $c10 = int_const($f, 10);
    my $add1 = $f->make('Add', inputs => [$rx1, $c10]);
    $add1->set_representation('Int');
    my $ny = $f->make('Constant', value => '$y', const_type => 'string');
    my $vy = $f->make('VarDecl', inputs => [$ny, $add1]);
    $vy->set_representation('Int');

    my $rxL = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    my $asg = $f->make('Assign', inputs => [$rxL, int_const($f, 2)]);
    $asg->set_representation('Int');

    my $rx2 = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    my $add2 = $f->make('Add', inputs => [$rx2, $c10]);
    $add2->set_representation('Int');
    is($add2->id, $add1->id, 'precondition: the two pure Adds hash-cons to one node');
    my $nz = $f->make('Constant', value => '$z', const_type => 'string');
    my $vz = $f->make('VarDecl', inputs => [$nz, $add2]);
    $vz->set_representation('Int');

    my $ryF = $f->make('PadAccess', targ => 0, varname => '$y', inputs => [$vy]);
    $ryF->set_representation('Int');
    my $rzF = $f->make('PadAccess', targ => 0, varname => '$z', inputs => [$vz]);
    $rzF->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$ryF, $rzF]);
    $sum->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$sum]);
    $ret->set_control_in($vz);
    $vz->set_control_in($asg);
    $asg->set_control_in($vy);
    $vy->set_control_in($vx);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:23', 'post-assign consumption sees x=2 (perl: 11+12=23)');
};

# my $x = 1; $x = $x + 1; $x = $x + 1; return $x;
# Family-A makes the two Assigns distinct nodes; Family-B makes the shared
# Add re-lower at the second Assign so it reads x=2, not the cached x=1.
subtest 'repeat scalar rebind increments twice (C1+C3 interaction)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $nx = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$nx, int_const($f, 1)]);
    $vx->set_representation('Int');

    my $rx = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Int');
    my $c1 = int_const($f, 1);

    my $add1 = $f->make('Add', inputs => [$rx, $c1]);
    $add1->set_representation('Int');
    my $asg1 = $f->make('Assign', inputs => [$rx, $add1]);
    $asg1->set_representation('Int');

    my $add2 = $f->make('Add', inputs => [$rx, $c1]);
    $add2->set_representation('Int');
    my $asg2 = $f->make('Assign', inputs => [$rx, $add2]);
    $asg2->set_representation('Int');

    isnt($asg1->id, $asg2->id, 'precondition: the two Assigns are distinct (Family-A)');

    my $rxF = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vx]);
    my $ret = $f->make_cfg('Return', inputs => [$rxF]);
    $ret->set_control_in($asg2);
    $asg2->set_control_in($asg1);
    $asg1->set_control_in($vx);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:3', 'two increments both fire (perl: 3)');
};

# my @a = (1,2); my $p = $a[0]; $a[0] = 9; return $a[0];
# The pre-store and post-store element reads hash-cons to ONE Subscript;
# the post-store read must see the stored value. perl: 9.
subtest 'Subscript read-store-read re-reads the element (C2)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $arr = $f->make('ArrayRef', inputs => [int_const($f, 1), int_const($f, 2)]);
    $arr->set_representation('ArrayRef');
    my $i0 = int_const($f, 0);

    my $rd1 = $f->make('Subscript', inputs => [$arr, $i0]);
    $rd1->set_representation('Slot');
    my $np = $f->make('Constant', value => '$p', const_type => 'string');
    my $vp = $f->make('VarDecl', inputs => [$np, $rd1]);
    $vp->set_representation('Slot');

    my $st = $f->make('Assign',
        inputs => [$f->make('Subscript', inputs => [$arr, $i0]), int_const($f, 9)]);
    $st->set_representation('Int');

    my $rd2 = $f->make('Subscript', inputs => [$arr, $i0]);
    $rd2->set_representation('Slot');
    is($rd2->id, $rd1->id, 'precondition: the two element reads hash-cons to one node');

    my $ret = $f->make_cfg('Return', inputs => [$rd2]);
    $ret->set_control_in($st);
    $st->set_control_in($vp);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:9', 'read after element store sees the stored value (perl: 9)');
};

# my @a = (1,2); my $p = $a[0]; $a[0] = 9; return $p;
# Over-correction guard: re-lowering must NOT leak into already-bound
# values. $p was bound BEFORE the store; returning it must give the OLD
# element value (the VarDecl initializer was lowered at the pre-store
# program point and var_table holds that SSA ref). perl: 1.
subtest 'pre-store binding keeps its old value (no over-correction)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $arr = $f->make('ArrayRef', inputs => [int_const($f, 1), int_const($f, 2)]);
    $arr->set_representation('ArrayRef');
    my $i0 = int_const($f, 0);

    my $rd1 = $f->make('Subscript', inputs => [$arr, $i0]);
    $rd1->set_representation('Slot');
    my $np = $f->make('Constant', value => '$p', const_type => 'string');
    my $vp = $f->make('VarDecl', inputs => [$np, $rd1]);
    $vp->set_representation('Slot');

    my $st = $f->make('Assign',
        inputs => [$f->make('Subscript', inputs => [$arr, $i0]), int_const($f, 9)]);
    $st->set_representation('Int');

    my $rp = $f->make('PadAccess', targ => 0, varname => '$p', inputs => [$vp]);
    $rp->set_representation('Slot');

    my $ret = $f->make_cfg('Return', inputs => [$rp]);
    $ret->set_control_in($st);
    $st->set_control_in($vp);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:1', 'value bound before the store keeps the pre-store element (perl: 1)');
};

done_testing;
