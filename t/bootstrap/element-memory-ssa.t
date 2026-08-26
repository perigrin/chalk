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
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
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

subtest 'shift/pop mutate the array; a later read observes the drain' => sub {
    my @cases = (
        # single mutation, then a whole-array read
        ['my @q=(1,2,3); my $x=shift @q; scalar @q'     => 'Int:2'],
        ['my @q=(1,2,3); my $x=pop @q; scalar @q'       => 'Int:2'],
        # after a shift front-drop, $q[0] is the NEW first element
        ['my @q=(10,20,30); my $x=shift @q; $q[0]'      => 'Int:20'],
    );
    for my $c (@cases) {
        my ($kind, $out) = lower_and_run($c->[0]);
        is("$kind:$out", "value:$c->[1]", "[$c->[0]] -> $c->[1]");
    }
};

subtest 'a constant range/list literal expands to all its elements (zhi 019f5942)' => sub {
    # `my @q=(1..4)` constant-folds to a const[AV] whose N elements the producer
    # must expand into an N-element ArrayRef. Reading only the first element built
    # a 1-element array (scalar @q -> 1, a silent miscompile). Now the AV is fully
    # expanded, so scalar @q == 4 and element reads see the whole range.
    my @cases = (
        ['my @q=(1..4); scalar @q'      => 'Int:4'],
        ['my @q=(1..4); $q[2]'          => 'Int:3'],
        ['my @q=(1..4); $q[0]+$q[3]'    => 'Int:5'],
        ['my @q=(2..5); scalar @q'      => 'Int:4'],
        ['my @q=(5..5); scalar @q'      => 'Int:1'],   # single-element range
        # a genuine array-of-one-arrayref (`[...]`, an anonlist) must NOT be
        # flattened by the const-range expansion -- scalar @a is 1, not 3.
        ['my @a=([1,2,3]); scalar @a'   => 'Int:1'],
        ['my @q=(1,2,3); scalar @q'     => 'Int:3'],   # non-folded list, unchanged
    );
    for my $c (@cases) {
        my ($kind, $out) = lower_and_run($c->[0]);
        is("$kind:$out", "value:$c->[1]", "[$c->[0]] -> $c->[1]");
    }
};

subtest 'an element read interleaved between two shifts observes each version (WAR)' => sub {
    # `shift; $p=$q[0]; shift; $r=$q[0]` -- $p must be pinned at the memory
    # version after the FIRST shift, before the second shift advances the elems
    # pointer again. Without freezing the read at its program point, $p sinks to
    # the post-second-shift value (a silent WAR miscompile: 60 instead of 50).
    my ($kind, $out) = lower_and_run(
        'my @q=(10,20,30,40); my $a=shift @q; my $p=$q[0]; my $b=shift @q; my $r=$q[0]; $p+$r');
    is("$kind:$out", 'value:Int:50', 'interleaved shift reads pin per-version -> 50, not 60');
};

