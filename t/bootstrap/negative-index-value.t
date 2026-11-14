# ABOUTME: Guards negative-index array-read VALUE lowering (from-the-end adjustment, 019f2fd3).
# ABOUTME: $a[-1] on a 3-element array must lower to the last element (3), not 0.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);
use Chalk::Target::LLVM;
use Chalk::IR::NodeFactory;

# Append a Print of the returned value onto the graph's EXISTING control chain,
# after the last effect, and return Undef instead: a program's observable
# contract is what it prints. The brackets separate "printed the empty string"
# from "printed nothing at all".
sub print_program ($ret) {
    my $val  = $ret->inputs->[0];
    my $repr = $val->stamp // 'Int';
    my $f    = Chalk::IR::NodeFactory->new;
    my $str = $repr eq 'Str' ? $val : do {
        my $c = $f->make( 'Coerce',
            inputs => [$val], from_repr => $repr, to_repr => 'Str' );
        $c->set_stamp('Str');
        $c;
    };
    my $lb = $f->make( 'Constant', value => '[', const_type => 'string' );
    $lb->set_stamp('Str');
    my $rb = $f->make( 'Constant', value => ']', const_type => 'string' );
    $rb->set_stamp('Str');
    my $print = $f->make( 'Print', inputs => [ $lb, $str, $rb ] );
    $print->set_control_in( $ret->control_in );
    my $u = $f->make( 'Constant', value => undef, const_type => 'undef' );
    $u->set_stamp('Undef');
    my $nret = $f->make_cfg( 'Return', inputs => [$u] );
    $nret->set_control_in($print);
    return $nret;
}

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

# Compile $body through B::SoN -> loader -> Target::LLVM -> lli and return
# what the program prints for corpus_case's value (see print_program). The array read lowering must apply perl's
# from-the-end index adjustment (idx < 0 ? idx + len : idx) before the
# bounds-checked load.
sub run_i64 ($body) {
    my $src = "package main;\nsub corpus_case { $body }\n";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return (undef, "no JSON") unless $json =~ /\S/;
    my $graphs = from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $g = $graphs->{'main::corpus_case'} or return (undef, "no graph");
    my $ret = $g->returns->[0] or return (undef, "no Return");
    my $ll  = Chalk::Target::LLVM->lower(print_program($ret), (defined $mop ? (mop => $mop) : ()));
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    my $exit = $? >> 8;
    return (undef, "lli exit $exit: $out") if $exit != 0;
    return ($out, undef);
}

# The value prints between brackets: an element as [n], undef as [] -- so an
# out-of-range miss is told from a wrong element or a 0.
#
# A negative in-range index reads from the end. Bilateral coverage: not just the
# boundary (-1) but a non-boundary (-2) so an off-by-one adjustment is caught.
subtest 'negative in-range index reads from the end (019f2fd3)' => sub {
    my ($v1, $e1) = run_i64('my @a = (1, 2, 3); $a[-1]');
    is($v1, '[3]', '$a[-1] over (1,2,3) is the last element 3') or diag($e1 // '');

    my ($v2, $e2) = run_i64('my @a = (1, 2, 3); $a[-2]');
    is($v2, '[2]', '$a[-2] over (1,2,3) is 2 (non-boundary: catches off-by-one)') or diag($e2 // '');

    my ($v3, $e3) = run_i64('my @a = (1, 2, 3); $a[-3]');
    is($v3, '[1]', '$a[-3] over (1,2,3) is the first element 1') or diag($e3 // '');
};

# The adjustment must NOT disturb the already-correct positive path.
subtest 'positive index unchanged (teeth)' => sub {
    my ($v0) = run_i64('my @a = (1, 2, 3); $a[0]');
    is($v0, '[1]', '$a[0] is 1');
    my ($v2) = run_i64('my @a = (1, 2, 3); $a[2]');
    is($v2, '[3]', '$a[2] is 3');
};

# Negative-out-of-range stays a miss: idx + len is still negative, so the
# unsigned bounds check must still reject it. The loader stamps a STATIC OOB
# read as Slot, so the program prints undef: []. $a[-4]/$a[-5] over a 3-element
# array are past the start.
subtest 'negative out-of-range stays a miss (teeth)' => sub {
    my ($v4) = run_i64('my @a = (1, 2, 3); $a[-4]');
    is($v4, '[]', '$a[-4] is out of range past the start -> undef');
    my ($v5) = run_i64('my @a = (1, 2, 3); $a[-5]');
    is($v5, '[]', '$a[-5] is out of range past the start -> undef');
};

# A variable index the loader cannot statically resolve stays Int repr and
# reaches the backend's Int read path -- so this directly exercises the
# from-the-end adjustment (both the hit and the still-negative OOB miss, where
# idx + len stays huge-unsigned under the icmp ult bounds check).
subtest 'variable (dynamic) negative index goes through the backend adjustment' => sub {
    my ($h1) = run_i64('my @a = (1, 2, 3); my $i = -1; $a[$i]');
    is($h1, '[3]', 'dynamic $i=-1 reads the last element 3 (backend adjustment)');

    my ($h3) = run_i64('my @a = (1, 2, 3); my $i = -3; $a[$i]');
    is($h3, '[1]', 'dynamic $i=-3 reads the first element 1');

    my ($m4) = run_i64('my @a = (1, 2, 3); my $i = -4; $a[$i]');
    is($m4, '[]', 'dynamic $i=-4 stays OOB (idx+len still negative) -> undef');
};

done_testing();
