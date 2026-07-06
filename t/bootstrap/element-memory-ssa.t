# ABOUTME: End-to-end memory-SSA phase 2a: element read/store ordering (lli == perl).
# ABOUTME: Read-before-store snapshots the pre-store value; branch-guarded store is an honest GAP.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

skip_all "perl5-son not found"  unless -f "$SON/B/SoN.pm";
skip_all "lli not found"        unless -x $LLI;
skip_all "perl 5.42 not found"  unless -x $PERL;

use lib 'lib', 't/lib';
require Chalk::IR::Serialize::JSON;
require Chalk::Target::LLVM;

# Drive a snippet through B::SoN -> Chalk load -> LLVM lower -> lli; return
# ('value', $lli_out) or ('gap', $err) or ('perl', $perl_out).
sub lower_and_run ($body) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh "package main;\nsub corpus_case { $body }\n";
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return ('err', 'no JSON') unless $json =~ /\S/;
    my ($graphs, $mop) = Chalk::IR::Serialize::JSON::from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return ('err', 'no graph');
    my $ll = eval {
        Chalk::Target::LLVM->lower($g->returns->[0],
            (defined $mop ? (mop => $mop) : ()));
    };
    return ('gap', $@) if $@;
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    chomp $out;
    return ('value', $out);
}

sub perl_val ($body) {
    my $out = qx($PERL -e 'my \$r = do { $body }; print defined \$r ? "Int:\$r" : "Undef:"' 2>&1);
    chomp $out;
    return $out;
}

subtest 'read before store snapshots the pre-store value (the WAR fix)' => sub {
    my ($kind, $out) = lower_and_run('my @a=(5,6,7); my $x=$a[0]; $a[0]=99; $x');
    is($kind, 'value', 'lowered (not a GAP)') or return;
    is($out, 'Int:5', 'lli returns 5 (the pre-store value), not 99');
};

subtest 'interleaved read/store observes each program point' => sub {
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); $a[0]=1; my $x=$a[0]; $a[0]=2; $x+$a[0]');
    is($kind, 'value', 'lowered') or return;
    is($out, 'Int:3', 'lli returns 3 (1 + 2), not 4');
};

subtest 'straight-line stores/reads stay correct (regression)' => sub {
    my @cases = (
        ['my @a=(1,2,3); $a[0]=42; $a[0]'          => 'Int:42'],
        ['my @a=(1,2,3); $a[0]=42; $a[1]'          => 'Int:2'],
        ['my @a=(1,2,3); $a[1]=9; $a[1]+$a[0]'     => 'Int:10'],
        ['my %h=(a=>1); $h{a}=5; $h{a}'            => 'Int:5'],
    );
    for my $c (@cases) {
        my ($kind, $out) = lower_and_run($c->[0]);
        is("$kind:$out", "value:$c->[1]", "[$c->[0]] -> $c->[1]");
    }
};

subtest 'a store in a taken if-arm is visible after the branch (2b memory-Phi)' => sub {
    # `if ($c) { $a[0] = 9 } $a[0]` -- the store is control-dependent on the
    # branch; the post-branch read takes the merged memory (memory-Phi). With
    # $c true the store ran -> 9.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $c=1; if($c){$a[0]=9} $a[0]');
    is("$kind:$out", 'value:Int:9', 'store in the taken arm is visible -> 9');
};

subtest 'a store in an UNtaken if-arm is not visible (2b memory-Phi)' => sub {
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $c=0; if($c){$a[0]=9} $a[0]');
    is("$kind:$out", 'value:Int:1', 'store in the untaken arm is not visible -> 1');
};

subtest 'a dropped element read-modify-write GAPs, never miscompiles' => sub {
    # $a[i] += / ++ has a producer bug: the store-back is dropped (zhi 019f342f),
    # so the Add result is DEAD. The backend must GAP loudly rather than lower the
    # following read to the pre-modify value. Legitimate arith-over-element
    # ($a[0]+$a[1], $a[0]=$a[0]+1) is data-reachable and must NOT GAP.
    my ($k1) = lower_and_run('my @a=(1,2,3); $a[0]+=4; $a[0]');
    is($k1, 'gap', 'straight-line element += (dropped store) GAPs');
    my ($k2) = lower_and_run('my @a=(1,2,3); my $c=1; if($c){$a[0]+=4} $a[0]');
    is($k2, 'gap', 'branch-guarded element += (dropped store) GAPs');
    my ($k3, $o3) = lower_and_run('my @a=(1,2,3); $a[0]+$a[1]');
    is("$k3:$o3", 'value:Int:3', 'legit arith over two element reads does NOT GAP');
    my ($k4, $o4) = lower_and_run('my @a=(5,6,7); $a[0]=$a[0]+1; $a[0]');
    is("$k4:$o4", 'value:Int:6', 'element read + explicit store-back does NOT GAP');
};

done_testing();