subtest 'an element read interleaved between two pops observes each version (WAR)' => sub {
    my ($kind, $out) = lower_and_run(
        'my @q=(10,20,30,40); my $a=pop @q; my $p=$q[2]; my $b=pop @q; my $r=$q[1]; $p+$r');
    is("$kind:$out", 'value:Int:50', 'interleaved pop reads pin per-version -> 50, not 20');
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

subtest 'a read of a DIFFERENT element after a guarded store is correct' => sub {
    # `if($c){$a[0]=9} $a[0]+$a[1]` -- the guarded store touches slot 0; the
    # post-merge reads of slot 0 (9) and slot 1 (unchanged 2) both re-load from
    # the array. c true -> 9 + 2 = 11.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); my $c=1; if($c){$a[0]=9} $a[0]+$a[1]');
    is("$kind:$out", 'value:Int:11', 'guarded slot-0 store + slot-1 read -> 11');
};

subtest 'a guarded hash store is visible after the branch (memory-Phi over %Hash)' => sub {
    my ($kind, $out) = lower_and_run('my %h=(a=>1); my $c=1; if($c){$h{a}=9} $h{a}');
    is("$kind:$out", 'value:Int:9', 'guarded hash store is visible -> 9');
};

subtest 'a mixed scalar-rebind + element-store arm GAPs, never miscompiles (2b-3 mixed)' => sub {
    # `if($c){$x=9; $a[0]=7} $x+$a[0]` -- ONE arm both rebinds a scalar (a
    # value-Phi) and stores an element (a memory-Phi) on the same Region. The
    # value-Phi's arm order is not yet reconciled with the element store; wiring
    # it read the wrong arm (12 instead of 16). Must GAP loudly, not miscompile.
    my ($kind, $out) = lower_and_run(
        'my @a=(1,2,3); my $c=1; my $x=5; if($c){$x=9;$a[0]=7} $x+$a[0]');
    is($kind, 'gap', 'the mixed scalar+element-store arm GAPs (not a wrong value)');
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

subtest 'a shift-drain loop consumes the array through a loop memory-Phi' => sub {
    # `while (my $x = shift @q) { $s += $x }` -- the DOMINANT worklist-drain idiom.
    # The shift mutates @q in the loop CONDITION; @q's memory threads through a
    # loop-header memory-Phi so each iteration shifts off the previous drain, and
    # the loop-invariant array literal is built ONCE in the preheader (not
    # re-initialized each iteration, which would loop forever). Drains to empty.
    my ($k1, $o1) = lower_and_run('my @q=(1,2,3); my $s=0; while (my $x = shift @q) { $s += $x } $s');
    is("$k1:$o1", 'value:Int:6', 'shift-drain accumulates 1+2+3 -> 6');

    # pop-drain (drains from the end): same total.
    my ($k2, $o2) = lower_and_run('my @q=(10,20,30); my $s=0; while (my $x = pop @q) { $s += $x } $s');
    is("$k2:$o2", 'value:Int:60', 'pop-drain accumulates 10+20+30 -> 60');

    # the drained value is UNUSED in the body (a pure count): the array is off the
    # return value path, so its repr is inferred structurally at the shift.
    my ($k3, $o3) = lower_and_run('my @q=(5,5,5,5); my $n=0; while (my $x = shift @q) { $n += 1 } $n');
    is("$k3:$o3", 'value:Int:4', 'shift-drain count (value unused) -> 4');
};

subtest 'a do-block in a loop body with a body-local var lowers correctly (zhi 019f59b1)' => sub {
    # `while ($i<3){ $s = $s + do { my $t=$i; $t+1 }; $i=$i+1 } $s` -- the do-block
    # is inlined (not a nested loop), but its body-local `my $t=$i` used to
    # mis-wire $s's loop-Phi backedge to Add($i_phi, $i_next) instead of
    # Add($s_phi, $t+1): a silent off-by-one (returned 5, not 6). Either lower
    # correctly to 6 or GAP loudly -- never a silent wrong value.
    my ($k, $o) = lower_and_run(
        'my $i=0; my $s=0; while ($i<3){ $s = $s + do { my $t=$i; $t+1 }; $i=$i+1 } $s');
    # Correct-or-GAP, never the silent 5. A lowered value MUST be Int:6.
    my $outcome = ($k eq 'value') ? "$k:$o" : 'gap';
    ok($outcome eq 'value:Int:6' || $outcome eq 'gap',
        "do-block accumulator lowers to 6 or GAPs, never a silent wrong value (got $k:$o)");
};

subtest 'unsound drain shapes GAP, never miscompile (soundness guards)' => sub {
    # Each of these was found (adversarial verification) to miscompile/crash/hang
    # before its guard. The in-place drain destroys the pre-loop array, so any of
    # these shapes must GAP loudly rather than mislower:
    #  - the drained array is ALSO read before the loop (`scalar @q`);
    #  - the body RE-FILLS the array (`push @q, ...`);
    #  - `defined(my $x = shift @q)` as the condition (Defined is not an icmp).
    for my $body (
        'my @q=(5,6,7); my $before=scalar @q; my $s=0; while (my $x=shift @q){$s+=$x} $before',
        'my @q=(3); my $s=0; while (my $x = shift @q) { $s += $x; push @q, $x - 1 } $s',
        'my @q=(1,2,0,3); my $s=0; while (defined(my $x = shift @q)) { $s += $x } $s',
    ) {
        my ($kind, $out) = lower_and_run($body);
        isnt($kind, 'value', "[$body] does NOT lower to a value (GAPs)")
            or diag("unexpectedly lowered to: $out");
    }

    # A drain over a constant RANGE `(1..4)` now lowers correctly (the folded
    # const AV is expanded to a 4-element ArrayRef, zhi 019f5942) -- it is no
    # longer an unsound shape. It drains 1+2+3+4 = 10.
    my ($rk, $ro) = lower_and_run(
        'my @q=(1..4); my $s=0; while (my $x = shift @q) { $s += $x } $s');
    is("$rk:$ro", 'value:Int:10', 'a drain over (1..4) lowers correctly (was a GAP) -> 10');
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

subtest 'an element read-modify-write stores back (019f342f)' => sub {
    # $a[i] += / ++ now emits the element store-back (zhi 019f342f-ad73): the
    # producer reads the pre-store value through a memory-pinned rvalue Subscript,
    # computes the new value, and stores it back. A following read observes the
    # updated element. (Was a dropped-store GAP before the fix; full RMW-as-value
    # coverage lives in t/bootstrap/element-rmw-memory-ssa.t.)
    my ($k1, $o1) = lower_and_run('my @a=(1,2,3); $a[0]+=4; $a[0]');
    is("$k1:$o1", 'value:Int:5', 'straight-line element += stores back -> 5');
    my ($k2, $o2) = lower_and_run('my @a=(1,2,3); my $c=1; if($c){$a[0]+=4} $a[0]');
    is("$k2:$o2", 'value:Int:5', 'branch-guarded element += stores back (2b memory-Phi) -> 5');
    my ($k3, $o3) = lower_and_run('my @a=(1,2,3); $a[0]+$a[1]');
    is("$k3:$o3", 'value:Int:3', 'legit arith over two element reads does NOT GAP');
    my ($k4, $o4) = lower_and_run('my @a=(5,6,7); $a[0]=$a[0]+1; $a[0]');
    is("$k4:$o4", 'value:Int:6', 'element read + explicit store-back does NOT GAP');
};

subtest 'a control-only-reachable loop-body store lowers (result unread)' => sub {
    # `my @a=(5,6,7); my $x=$a[0]; my $i=0; while($i<3){$a[0]=$i; $i=$i+1} $x`
    # -- the return is the PRE-loop read $x (5); the in-loop store $a[0]=$i is
    # threaded as a pure statement effect (its RESULT is never read, no post-loop
    # read observes its memory). The store Assign is thus reachable only via the
    # loop body's control edge, not the value graph, so the loader's repr pass
    # never stamped it and the backend GAPed with repr=undef (019f3559). Its repr
    # is derivable at the store site (rhs $i is Int); once stamped the store
    # lowers and the whole method returns the pre-loop 5.
    my ($kind, $out) = lower_and_run('my @a=(5,6,7); my $x=$a[0]; my $i=0; while($i<3){$a[0]=$i; $i=$i+1} $x');
    is("$kind:$out", 'value:Int:5', 'control-only loop-body store lowers, returns pre-loop 5');
};

subtest 'a straight-line store BEFORE a while loop is not false-GAPed (019f342f)' => sub {
    # `my @a=(1,2,3); $a[0]=5; my $r=$a[0]; my $i=0; while($i<2){$i=$i+1} $r`
    # -- the store $a[0]=5 and the read $r=$a[0] are straight-line; the while loop
    # touches only $i, not the array. _scan_memory_shape walked the return's
    # control_in chain to find on-chain stores, but a Region/Loop links its
    # predecessor through control-flow INPUTS (Region->Proj->Loop->store), not a
    # linear control_in, so the pre-loop store was misclassified off-chain and the
    # read GAPed. Following the control-flow head recognizes the on-chain store.
    my ($kind, $out) = lower_and_run('my @a=(1,2,3); $a[0]=5; my $r=$a[0]; my $i=0; while($i<2){$i=$i+1} $r');
    is("$kind:$out", 'value:Int:5', 'pre-loop store/read lowers (not a false GAP), returns 5');
};

done_testing();
