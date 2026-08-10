# ABOUTME: Runner for the regex mdtest corpus topic (constructive format).
# ABOUTME: R1/R3-R6 lower GREEN via the G6 regex sub-compiler; R2 (qr//) remains GAP until its tranche.
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
# SECTION 1: Parse regex.md and verify the topic's named idioms are present.
#
# All regex idioms (R1-R6) must be present. R1-R6 carry constructive graphs
# lowered by the G6 regex sub-compiler (literal/anchor/class/quantifier/
# capture matching, qr// application, s/// splice); a GREEN claim must be
# backed by an actual lowerable graph (the SECTION 4 guard enforces this).
#
# This runner asserts the STATIC inventory + shape of the corpus file. The
# authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition (zhi 019f53a0). Retired here in favor of the single
# authoritative gate; the presence/L-verdict/guard checks below lower nothing
# and stay.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($REGEX_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /R1.*regex.*match/i      } @titles), 'case: R1 regex match present');
ok((grep { /R2.*qr/i                } @titles), 'case: R2 qr// compiled regex present');
ok((grep { /R3.*substitution/i      } @titles), 'case: R3 regex substitution present');
ok((grep { /R4.*anchored/i          } @titles), 'case: R4 anchored match present');
ok((grep { /R5.*class/i             } @titles), 'case: R5 character class present');
ok((grep { /R6.*quantified/i        } @titles), 'case: R6 quantified identifier present');

# ---------------------------------------------------------------------------
# SECTION 2: Verify per-case L verdicts
#
# R1 (literal `=~`) is lowered runtime-free by the G6 regex sub-compiler — a
# literal pattern compiles to a slide-loop matcher producing the i1 matched?
# result, fed through a ternary to Int. It declares L: GREEN with a constructive
# graph. R2 (qr//) and R3 (s///) remain GAP until their tranches (qr// matcher
# value; s/// match + Str splice) are modelled.
# ---------------------------------------------------------------------------

my %EXPECTED_VERDICT = (
    'R1' => 'GREEN',   # literal match — G6 T0
    'R2' => 'GREEN',   # qr// — Constant(regex) + Match, statically inlined
    'R3' => 'GREEN',   # s/// — G6 T4 (match + splice)
    'R4' => 'GREEN',   # anchored match (^) — G6 T1
    'R5' => 'GREEN',   # character class — G6 T2
    'R6' => 'GREEN',   # quantified identifier — G6 T3
    'R7' => 'GREEN',   # negated match (!~) — Not over the existing matcher
    'R8'  => 'GREEN',  # unbound match reads $_
    'R8b' => 'GREEN',  # ... and its bilateral non-matching partner
    'R9'  => 'GREEN',  # match bound to a package scalar (OPf_STACKED subject)
);
subtest 'per-case L verdicts (all GREEN via G6)' => sub {
    plan tests => scalar @$cases;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        # A lettered variant (R8b) is its own key, not a synonym for its parent:
        # `\b(R\d+)\b` cannot match "R8b" at all (no boundary between 8 and b),
        # so an unlisted variant would silently fall through to the GAP default.
        my ($key)   = $title =~ /\b(R\d+[a-z]?)\b/;
        my $want    = $EXPECTED_VERDICT{$key // ''} // 'GAP';
        is($decl, $want, "case '$title': declared L: $want");
    }
};

# ---------------------------------------------------------------------------
# SECTION 3: Negative guard — a GREEN claim without a graph must FAIL
#
# If someone edits a regex case to claim L: GREEN without an actual lowerable
# graph, the runner must catch the lie.  A pure-GAP block (no node lines)
# combined with a GREEN claim is the inconsistency the runner detects.
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
