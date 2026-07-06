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

subtest 'a flat if/else stores in both arms and reads the taken arm (2b-3)' => sub {
    # `if ($c) { $a[0] = 7 } else { $a[0] = 8 } $a[0]` -- BOTH arms store the
    # same element; the post-branch read takes the merged memory (a memory-Phi
    # with two store inputs). c true -> 7, c false -> 8.
    my ($k1, $o1) = lower_and_run('my @a=(1,2,3); my $c=1; if($c){$a[0]=7}else{$a[0]=8} $a[0]');
    is("$k1:$o1", 'value:Int:7', 'c true selects the true arm store -> 7');
    my ($k0, $o0) = lower_and_run('my @a=(1,2,3); my $c=0; if($c){$a[0]=7}else{$a[0]=8} $a[0]');
    is("$k0:$o0", 'value:Int:8', 'c false selects the false arm store -> 8');
};

subtest 'a while-loop element store is visible after the loop (2b-4 memory-Phi)' => sub {
    # `my @a=(1,2,3); my $i=0; while($i<3){$a[$i]=$i*2+10; $i=$i+1} $a[1]` -- the body
    # stores through a loop-header memory-Phi; the post-loop read observes the
    # merged memory. a[1] = 1*2+10 = 12. The store value is deliberately DISTINCT
    # from the initializer (a[1] was 2) so a dropped loop-store / elided memory-Phi
    # would read 2 and fail -- the assertion discriminates a working store, not a
    # value that coincides with the init.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $i=0; while($i<3){$a[$i]=$i*2+10; $i=$i+1} $a[1]');
    is("$kind:$out", 'value:Int:12', 'while-loop element store visible after loop -> 12');
};

subtest 'a foreach-range element store is visible after the loop (2b-4 memory-Phi)' => sub {
    # `my @a=(0,0,0); for my $i (0..2){$a[$i]=$i+1} $a[2]` -- the foreach-range
    # body stores through the loop-header memory-Phi. a[2] = 2+1 = 3.
    my ($kind, $out) = lower_and_run('my @a=(0,0,0); for my $i (0..2){$a[$i]=$i+1} $a[2]');
    is("$kind:$out", 'value:Int:3', 'foreach-range element store visible after loop -> 3');
};

subtest 'a read BEFORE the loop snapshots pre-loop memory (WAR ordering holds)' => sub {
    # `my @a=(5,6,7); my $x=$a[0]; my $i=0; while($i<3){$a[0]=$i; $i=$i+1} $x*10+$a[0]`
    # -- the pre-loop read $x=$a[0] must snapshot the PRE-loop value (5), while the
    # post-loop read $a[0] observes the loop's final store (2). If the header
    # memory-Phi contaminated the earlier read, $x would be 2 and the result 22
    # instead of 5*10+2 = 52.
    my ($kind, $out) = lower_and_run('my @a=(5,6,7); my $x=$a[0]; my $i=0; while($i<3){$a[0]=$i; $i=$i+1} $x*10+$a[0]');
    is("$kind:$out", 'value:Int:52', 'pre-loop read snapshots 5, post-loop read 2 -> 52');
};

subtest 'a NESTED branch-guarded store still GAPs-or-errors, never miscompiles (out of 2b-3 scope)' => sub {
    # Nested branches are out of scope for the flat if/else work. The outer
    # if($c){if($d){...}} inner branch join used to be misread as an
    # EXPR-while-COND loop back-edge and crash the while-loop translator; that
    # crash is fixed (zhi 019f34cc), so the producer now GAPs LOUDLY (the arm
    # does not converge) rather than crashing -- B::SoN emits no graph and
    # lower_and_run returns 'err'. This subtest pins the ANTI-MISCOMPILE
    # invariant (never a value): a future nested lowering (2b-3 composed
    # branches) must stay non-value here -- a correct nested lowering or an
    # honest GAP, never a silently-wrong value.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $c=1; my $d=1; if($c){if($d){$a[0]=7}} $a[0]');
    isnt($kind, 'value', "nested branch store does not silently lower (got $kind:$out)");
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
