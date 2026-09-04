# ABOUTME: End-to-end runner for the mdtest-style typed-IR corpus (constructive format).
# ABOUTME: Parses arithmetic.md, builds graphs FROM the ir blocks, asserts behavior+TypedInvariant+L-verdict.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';
use File::Temp qw(tempfile);

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::Target::LLVM;

use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::LLVMDriver;
use Chalk::CodeGen::Harness::BehaviorRecord;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

my $ARITHMETIC_MD = 't/corpus/mdtest/arithmetic.md';

unless (-f $ARITHMETIC_MD) {
    plan skip_all => "arithmetic.md not found at $ARITHMETIC_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse arithmetic.md and run all 5 cases end-to-end
#
# The KEY PROOF: graphs are built FROM THE MARKDOWN ir blocks (no external
# graph_for builder).  Each GREEN case lowers via lli and matches perl.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($ARITHMETIC_MD);
ok(scalar(@$cases) >= 5, 'arithmetic.md has at least the 5 original cases');

my @case_titles = map { $_->{title} } @$cases;
ok((grep { /Integer addition/ } @case_titles),       'case: Integer addition present');
ok((grep { /Integer subtraction/ } @case_titles),    'case: Integer subtraction present');
ok((grep { /Integer multiplication/ } @case_titles), 'case: Integer multiplication present');
ok((grep { /Float division/ } @case_titles),         'case: Float division present');
ok((grep { /Integer modulo/ } @case_titles),         'case: Integer modulo right-sign present');

# Run every case (no graph_for — the graph is built from the ir block). A case
# whose ir block is a declared worklist entry (L: GREEN but a known B::SoN gap,
# same convention as son-corpus-wide.t's tally) is TODO-wrapped: red there is
# the worklist, not a regression, and must never silently mask a real FAIL.
my %KNOWN_WORKLIST = map { $_ => 1 } (
    'Float division of two variables',
    # A LIVE MISCOMPILE, not an absence: this case COMPILES and gets the wrong
    # answer (9.00719925474099e+15 against perl's 9007199254740993), because
    # %_REPR_LLVM_TYPE maps Num to double before any constraint is seen and the
    # sitofp cannot hold an i64 above 2^53.
    #
    # It is deliberately NOT declared `L: GAP`. The gate rejects that outright
    # -- "a corpus-declared GAP that LOWERS BUT DISAGREES with perl ... the
    # declaration was hiding a miscompile, not an absence" -- and it is right:
    # a GAP claims the case does not compile. It is not a DEVIATES case either,
    # since chalk COULD produce the exact answer; that verdict is for output a
    # static compiler cannot match.
    #
    # So it is TODO here and red on the gate, which is the honest shape for a
    # known defect with a named cause. See
    # docs/plans/2026-09-04-perl-decides-repr-by-value-not-type.md.
    'Int exceeding 2^53 entering a Num context loses precision',
);

for my $case (@$cases) {
    my $title = $case->{title};
    my $is_worklist = $KNOWN_WORKLIST{$title};

    subtest "case: $title" => sub {
        local $TODO = "B::SoN gap (worklist, not a regression)" if $is_worklist;

        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        # Behavior check
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape check (TypedInvariant on the built graph)
        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape fail: " . join('; ', @{ $result->{fail_reasons} }));

        # L-verdict check
        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        # Overall
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));

        # For GREEN cases: directly prove the graph built from the block goes
        # through lli and matches perl (the load-bearing proof).
        # AN ABSENT ir BLOCK IS NOT A GREEN ONE, and this used to conflate
        # them. `parse_l_verdict_from_ir` defaults to 'GREEN' when it finds no
        # L: line -- correct for a block that simply omits the declaration --
        # but `$case->{ir} // ''` fed it an EMPTY STRING for a case with no
        # block at all, which took the same default. The next line then handed
        # `undef` to `build_graph_from_ir` and the whole FILE died with
        # "ir_block must be defined", after the per-case subtests had already
        # reported. A dying file reads as zero failures in a grep for `not ok`.
        #
        # A case without an ir block has nothing to build FROM: the
        # constructive proof does not apply to it, which is different from
        # applying and failing.
        my $decl_verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir(
            $case->{ir} // '');
        if (defined $case->{ir} && $case->{ir} =~ /\S/ && $decl_verdict eq 'GREEN') {
            my $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir(
                $case->{ir});
            ok(defined $return_node, "$title: build_graph_from_ir returns a node");
            if (defined $return_node) {
                my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
                ok(!$meta->{marked_unsupported},
                    "$title: built-from-block graph is truly GREEN (not marked_unsupported)");
                my $lli_out  = $L->return_values->[0] // '';
                my $perl_out = $case->{_perl_actual} // '';
                if (length $perl_out) {
                    # Both sides are type-tagged (Int:N, Num:G, Bool:, etc.).
                    # Exact tag comparison — no numeric tolerance needed; the tag encodes the type.
                    is($lli_out, $perl_out,
                        "$title: lli output '$lli_out' == perl oracle '$perl_out' (built from block)");
                }
            }
        }
    };
}

