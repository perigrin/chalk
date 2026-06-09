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
is(scalar(@$cases), 5, 'arithmetic.md has 5 cases');

my @case_titles = map { $_->{title} } @$cases;
ok((grep { /Integer addition/ } @case_titles),       'case: Integer addition present');
ok((grep { /Integer subtraction/ } @case_titles),    'case: Integer subtraction present');
ok((grep { /Integer multiplication/ } @case_titles), 'case: Integer multiplication present');
ok((grep { /Float division/ } @case_titles),         'case: Float division present');
ok((grep { /Integer modulo/ } @case_titles),         'case: Integer modulo right-sign present');

# Run all 5 cases (no graph_for — the graph is built from the ir block)
for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
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
        my $decl_verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir(
            $case->{ir} // '');
        if ($decl_verdict eq 'GREEN') {
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
1 + 2
```

```behavior
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
    # The oracle now emits a type-tagged value: Int:3 for the integer 1+2.
    is($result->{behavior}{actual}, 'Int:3', 'captured value is Int:3 from perl oracle (type-tagged)');
    is($result->{overall}, 'CAPTURED', 'overall verdict is CAPTURED');

    # Re-read the file: the behavior block should now be filled
    open my $rfh, '<:utf8', $tmpfile or die "cannot open $tmpfile: $!";
    my $new_content = do { local $/; <$rfh> };
    close $rfh;

    like($new_content, qr/return: Int:3/, 'rewritten file contains "return: Int:3" (type-tagged)');
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
