# ABOUTME: Runner for the references mdtest corpus topic (all-GAP format).
# ABOUTME: Exercises R1-R8 array/hash/ref/deref idioms; all are L: GAP (Scalar/SV* layout required).
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;

my $REFERENCES_MD = 't/corpus/mdtest/references.md';

unless (-f $REFERENCES_MD) {
    plan skip_all => "references.md not found at $REFERENCES_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse references.md and verify case inventory
#
# All 8 reference/deref idioms (R1-R8) must be present.  Every case is an
# L: GAP because arrays and hashes require Scalar/SV* representation — none
# are runtime-free lowerable in the current Int/Num/Str arithmetic slice.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($REFERENCES_MD);
is(scalar(@$cases), 8, 'references.md has 8 cases (R1-R8)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /R1.*array.*literal/i }       @titles), 'case: R1 array literal present');
ok((grep { /R2.*array.*element.*read/i } @titles), 'case: R2 array element read present');
ok((grep { /R3.*hash.*literal/i }        @titles), 'case: R3 hash literal present');
ok((grep { /R4.*anonymous.*array/i }     @titles), 'case: R4 anonymous array ref present');
ok((grep { /R5.*anonymous.*hash/i }      @titles), 'case: R5 anonymous hash ref present');
ok((grep { /R6.*array.*element.*assign/i } @titles), 'case: R6 array element assignment present');
ok((grep { /R7.*hash.*element.*assign/i }  @titles), 'case: R7 hash element assignment present');
ok((grep { /R8.*nested/i }               @titles), 'case: R8 nested array ref present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all 8 cases end-to-end
#
# For each case:
#   - behavior check must PASS (perl oracle vs declared return value)
#   - ir-shape check must not FAIL (all are pure-GAP blocks; trivially pass)
#   - L-verdict check must PASS (all declare L: GAP; pure-GAP block is consistent)
#
# No lli / LLVMDriver needed — every case is a pure-GAP block.
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

        # L-verdict check: pure-GAP block with declared GAP must be consistent
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
# Every reference/deref idiom in this topic is an honest GAP: arrays and
# hashes need Scalar/SV* representation, which is not in the current
# runtime-free lowering slice.  A GREEN claim for any of them would be a lie.
# ---------------------------------------------------------------------------

subtest 'all R1-R8 cases declare L: GAP' => sub {
    plan tests => 8;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        is($decl, 'GAP', "case '$title': declared L: GAP (Scalar/SV* layout required)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Verify all ir blocks are pure-GAP (no node lines)
#
# A pure-GAP block has an L: GAP(...) line and NO %name = ... node lines.
# Every references case must be a pure-GAP block — the IR for array/hash
# idioms cannot be built constructively yet (no ArrayIndex, HashIndex,
# NewArray, NewHash nodes in the current IR).  This section confirms that
# none of the cases accidentally grew a node line.
# ---------------------------------------------------------------------------

subtest 'all R1-R8 ir blocks are pure-GAP (no constructive node lines)' => sub {
    plan tests => 8;
    for my $case (@$cases) {
        my $ir_text = $case->{ir} // '';
        my $has_nodes = ($ir_text =~ /^\s*%\w+\s*=/m) ? 1 : 0;
        my $title     = $case->{title};
        ok(!$has_nodes,
            "case '$title': ir block has no node lines (pure-GAP, not constructive)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Negative guard — a reference case claiming GREEN must FAIL
#
# If someone edits a reference case to claim L: GREEN without a constructive
# graph, the runner must catch the lie.  A pure-GAP block combined with a
# GREEN claim is the inconsistency the runner detects.
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for a reference case FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN array case

```perl
# source
my @a = (1, 2, 3); scalar @a
```

```behavior
return: 3
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
