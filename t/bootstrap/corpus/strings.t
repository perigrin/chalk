# ABOUTME: Runner for the strings mdtest corpus topic (constructive format).
# ABOUTME: Exercises S1-S4 string idioms: all are Scalar/SV* GAPs (no runtime-free string lowering yet).
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;
use Chalk::CodeGen::Harness::LLVMDriver;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

my $STRINGS_MD = 't/corpus/mdtest/strings.md';

unless (-f $STRINGS_MD) {
    plan skip_all => "strings.md not found at $STRINGS_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse strings.md and verify case inventory
#
# All 4 string idioms (S1-S4) must be present.  Every case is a pure-GAP
# (Str/Scalar representation; no runtime-free string lowering in the current
# Int/Num slice).  The corpus MUST record these GAPs honestly — a GREEN claim
# for any of them would be a lie and must fail.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($STRINGS_MD);
is(scalar(@$cases), 4, 'strings.md has 4 cases (S1-S4)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /S1.*single/i      } @titles), 'case: S1 single-quoted literal present');
ok((grep { /S2.*double/i      } @titles), 'case: S2 double-quoted literal present');
ok((grep { /S3.*concat.*dot/i } @titles), 'case: S3 dot concat present');
ok((grep { /S4.*concat.*assign/i } @titles), 'case: S4 concat-assign present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 4 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (all declare L: GAP, actual is also GAP)
#
# All string cases are pure-GAP: the ir block contains only an L: GAP(...)
# line with no node bindings.  The runner records the GAP without attempting
# to build or lower a graph.
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        # Behavior check: perl oracle must agree with declared return
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape check: pure-GAP blocks trivially pass (no graph to validate)
        isnt($result->{ir_shape}{verdict}, 'FAIL',
            "$title: ir-shape not FAIL")
            or diag("  ir-shape fail: " . join('; ', @{ $result->{fail_reasons} }));

        # L-verdict check: declared GAP must match actual GAP
        is($result->{l_verdict}{verdict}, 'PASS',
            "$title: L verdict matches")
            or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));

        # Overall
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));
    };
}

# ---------------------------------------------------------------------------
# SECTION 3: Verify all cases declare L: GAP
#
# Every string idiom in this topic is a GAP — strings require Scalar/SV*
# representation not yet in the runtime-free lowering slice.
# ---------------------------------------------------------------------------

subtest 'S1-S4 all declare L: GAP (Str/Scalar not runtime-free lowerable)' => sub {
    plan tests => 4;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        is($decl, 'GAP', "case '$title': declared L: GAP");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Negative guard — a string case claiming GREEN must FAIL
#
# String idioms are not runtime-free lowerable.  If someone edits a string
# case to claim L: GREEN without an actual lowerable graph, the runner must
# catch the lie.  A pure-GAP block (no node lines) combined with a GREEN
# claim is the inconsistency the runner detects.
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for string literal FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN string literal case

```perl
# source
my $s = 'hello'; $s
```

```behavior
return: hello
context: scalar
```

```ir
L: GREEN
```
END_MD

    use File::Temp qw(tempfile);
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.md', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $fake_green_md;
    close $fh;

    my $fake_cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($tmpfile);
    my $fake_case  = $fake_cases->[0];
    my $result     = Chalk::CodeGen::Harness::MdtestCorpus->run_case($fake_case, {});

    is($result->{l_verdict}{verdict}, 'FAIL',
        'pure-GAP block (no nodes) claiming L: GREEN is FAIL');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
    ok(scalar(@{ $result->{fail_reasons} }) > 0, 'at least one fail reason recorded');
    like($result->{fail_reasons}[0] // '', qr/L verdict|GAP|GREEN/i,
        'fail reason mentions L verdict, GAP, or GREEN');
};

done_testing;
