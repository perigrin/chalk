# ABOUTME: Phase 4 gate measurement: run EVERY mdtest corpus case through B::SoN.
# ABOUTME: Triple contract per case: behavior (lli == perl) + shape (ir-block subset) + TypedInvariant.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Graph::TypedInvariant;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;
use Chalk::CodeGen::Harness::MdtestCorpus;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;
plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;

# host.md H3 ($ENV{CHALK_G7_TEST}) declares its env dependency in the case
# prose: both the perl oracle and lli inherit this runner's environment (they
# are qx() child processes). Set it so H3 gate-greens here as it does in the
# dedicated host.t runner (which sets the same var).
local $ENV{CHALK_G7_TEST} = 'hostval';

# ---------------------------------------------------------------------------
# The B::SoN pipeline (class-aware), reused shape from son-e2e.t.
# ---------------------------------------------------------------------------
sub split_class_source ($clean) {
    my @lines = split /\n/, $clean;
    my (@head, @driver, @class_names);
    my ($depth, $in_class) = (0, 0);
    for my $line (@lines) {
        if (!$in_class && $line =~ /^\s*(?:use|no)\s+/) { push @head, $line; next; }
        if (!$in_class && $line =~ /^\s*class\s+(\w[\w:]*)/) {
            push @class_names, $1; $in_class = 1; $depth = 0;
        }
        if ($in_class) {
            push @head, $line;
            $depth += ($line =~ tr/{//);
            $depth -= ($line =~ tr/}//);
            $in_class = 0 if $depth <= 0;
            next;
        }
        push @driver, $line;
    }
    my $prog = join("\n", @head) . "\npackage main;\n"
             . "sub corpus_case {\n" . join("\n", @driver) . "\n}\n";
    return ($prog, \@class_names);
}

sub run_through_bson ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my ($prog, $class_names) = split_class_source($clean);
    my $pkg_opts = join(',', 'package=main', map { "package=$_" } @$class_names);

    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $prog;
    close $fh;

    my $json = qx($PERL -I$SON -MO=SoN,json,$pkg_opts $tmp 2>/dev/null);
    return (undef, "B::SoN produced no JSON")        unless $json =~ /\S/;
    my $data = eval { JSON::PP->new->decode($json) };
    return (undef, "JSON decode failed")             unless $data;
    return (undef, "no main::corpus_case method")
        unless $data->{methods}{'main::corpus_case'};

    my ($graphs, $mop) = eval { Chalk::IR::Serialize::JSON::from_json($json) };
    return (undef, "from_json failed: $@")           unless $graphs;
    my $g = $graphs->{'main::corpus_case'} or return (undef, "no loaded graph");
    my $ret = $g->returns->[0] or return (undef, "no Return node", $g);

    my $ll = eval { Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ())) };
    return (undef, "lower: $@", $g) if $@;

    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    if (my $sig = $? & 127) {
        return (undef, "lli died on signal $sig", $g);
    }
    my $exit = $? >> 8;
    return (undef, "lli exited $exit", $g) if $exit != 0;
    chomp $out;
    return ($out, undef, $g);
}

sub perl_oracle ($source) {
    (my $clean = $source) =~ s/^\s*#[^\n]*\n//gm;
    $clean =~ s/\s+$//;
    my $frag = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $prog = "use 5.42.0;\nuse utf8;\nmy \$_result = do {\n$clean\n};\n$frag";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog; close $fh;
    my $out = qx($PERL $tmp 2>&1);
    chomp $out;
    return $out;
}

# ---------------------------------------------------------------------------
# Iterate every case in every topic file.
# ---------------------------------------------------------------------------
my @topics = sort glob('t/corpus/mdtest/*.md');

my %tally = (green => 0, gap_declared => 0, bug => 0, no_source => 0,
             shape_ok => 0, inv_ok => 0, gate_green => 0);
my %by_topic;
my @bugs;