# ---------------------------------------------------------------------------
# SECTION 2: Capture mode
#
# Create a scratch .md with an empty behavior block, run in capture mode,
# verify the behavior block gets filled in with the perl oracle value.
# The ir block is now constructive (no ir-tag comment).
# ---------------------------------------------------------------------------

subtest 'capture mode: empty behavior block gets filled from perl oracle' => sub {
    my $scratch_md = <<'END_MD';
# Scratch

## Capture test

```perl
# source
use 5.42.0;
say(1 + 2);
```

```behavior
```

```ir
%start = Start()
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
%co  = Coerce(%add : Int -> Str) :Str
%nl  = Constant("\n") :Str
%p   = Print(%co, %nl)
return %p
control: %start -> %p
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $scratch_md;
    close $fh;

    # Run in capture mode (no graph_for needed)
    my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    is(scalar(@$cases), 1, 'scratch md has 1 case');

    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {
        capture_mode => 1,
        md_path      => $tmpfile,
    });

    is($result->{behavior}{verdict}, 'CAPTURED', 'behavior verdict is CAPTURED');
    # A case is a PROGRAM: the oracle's result is what it PRINTED, so capture
    # records stdout. It used to record a type-tagged return VALUE (Int:3),
    # which described a fragment -- a program has no return value, and a block
    # captured that way was immediately rejected as unmigrated on the re-run.
    is($result->{behavior}{actual}, '3', 'captured value is the printed 3');
    is($result->{overall}, 'CAPTURED', 'overall verdict is CAPTURED');

    # Re-read the file: the behavior block should now be filled
    open my $rfh, '<:utf8', $tmpfile or die "cannot open $tmpfile: $!";
    my $new_content = do { local $/; <$rfh> };
    close $rfh;

    like($new_content, qr/stdout: 3/, 'rewritten file contains "stdout: 3"');
    unlike($new_content, qr/^```behavior\s*```/m, 'behavior block is no longer empty');

    # Run again on the rewritten file — now it should PASS (not CAPTURED)
    my $cases2  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case2   = $cases2->[0];
    my $result2 = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case2, {
        capture_mode => 1,
        md_path      => $tmpfile,
    });

    is($result2->{behavior}{verdict}, 'PASS',
        'after capture: re-running the frozen block gives PASS (not CAPTURED again)');
};

# ---------------------------------------------------------------------------
# SECTION 3: Negative guards — the corpus must not lie
# ---------------------------------------------------------------------------

# GUARD 1: hand-written behavior that disagrees with perl MUST fail
subtest 'guard: hand-written behavior mismatch FAILS' => sub {
    my $bad_md = <<'END_MD';
# Bad

## Bad behavior case

```perl
# source
1 + 2
```

```behavior
return: 99
context: scalar
```

```ir
%c1  = Constant(1) :Int
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $bad_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    is($result->{behavior}{verdict}, 'FAIL',
        'behavior with wrong return:99 is FAIL (perl says 3)');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(scalar(@{ $result->{fail_reasons} }) > 0, 'at least one fail reason recorded');
    like($result->{fail_reasons}[0], qr/mismatch|behavior/i,
        'fail reason mentions mismatch or behavior');
};

# GUARD 2: an ir block that builds an ill-typed graph MUST fail the TypedInvariant
subtest 'guard: ill-typed ir block (Num fed to Add without Coerce) FAILS TypedInvariant' => sub {
    # This ir block feeds a Num constant directly into Add — Add requires Int inputs.
    # The TypedInvariant must reject this.
    my $bad_ir_md = <<'END_MD';
# Bad IR

## Ill-typed ir block case

```perl
# source
1 + 2
```

```behavior
return: 3
context: scalar
```

```ir
%c1  = Constant(1) :Num
%c2  = Constant(2) :Int
%add = Add(%c1, %c2) :Int
return %add
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $bad_ir_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    is($result->{ir_shape}{verdict}, 'FAIL',
        'ir-shape FAILS when built graph violates TypedInvariant (Num input to Add)');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(defined $result->{ir_shape}{violations}
       && scalar(@{ $result->{ir_shape}{violations} }) > 0,
       'violations list is non-empty');
    like($result->{fail_reasons}[0] // '', qr/TypedInvariant|representation|Num|Int/i,
        'fail reason mentions TypedInvariant or representation mismatch');
};

# GUARD 3: claiming L: GREEN for a real GAP idiom MUST fail
subtest 'guard: L verdict GREEN for a real GAP FAILS' => sub {
    # A Constant with Scalar representation cannot lower runtime-free.
    # The ir block claims GREEN but the real L corner will say GAP.
    my $fake_green_md = <<'END_MD';
# Fake Green

## Fake GREEN verdict case

```perl
# source
1
```

```behavior
return: 1
context: scalar
```

```ir
%c1  = Constant(1) :Scalar
return %c1
L: GREEN
```
END_MD

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $fake_green_md;
    close $fh;

    my $cases  = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $case   = $cases->[0];
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

    is($result->{l_verdict}{verdict}, 'FAIL',
        'L verdict FAILS when actual is GAP but declared GREEN');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    like($result->{fail_reasons}[0] // '', qr/L verdict|GAP|GREEN/i,
        'fail reason mentions L verdict or GAP/GREEN');
};

done_testing;
