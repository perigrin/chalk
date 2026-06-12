# ABOUTME: Regex matches are statement effects: per-call identity (two textually-identical
# ABOUTME: matches are distinct nodes) so cached results and capture records are per-point.
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

# A match EXECUTES (it reads its subject and writes capture state) — two
# textually-identical matches at different program points are distinct
# effects. Content hash-consing collapsed them to one node, so the value
# cache served the FIRST match's result at the second program point
# (019eb6ff item 1, live-reproduced: a match re-tested after its subject
# was reassigned returned the stale pre-store result), and the
# _regex_captures side table held ONE offsets record for both points.

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

sub str_const {
    my ($f, $val) = @_;
    my $c = $f->make('Constant', value => $val, const_type => 'string');
    $c->set_representation('Str');
    return $c;
}

subtest 'match ops have per-call identity at the factory' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $s = str_const($f, 'abc');

    my $m1 = $f->make('RegexMatch', pattern => 'b', flags => '', inputs => [$s]);
    my $m2 = $f->make('RegexMatch', pattern => 'b', flags => '', inputs => [$s]);
    isnt($m1->id, $m2->id, 'identical RegexMatch nodes are distinct');

    my $qr = $f->make('Constant', value => 'b', const_type => 'regex');
    $qr->set_representation('Regex');
    my $a1 = $f->make('Match', inputs => [$s, $qr]);
    my $a2 = $f->make('Match', inputs => [$s, $qr]);
    isnt($a1->id, $a2->id, 'identical Match (qr-apply) nodes are distinct');

    my $n1 = $f->make('NotMatch', inputs => [$s, $qr]);
    my $n2 = $f->make('NotMatch', inputs => [$s, $qr]);
    isnt($n1->id, $n2->id, 'identical NotMatch nodes are distinct');

    my $b1 = $f->make('BacktickExpr', inputs => [$s]);
    my $b2 = $f->make('BacktickExpr', inputs => [$s]);
    isnt($b1->id, $b2->id, 'identical BacktickExpr (qx) nodes are distinct');
};

# my $s = "b"; my $y = ($s =~ /b/); $s = "x"; my $z = ($s =~ /b/); return $z;
# perl: the second match tests the NEW subject -> false.
subtest 'match re-tested after subject reassign sees the new value' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $ns = $f->make('Constant', value => '$s', const_type => 'string');
    my $vs = $f->make('VarDecl', inputs => [$ns, str_const($f, 'b')]);
    $vs->set_representation('Str');

    my $rs1 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs1->set_representation('Str');
    my $m1 = $f->make('RegexMatch', pattern => 'b', flags => '', inputs => [$rs1]);
    $m1->set_representation('Bool');
    my $ny = $f->make('Constant', value => '$y', const_type => 'string');
    my $vy = $f->make('VarDecl', inputs => [$ny, $m1]);
    $vy->set_representation('Bool');

    my $rsL = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    my $asg = $f->make('Assign', inputs => [$rsL, str_const($f, 'x')]);
    $asg->set_representation('Str');

    my $rs2 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    my $m2 = $f->make('RegexMatch', pattern => 'b', flags => '', inputs => [$rs2]);
    $m2->set_representation('Bool');
    isnt($m2->id, $m1->id, 'precondition: the two matches are distinct nodes');
    my $nz = $f->make('Constant', value => '$z', const_type => 'string');
    my $vz = $f->make('VarDecl', inputs => [$nz, $m2]);
    $vz->set_representation('Bool');

    my $rzF = $f->make('PadAccess', targ => 0, varname => '$z', inputs => [$vz]);
    $rzF->set_representation('Bool');
    my $ret = $f->make_cfg('Return', inputs => [$rzF]);
    $ret->set_control_in($vz);
    $vz->set_control_in($asg);
    $asg->set_control_in($vy);
    $vy->set_control_in($vs);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Bool:', 'the second match tests the reassigned subject (perl: false)');
};

# my $s = "aa x"; $s =~ /(a+)/; my $p = $1;
# $s = "aaa x"; $s =~ /(a+)/; my $q = $1;
# return $p . "-" . $q;   perl: "aa-aaa" — each $1 belongs to ITS match.
subtest 'capture records are per program point' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $ns = $f->make('Constant', value => '$s', const_type => 'string');
    my $vs = $f->make('VarDecl', inputs => [$ns, str_const($f, 'aa x')]);
    $vs->set_representation('Str');

    my $rs1 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs1->set_representation('Str');
    my $m1 = $f->make('RegexMatch', pattern => '(a+)', flags => '', inputs => [$rs1]);
    $m1->set_representation('Bool');
    my $cap1 = $f->make('RegexCapture', n => 1, inputs => [$m1]);
    $cap1->set_representation('Str');
    my $np = $f->make('Constant', value => '$p', const_type => 'string');
    my $vp = $f->make('VarDecl', inputs => [$np, $cap1]);
    $vp->set_representation('Str');

    my $rsL = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    my $asg = $f->make('Assign', inputs => [$rsL, str_const($f, 'aaa x')]);
    $asg->set_representation('Str');

    my $rs2 = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    my $m2 = $f->make('RegexMatch', pattern => '(a+)', flags => '', inputs => [$rs2]);
    $m2->set_representation('Bool');
    my $cap2 = $f->make('RegexCapture', n => 1, inputs => [$m2]);
    $cap2->set_representation('Str');
    my $nq = $f->make('Constant', value => '$q', const_type => 'string');
    my $vq = $f->make('VarDecl', inputs => [$nq, $cap2]);
    $vq->set_representation('Str');

    my $rp = $f->make('PadAccess', targ => 0, varname => '$p', inputs => [$vp]);
    $rp->set_representation('Str');
    my $rq = $f->make('PadAccess', targ => 1, varname => '$q', inputs => [$vq]);
    $rq->set_representation('Str');
    my $dash = str_const($f, '-');
    my $c1 = $f->make('Concat', inputs => [$rp, $dash]);
    $c1->set_representation('Str');
    my $c2 = $f->make('Concat', inputs => [$c1, $rq]);
    $c2->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$c2]);
    $ret->set_control_in($vq);
    $vq->set_control_in($asg);
    $asg->set_control_in($vp);
    $vp->set_control_in($vs);

    my ($out, $exit) = run_lli(Chalk::Target::LLVM->lower($ret));
    is($exit, 0, 'lli exits 0');
    is($out, 'Str:aa-aaa', 'each $1 reads its own match record (perl: aa-aaa)');
};

done_testing;
