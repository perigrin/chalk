# ABOUTME: Runner for the references mdtest corpus (R1-R8 GREEN, R9-R11 adversarial/boundary).
# ABOUTME: Exercises array/hash/ref/deref idioms; R1-R10 are L: GREEN (G4 campaign group closed).
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

my $REFERENCES_MD = 't/corpus/mdtest/references.md';

unless (-f $REFERENCES_MD) {
    plan skip_all => "references.md not found at $REFERENCES_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse references.md and verify case inventory
#
# R1-R8:  Array/hash/ref/deref idioms — L: GREEN (G4 campaign group closed).
# R9:     Out-of-bounds array read    — L: GREEN (OOB -> Undef:, never segfault).
# R10:    Missing-key hash lookup     — L: GREEN (miss -> Undef:).
# R11:    Hash keys sorted order      — L: GAP   (sort/join/keys deferred).
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($REFERENCES_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /R1.*array.*literal/i }        @titles), 'case: R1 array literal present');
ok((grep { /R2.*array.*element.*read/i }  @titles), 'case: R2 array element read present');
ok((grep { /R3.*hash.*literal/i }         @titles), 'case: R3 hash literal present');
ok((grep { /R4.*anonymous.*array/i }      @titles), 'case: R4 anonymous array ref present');
ok((grep { /R5.*anonymous.*hash/i }       @titles), 'case: R5 anonymous hash ref present');
ok((grep { /R6.*array.*element.*assign/i} @titles), 'case: R6 array element assignment present');
ok((grep { /R7.*hash.*element.*assign/i } @titles), 'case: R7 hash element assignment present');
ok((grep { /R8.*nested/i }                @titles), 'case: R8 nested array ref present');
ok((grep { /R9.*out.*of.*bounds/i }       @titles), 'case: R9 OOB array read present');
ok((grep { /R10.*missing.*key/i }         @titles), 'case: R10 missing-key hash present');
ok((grep { /R11.*hash.*keys.*sorted/i }   @titles), 'case: R11 hash keys sorted present');

# ---------------------------------------------------------------------------
# SECTION 2: Static verdict + node-line checks (no lowering here).
#
# The authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks + .ll probes
# here lowered the hand-written IR BLOCK through the constructive builder -- a
# second, drifting lowering path that reported miscompiles on cases
# son-corpus-wide.t gates GREEN (zhi 019f53a0). Retired in favor of the single
# authoritative gate; the static presence/verdict/node-line checks below lower
# nothing and stay.
#
# R11 (keys-sorted) and R12 (aliased element store) are declared GAPs, not GREEN.
# ---------------------------------------------------------------------------

my @green_cases = grep { $_->{title} !~ /R11|R12/i } @$cases;

# ---------------------------------------------------------------------------
# SECTION 3: R11 hash keys sorted order — declares L: GAP (static parse).
#
# R11 declares GAP because sort+join+keys require list-context operations
# not yet in the LLVM lowering slice.
# ---------------------------------------------------------------------------

my ($r11_case) = grep { $_->{title} =~ /R11/i } @$cases;

subtest 'R11 hash keys sorted order: declares L: GAP (list-ops deferred)' => sub {
    ok(defined $r11_case, 'R11 case found');

    if (defined $r11_case) {
        my $decl = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($r11_case->{ir} // '');
        is($decl, 'GAP', 'R11 declares L: GAP (honest boundary)');
    }

    done_testing;
};

# ---------------------------------------------------------------------------
# SECTION 4: Verify R1-R10 all declare L: GREEN
# ---------------------------------------------------------------------------

subtest 'all R1-R10 cases declare L: GREEN' => sub {
    plan tests => scalar(@green_cases);
    for my $case (@green_cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        is($decl, 'GREEN', "case '$title': declared L: GREEN");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Verify R1-R10 ir blocks have constructive node lines
# ---------------------------------------------------------------------------

subtest 'all R1-R10 ir blocks have constructive node lines' => sub {
    plan tests => scalar(@green_cases);
    for my $case (@green_cases) {
        my $ir_text   = $case->{ir} // '';
        my $has_nodes = ($ir_text =~ /^\s*%\w+\s*=/m) ? 1 : 0;
        my $title     = $case->{title};
        ok($has_nodes, "case '$title': ir block has node lines (constructive)");
    }
};

# ---------------------------------------------------------------------------
# SECTION 7: Negative guard — pure-GAP block claiming GREEN FAILS
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN FAILS L verdict' => sub {
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

    done_testing;
};

done_testing;
