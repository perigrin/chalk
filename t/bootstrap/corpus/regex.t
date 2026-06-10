# ABOUTME: Runner for the regex mdtest corpus topic (constructive format).
# ABOUTME: R1 (literal match) lowers GREEN via the G6 regex sub-compiler; R2 (qr//) + R3 (s///) remain GAP until their tranches.
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

my $REGEX_MD = 't/corpus/mdtest/regex.md';

unless (-f $REGEX_MD) {
    plan skip_all => "regex.md not found at $REGEX_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse regex.md and verify case inventory
#
# All 3 regex idioms (R1-R3) must be present.  Every case is a pure-GAP
# (Str/Scalar + regex engine; no runtime-free regex lowering in the current
# Int/Num slice).  The corpus MUST record these GAPs honestly — a GREEN claim
# for any of them would be a lie and must fail.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($REGEX_MD);
is(scalar(@$cases), 5, 'regex.md has 5 cases (R1-R5)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /R1.*regex.*match/i      } @titles), 'case: R1 regex match present');
ok((grep { /R2.*qr/i                } @titles), 'case: R2 qr// compiled regex present');
ok((grep { /R3.*substitution/i      } @titles), 'case: R3 regex substitution present');
ok((grep { /R4.*anchored/i          } @titles), 'case: R4 anchored match present');
ok((grep { /R5.*class/i             } @titles), 'case: R5 character class present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 3 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (pure-GAP blocks trivially pass)
#   - L-verdict check must PASS (all declare L: GAP, actual is also GAP)
#
# All regex cases are pure-GAP: the ir block contains only an L: GAP(...)
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
# SECTION 3: Verify per-case L verdicts
#
# R1 (literal `=~`) is lowered runtime-free by the G6 regex sub-compiler — a
# literal pattern compiles to a slide-loop matcher producing the i1 matched?
# result, fed through a ternary to Int. It declares L: GREEN with a constructive
# graph. R2 (qr//) and R3 (s///) remain GAP until their tranches (qr// matcher
# value; s/// match + Str splice) are modelled.
# ---------------------------------------------------------------------------

my %EXPECTED_VERDICT = (
    'R1' => 'GREEN',   # literal match — G6 T0
    'R2' => 'GAP',     # qr// — pending
    'R3' => 'GAP',     # s/// — pending
    'R4' => 'GREEN',   # anchored match (^) — G6 T1
    'R5' => 'GREEN',   # character class — G6 T2
);

subtest 'per-case L verdicts (R1/R4/R5 GREEN via G6; R2/R3 still GAP)' => sub {
    plan tests => 5;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        my ($key)   = $title =~ /\b(R\d+)\b/;
        my $want    = $EXPECTED_VERDICT{$key // ''} // 'GAP';
        is($decl, $want, "case '$title': declared L: $want");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Negative guard — a regex case claiming GREEN must FAIL
#
# Regex idioms are not runtime-free lowerable.  If someone edits a regex case
# to claim L: GREEN without an actual lowerable graph, the runner must catch
# the lie.  A pure-GAP block (no node lines) combined with a GREEN claim is
# the inconsistency the runner detects.
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for regex match FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN regex match case

```perl
# source
my $s = "foobar"; $s =~ /foo/ ? 1 : 0
```

```behavior
return: 1
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