for my $md (@topics) {
    my $topic = $md =~ m{/([^/]+)\.md$} ? $1 : $md;
    my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($md);

    for my $case (@$cases) {
        my $title  = $case->{title} // '?';
        my $source = $case->{source};
        my $label  = "$topic: $title";

        unless (defined $source && $source =~ /\S/) {
            $tally{no_source}++;
            next;   # section with no perl block (prose)
        }

        my $verdict = Chalk::CodeGen::Harness::MdtestCorpus
            ->parse_l_verdict_from_ir($case->{ir} // '');

        # Corpus-declared GAP: not expected to lower; record honestly.
        if ($verdict eq 'GAP') {
            $tally{gap_declared}++;
            $by_topic{$topic}{gap}++;
            pass("$label: corpus-declared GAP (skipped)");
            next;
        }

        my $oracle = perl_oracle($source);
        my ($lli, $err, $g) = run_through_bson($source);

        # The triple contract (Phase 4 gate): behavior AND shape AND invariant.
        my $behavior_ok = defined $lli && $lli eq $oracle;

        my ($shape_ok, $shape_why) = (0, 'no loaded graph');
        my ($inv_ok,   $inv_why)   = (0, 'no loaded graph');
        if (defined $g) {
            # Each leg is exception-isolated: a die in one graph walk must
            # cost that case only, not abort the whole gap map.
            my $shape = eval {
                Chalk::CodeGen::Harness::MdtestCorpus
                    ->shape_subset_check($case->{ir}, $g->returns->[0]);
            } // { verdict => 'FAIL', missing => [], reason => "died: $@" };
            $shape_ok  = $shape->{verdict} eq 'PASS';
            $shape_why = $shape->{verdict} eq 'FAIL' && $shape->{missing}->@*
                ? 'missing [' . join(', ', $shape->{missing}->@*) . ']'
                : ($shape->{reason} // '');

            my $inv = eval { Chalk::IR::Graph::TypedInvariant->check($g->nodes) }
                // { ok => 0, violations => [{ message => "died: $@" }] };
            $inv_ok  = $inv->{ok} ? 1 : 0;
            $inv_why = $inv->{ok} ? ''
                : join('; ', map { $_->{message} } $inv->{violations}->@*);
        }

        $tally{green}++,      $by_topic{$topic}{green}++      if $behavior_ok;
        $tally{shape_ok}++,   $by_topic{$topic}{shape}++      if $shape_ok;
        $tally{inv_ok}++,     $by_topic{$topic}{inv}++        if $inv_ok;

        if ($behavior_ok && $shape_ok && $inv_ok) {
            $tally{gate_green}++;
            $by_topic{$topic}{gate}++;
            pass("$label: gate-green (behavior + shape + invariant)");
        }
        else {
            my @why;
            push @why, (defined $lli ? "lli '$lli' != perl '$oracle'" : $err)
                unless $behavior_ok;
            push @why, "shape: $shape_why"     unless $shape_ok;
            push @why, "invariant: $inv_why"   unless $inv_ok;
            my $why = join(' | ', @why);
            $tally{bug}++;
            $by_topic{$topic}{bug}++;
            push @bugs, "$label -> $why";
            # Not a test failure: this is the gap map. Mark TODO so red = worklist.
            TODO: {
                local $TODO = "B::SoN gap (worklist, not a regression)";
                fail("$label: $why");
            }
        }
    }
}

# ---------------------------------------------------------------------------
# The map.
# ---------------------------------------------------------------------------
diag("");
diag("=== Phase 4 corpus-wide status (triple contract: behavior+shape+invariant) ===");
for my $t (sort keys %by_topic) {
    my $b = $by_topic{$t};
    diag(sprintf("  %-14s gate=%-2d behavior=%-2d shape=%-2d inv=%-2d gap=%-2d worklist=%-2d",
        $t, $b->{gate} // 0, $b->{green} // 0, $b->{shape} // 0,
        $b->{inv} // 0, $b->{gap} // 0, $b->{bug} // 0));
}
diag("");
diag(sprintf(
    "TOTAL: gate-green=%d  behavior=%d  shape=%d  invariant=%d  gap-declared=%d  worklist=%d  (no-source sections=%d)",
    @tally{qw(gate_green green shape_ok inv_ok gap_declared bug no_source)}));
if (@bugs) {
    diag("");
    diag("=== worklist (triple-contract gaps to close) ===");
    diag("  $_") for @bugs;
}

# The gate floor: the worklist is TODO (red = worklist, not regression), but
# already-certified gate-green cases must never silently regress. Raise the
# floor as the shape-contract families (019f2a50 pair) land.
cmp_ok($tally{gate_green}, q{>=}, 138, q{gate-green floor (138; FIRST WHOLE-FILE t/base PASS: t/base/if.t lowers end-to-end (lli==perl, via Mode1Runner). Root fix: a scalar-context print in an if/else arm (a last-statement if/else, WANT=0, whose Bool return is the block value) was NOT recognized as a statement effect -- so the value-context path left BOTH arm prints unguarded on shared control and BOTH fired (a silent miscompile: the sub printed both arms). _arm_has_void_call now treats a print as a control-flow-requiring effect in ANY context (not just OPf_WANT_VOID), so each print is control-pinned to its own arm Proj and only the taken arm fires. Corpus D1c/D1d pin the StrEq/StrNe-guard if.t idiom (bilateral: eq-guard true-arm, ne-guard else-arm). LATENT follow-up (does NOT affect if.t, which strips the epilogue): a WANT=0 last-statement if/else with print arms returns the pre-if value, not the taken print's Bool -- a return-value divergence, filed. Producer perl5-son pu. floor 136->138. Str package globals: A19 our $g=qq{hi} + A20 Str-global reassign. A Str package scalar is TWO mutable module slots (@pkg_<s>_<v>_ptr i8*, _len i64); the producer stamps the StashAccess with the RHS repr (Str vs Int), store/read hash-cons to one node so the read inherits it; backend store/load both slots + re-registers the loaded ptr len. Producer perl5-son pu (stash-store RHS-repr stamp). floor 134->136. round-2 t/base blockers flipped GREEN: T6 mid-body last (extra exit-Region predecessor), T7 next (reframed as if(!C){rest}), T9 stmt-modifier-in-arm, F5/F6 direct-call-with-args (SSA arg-binding during inline; the t/op is/ok unlocker), A16/A17/A18 package-var read+store (fixed a latent dropped-store miscompile; module i64 global). T8 (value-ctx ternary into element store) remains a declared GAP. Also fixed a loader topo bug (a merge-Phi Region emitted after its Phi lost its region). Producer: perl5-son pu. floor 126->134. the 6 t/base blocker GAPs are now GREEN: T1 list-context ternary (print $c ? "y" : "n" via a TernaryExpr over Str branches -- select ptr + len), T2 die-in-branch-arm (die lowers to an Unwind -> exit+unreachable; taken-die aborts exit 255, not-taken returns the other arm), T3 cond_expr-in-loop-body (dispatch to _handle_cond_expr from the loop-body walk), T4 last-in-loop-body (head-of-body last if hoisted as a negated loop header), L6 StrEq / L7 StrNe (length-guard + memcmp byte compare). Producer: perl5-son pu. floor 116->126. t/ blocker corpus: 6 GAP-declared cases pin the measured t/base blockers (T1 list-context ternary, T2 die-in-branch-arm, T3 cond_expr-in-loop-body, T4 last-in-loop-body, L6 StrEq, L7 StrNe) as regression-locked boundary markers that flip GAP->GREEN as each feature lands, plus 2 GREEN near-misses whose SIMPLE form already lowers (T5 direct no-arg named-sub call -> Int:42; L8 void call in an `and` arm -> stdout y + Int:1) -- the t/ files hit harder variants (Test::More `is` with no callee graph; an `and` arm mixing a void call with a scalar rebind) that still GAP. floor 114 -> 116. Prior: side-effecting loop condition lands: a `while` CONDITION that mutates a pad slot (`while ($i-- > 0)`) runs its mutation on the failing (N+1th) evaluation too, so the post-loop read must observe the AT-EXIT value, not the header Phi. The producer's two-phase loop translation now scouts the CONDITION segment for pad rebinds and, post-loop, binds each condition-mutated slot to its Phi back-edge (the value after the failing pass) instead of the header Phi; the LLVM backend pre-lowers such a back-edge in the loop header (identified by its post-loop consumer beyond its own Phi) so it dominates the exit. A condition that also STORES to memory still GAPs loudly. Two GREEN cases: D2d `my $i=3; while ($i-- > 0) {} $i` -> Int:-1 (the failing `$i-- > 0` decrements $i to -1); D2e `my $n=3; my $t=0; $t=$t+$n while $n-- > 0; $t` -> Int:3 (postfix, no pre-eval leak into the Phi init). Producer: perl5-son pu. floor 112 -> 114 (zhi 019f29ed). Prior: void print inside an if/else block body lands: `if ($c) { print "a\n" } else { print "b\n" }` in VOID context runs the taken arm for its print SIDE EFFECT. _handle_cond_expr only built real control flow (If + Proj + Region) when an arm STORED to an element or a class field; a void-print / void-call arm rebinds no pad slot, so it fell through to the pad-rebind merge path -- which merges nothing and left BOTH Print nodes unpinned so NEITHER fired (a silent effect drop). FIX: the $mem_branch gate now also fires when either arm has a void call/print (the same _arm_has_void_call predicate the &&/|| single-arm case uses, I7), routing the if/else through the shared control-flow block so each arm walks on its own Proj -- _handle_print control-pins its Print to that Proj and merge() Regions the arms. An `if` statement is always void (WANT 0/1), so this touches only the void path. Three GREEN cases: D1a `my $c=1; if ($c){print "a\n"}else{print "b\n"} 1` (true arm fires) -> stdout a\n + Int:1; D1b `my $c=0; ...` (else arm fires) -> stdout b\n + Int:1 (each Print pinned to its own arm's Proj -- bilateral proof the merge is genuine control flow, not a both-arms walk); D3f `for my $i (1..2){print "x\n"} 1` (loop-body void print, already green -- an acceptance guard that the loop-body effect path stays green alongside the if/else fix) -> stdout x\nx\n + Int:1. Producer: perl5-son pu cc0f4d0. floor 109 -> 112 (zhi I8). Prior: void print in a logical short-circuit arm lands: `EXPR && (print ...)` / `EXPR || (print ...)` in VOID context evaluates its RHS arm for the print's SIDE EFFECT, not its value. The producer previously modelled the arm as a discarded value and DROPPED the print (the arm collapsed to a value-returning And/Or). FIX: _arm_has_void_call now recognizes a void `print` (OPf_WANT_VOID) as a statement-effect arm exactly like a void entersub, so the and/or branch builds real control flow -- an If + Proj -- and merge() Regions the control-pinned Print onto the taken arm. Three bilateral GREEN cases: L5 `my $x=1; $x==$x && (print "y\n"); 1` (true guard, arm fires) -> stdout y\n + Int:1; L5b `$x!=$x && (print "y\n"); 1` (false guard, && short-circuits, arm SKIPPED) -> just Int:1; L5c `$x!=$x || (print "y\n"); 1` (|| fires the arm when the left is false, body on the FALSE Proj matching the unless polarity) -> stdout y\n + Int:1. The Print is control-dependent on the guard's Proj so it emits only when the arm is taken. floor 106 -> 109 (zhi I7). Prior: Stringify[Int]->Str coercion lands: in Chalk "ok $n" is COERCION not interpolation -- the producer wraps a non-Str operand of an interpolation Concat in a Stringify (Int->Str), and the LLVM backend renders it via an int-to-decimal loop (no libc) that records the RUNTIME digit-count length in _str_len_table so the Concat/print/return-epilogue slices exactly len bytes. Four GREEN cases: S9 `my $n=3; "ok $n"` -> Str:ok 3; S10 `my $n=-5; "val $n"` -> Str:val -5 (the sign is in the length -- do-while renders the magnitude then prepends '-'); S11 `my $n=0; "val $n"` -> Str:val 0 (do-while emits one '0'; a divide-until-zero loop would emit none); S12 `my $n=3; print "ok $n\\n"; 1` -> stdout ok 3\\n + Int:1 (I2's Print over the coerced Concat). A lone `"$n"` degenerates to the number itself in perl (oracle tags it Int), so the Str cases carry surrounding literal text to force a genuine Str face. floor 102 -> 106 (zhi I6). Prior: the Print statement effect + _lower_print land: print emits its list args to stdout runtime-free -- a Str arg via printf("%.*s", len, ptr) from the tracked _str_len_table, an Int arg via printf("%d") on the truncated i64, both BEFORE the return-value epilogue (the Print printf lands in @main's control-chain instructions, which precede the epilogue). Four GREEN print cases: bare `print "hi\n"; 1` -> hi\nInt:1; a mixed list `print "ok ", 1, "\n"; 1` -> ok 1\nInt:1; two ordered prints `print "a\n"; print "b\n"; 1` -> a\nb\nInt:1 (each is a distinct statement effect with per-call identity in %STATEMENT_EFFECT_OPS, threaded on the control chain in program order); and print-as-value `my $ok = print "x\n"; $ok` -> x\nBool:1 (print returns a genuine builtin::is_bool boolean, so the Print node's repr is Bool, not Int -- the loader seeds it). The explicit-filehandle form `print STDOUT ... / print $fh ...` sets OPf_STACKED and is a LOUD producer GAP (the runtime-free backend writes only to stdout; honoring a handle would misroute), corpus-declared GAP not a silent miscompile. floor 98 -> 102 (zhi I2). Prior: regex R7 negated match !~ pins the already-lowering Not(RegexMatch) path -- Perl compiles !~ to match wrapped in a not op (no distinct notmatch op), so the producer emits Not(RegexMatch(...)) and the negation rides on the existing RegexMatch matcher + the runtime-free Not arm (an i1 xor); no dedicated NotMatch lowering exists or is needed (the NotMatch node type is never produced). Bilateral against R1: R7 uses a pattern that DOES match so the negation flips a real match to false (zhi 019eb073 NotMatch line item). Prior: classes foreach over an arrayref field (for my $x ($items->@*){$s+=$x} -> 60) -- the #1 Phase-5 lib/ blocker (28 methods) lowers end-to-end: the loop-carried accumulator's back-edge (Add($s_phi, deferred-element-Subscript)) no longer GAPs at the loop-Phi stamp check -- a numeric-accumulator recurrence keeps its init stamp (the fixpoint no-op) and the loader types the element (zhi 019f6198). Plus the arrayref-field element read (field $items=[10,20,30]; $items->[0] -> 10) -- the producer emits an aggregate field default as an ArrayRef graph, the loader lifts the field type + element type, the backend reads the boxed i8* payload (zhi 019f61ad). Plus D3e element-indexed loop accumulator (for my $i (0..$#a){$s+=$a[$i]}) -- the #2 real-lib loop pattern; a DYNAMIC-index rvalue element read is stamped with the container element type (so the loop-carried back-edge is stamped), while a LITERAL index stays unstamped to preserve the OOB->Slot analysis (ref R9). Plus the foreach family: D3a foreach over a range with a RUNTIME high bound (for my $i (0..$n)/(0..$#a)) -- NumGt(Add(high,1), i_phi), the #1 Phase-5 lib/ blocker (28 methods); D3a2 $#a array last-index is Length-1 not Length (a pre-existing silent off-by-one av2arylen bug, exposed once 0..$#a could lower); D3b/D3c foreach over a lexical array (iterator = Subscript(arr,i), post-loop length intact via the store-back RMW heuristic); D3d iterator-write aliasing GAP; runtime LOW bound (for $lo..$hi) GAPs cleanly. for/foreach are aliases. zhi 019f5da9, gap-declared 13)});

done_testing();
