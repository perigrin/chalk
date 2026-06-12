# ABOUTME: Typed aggregate pointers (%Array*/%Hash*) resolve at the point of use; a table
# ABOUTME: keyed by node id served a stale pointer after the container variable was reassigned.
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

# _arr_table/_hash_table memoized the i8* -> %Array*/%Hash* bitcast PER NODE
# ID, populated once and never invalidated. A container variable reassigned
# to a different aggregate kept serving the OLD aggregate's typed pointer at
# every later subscript (019eb6ff item 3) — Family-B re-lowers the PadAccess
# (fresh i8*) but the table read ignored it. The typed pointer must resolve
# from the value the container lowers to AT THE USE.

sub run_lli {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
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

# my $r = [1]; $r = [9]; return $r->[0];   perl: 9
subtest 'subscript after ref reassign reads the new array' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $a1 = $f->make('ArrayRef', inputs => [int_const($f, 1)]);
    $a1->set_representation('ArrayRef');
    my $nr = $f->make('Constant', value => '$r', const_type => 'string');
    my $vr = $f->make('VarDecl', inputs => [$nr, $a1]);
    $vr->set_representation('ArrayRef');

    my $rr0 = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    $rr0->set_representation('ArrayRef');
    my $sub0 = $f->make('Subscript', inputs => [$rr0, int_const($f, 0)]);
    $sub0->set_representation('Int');
    my $np = $f->make('Constant', value => '$p', const_type => 'string');
    my $vp = $f->make('VarDecl', inputs => [$np, $sub0]);
    $vp->set_representation('Int');

    my $a2 = $f->make('ArrayRef', inputs => [int_const($f, 9)]);
    $a2->set_representation('ArrayRef');
    my $rrL = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    my $asg = $f->make('Assign', inputs => [$rrL, $a2]);
    $asg->set_representation('ArrayRef');

    my $rr1 = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    $rr1->set_representation('ArrayRef');
    my $sub1 = $f->make('Subscript', inputs => [$rr1, int_const($f, 0)]);
    $sub1->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$sub1]);
    $ret->set_control_in($asg);
    $asg->set_control_in($vp);
    $vp->set_control_in($vr);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:9', 'the subscript reads the NEW array (perl: 9)');
};

# my $r = [1]; my $p = $r->[0]; $r = [9]; $r->[0] = 7; my $q = $r->[0];
# return $p + $q;   perl: 1 + 7 = 8 — the element STORE after reassign must
# hit the new array too (the Assign(Subscript-lvalue) consumer site).
subtest 'element store after ref reassign hits the new array' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $a1 = $f->make('ArrayRef', inputs => [int_const($f, 1)]);
    $a1->set_representation('ArrayRef');
    my $nr = $f->make('Constant', value => '$r', const_type => 'string');
    my $vr = $f->make('VarDecl', inputs => [$nr, $a1]);
    $vr->set_representation('ArrayRef');

    my $rr0 = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    $rr0->set_representation('ArrayRef');
    my $sub0 = $f->make('Subscript', inputs => [$rr0, int_const($f, 0)]);
    $sub0->set_representation('Int');
    my $np = $f->make('Constant', value => '$p', const_type => 'string');
    my $vp = $f->make('VarDecl', inputs => [$np, $sub0]);
    $vp->set_representation('Int');

    my $a2 = $f->make('ArrayRef', inputs => [int_const($f, 9)]);
    $a2->set_representation('ArrayRef');
    my $rrL = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    my $asg = $f->make('Assign', inputs => [$rrL, $a2]);
    $asg->set_representation('ArrayRef');

    my $rr1 = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    $rr1->set_representation('ArrayRef');
    my $store_lv = $f->make('Subscript', inputs => [$rr1, int_const($f, 0)]);
    $store_lv->set_representation('Int');
    my $st = $f->make('Assign', inputs => [$store_lv, int_const($f, 7)]);
    $st->set_representation('Int');

    my $rr2 = $f->make('PadAccess', targ => 0, varname => '$r', inputs => [$vr]);
    $rr2->set_representation('ArrayRef');
    my $sub2 = $f->make('Subscript', inputs => [$rr2, int_const($f, 0)]);
    $sub2->set_representation('Int');
    my $nq = $f->make('Constant', value => '$q', const_type => 'string');
    my $vq = $f->make('VarDecl', inputs => [$nq, $sub2]);
    $vq->set_representation('Int');

    my $rp = $f->make('PadAccess', targ => 0, varname => '$p', inputs => [$vp]);
    $rp->set_representation('Int');
    my $rq = $f->make('PadAccess', targ => 1, varname => '$q', inputs => [$vq]);
    $rq->set_representation('Int');
    my $sum = $f->make('Add', inputs => [$rp, $rq]);
    $sum->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$sum]);
    $ret->set_control_in($vq);
    $vq->set_control_in($st);
    $st->set_control_in($asg);
    $asg->set_control_in($vp);
    $vp->set_control_in($vr);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Int:8', 'pre-reassign read keeps 1; the store hits the new array (perl: 8)');
};

done_testing;
