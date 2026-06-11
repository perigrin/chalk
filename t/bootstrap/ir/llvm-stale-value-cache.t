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

# my $x = 1; $x += 2; $x += 2; return $x;
# Two textually-identical CompoundAssigns: per-call identity (Family-A) plus
# re-lowered shared Add (Family-B) — both increments must fire. perl: 5.
subtest 'repeat compound assign fires twice (C3 behavioral)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $vd = $f->make('VarDecl', inputs => [
        $f->make('Constant', value => 'x', const_type => 'string'),
        int_const($f, 1),
    ]);
    $vd->set_representation('Int');

    my $pa = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vd]);
    $pa->set_representation('Int');
    my $c2 = int_const($f, 2);

    my $add1 = $f->make('Add', inputs => [$pa, $c2]);
    $add1->set_representation('Int');
    my $ca1 = $f->make('CompoundAssign', op => '+=', inputs => [$pa, $add1]);
    $ca1->set_representation('Int');

    my $add2 = $f->make('Add', inputs => [$pa, $c2]);
    $add2->set_representation('Int');
    my $ca2 = $f->make('CompoundAssign', op => '+=', inputs => [$pa, $add2]);
    $ca2->set_representation('Int');

    isnt($ca1->id, $ca2->id, 'precondition: the two CompoundAssigns are distinct (Family-A)');

    my $ret_pad = $f->make('PadAccess', targ => 0, varname => '$x', inputs => [$vd]);
    $ret_pad->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$ret_pad]);
    $ret->set_control_in($ca2);
    $ca2->set_control_in($ca1);
    $ca1->set_control_in($vd);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:5', 'both += fire (perl: 5)');
};

# class Pt { field $x :param; field $p; field $q;
#            ADJUST { $p = $x; $x = 9; $q = $x } }
# The two field READS of $x hash-cons to one FieldAccess consumed at two
# program points within ONE lowering context (the ADJUST body); the
# post-store read must see 9. perl: p+q = 5+9 = 14.
subtest 'FieldAccess read-store-read within one body re-reads the field (C2)' => sub {
    require Chalk::IR::ClassInfo;
    require Chalk::IR::MethodInfo;
    require Chalk::MOP::Field;

    my $f = Chalk::IR::NodeFactory->new;

    my $mf_x = Chalk::MOP::Field->new(name => 'x', sigil => '$', class => undef,
        fieldix => 0, type => 'Int', attributes => [':param']);
    my $mf_p = Chalk::MOP::Field->new(name => 'p', sigil => '$', class => undef,
        fieldix => 1, type => 'Int', attributes => []);
    my $mf_q = Chalk::MOP::Field->new(name => 'q', sigil => '$', class => undef,
        fieldix => 2, type => 'Int', attributes => []);

    my $fa_x_rd1 = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x_rd1->set_representation('Int');
    my $fa_p_lv = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_p_lv->set_representation('Int');
    my $st_p = $f->make('Assign', inputs => [$fa_p_lv, $fa_x_rd1]);
    $st_p->set_representation('Int');

    my $fa_x_lv = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x_lv->set_representation('Int');
    my $st_x = $f->make('Assign', inputs => [$fa_x_lv, int_const($f, 9)]);
    $st_x->set_representation('Int');

    my $fa_x_rd2 = $f->make('FieldAccess', field_index => 0, field_stash => 'Pt', inputs => []);
    $fa_x_rd2->set_representation('Int');
    is($fa_x_rd2->id, $fa_x_rd1->id,
        'precondition: the two field reads hash-cons to one node');
    my $fa_q_lv = $f->make('FieldAccess', field_index => 2, field_stash => 'Pt', inputs => []);
    $fa_q_lv->set_representation('Int');
    my $st_q = $f->make('Assign', inputs => [$fa_q_lv, $fa_x_rd2]);
    $st_q->set_representation('Int');

    my $fa_p_rd = $f->make('FieldAccess', field_index => 1, field_stash => 'Pt', inputs => []);
    $fa_p_rd->set_representation('Int');
    my $getp = Chalk::IR::MethodInfo->new(name => 'getp', body => [],
        body_node => $fa_p_rd, return_repr => 'Int');
    my $fa_q_rd = $f->make('FieldAccess', field_index => 2, field_stash => 'Pt', inputs => []);
    $fa_q_rd->set_representation('Int');
    my $getq = Chalk::IR::MethodInfo->new(name => 'getq', body => [],
        body_node => $fa_q_rd, return_repr => 'Int');

    my $ci = Chalk::IR::ClassInfo->new(name => 'Pt', methods => [$getp, $getq],
        fields => [$mf_x, $mf_p, $mf_q], adjusts => [[$st_p, $st_x, $st_q]]);

    my $v5 = int_const($f, 5);
    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        param_names => ['x'], inputs => [$ci, $v5]);
    $new->set_representation('Object');
    my $get_p = $f->make('Call', dispatch_kind => 'method', name => 'getp',
        inputs => [$new, $ci]);
    $get_p->set_representation('Int');
    my $get_q = $f->make('Call', dispatch_kind => 'method', name => 'getq',
        inputs => [$new, $ci]);
    $get_q->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$get_p, $get_q]);
    $sum->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$sum]);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:14', 'p keeps the pre-store value, q reads the stored one (perl: 5+9=14)');
};

done_testing;
