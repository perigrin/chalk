# ABOUTME: Runner for the strings mdtest corpus topic (constructive format).
# ABOUTME: S1-S4 are GREEN (Str ASCII/default-encoding lowered); S5 is the explicit non-ASCII GAP boundary.
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
# SECTION 1: Parse strings.md and verify the topic's named idioms are present.
#
# String cases: S1-S4 GREEN, S5 GAP (non-ASCII boundary).
#
# This runner asserts the STATIC inventory + shape of the corpus file. The
# authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition (zhi 019f53a0). Retired here in favor of the single
# authoritative gate.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($STRINGS_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /S1.*single/i         } @titles), 'case: S1 single-quoted literal present');
ok((grep { /S2.*double/i         } @titles), 'case: S2 double-quoted literal present');
ok((grep { /S3.*concat.*dot/i    } @titles), 'case: S3 dot concat present');
ok((grep { /S4.*concat.*assign/i } @titles), 'case: S4 concat-assign present');
ok((grep { /S5.*non.ASCII/i      } @titles), 'case: S5 non-ASCII GAP boundary present');

# @green_cases: every case except the S5 non-ASCII GAP boundary. Feeds the
# L-verdict declaration check (SECTION 2) and the libperl-free .ll probe
# (SECTION 5).
my @green_cases = grep { $_->{title} !~ /S5/i } @$cases;

# ---------------------------------------------------------------------------
# SECTION 2: Verify L: verdict for each case
#
# S1-S4: must declare and achieve L: GREEN
# S5: must declare L: GAP (explicit non-ASCII boundary)
# ---------------------------------------------------------------------------

subtest 'S1-S4 declare and achieve L: GREEN' => sub {
    plan tests => scalar @green_cases;
    for my $case (@green_cases) {
        my $ir_text = $case->{ir} // '';
        my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
        my $title   = $case->{title};
        is($decl, 'GREEN', "case '$title': declared L: GREEN");
    }
};

subtest 'S5 declares L: GAP (non-ASCII boundary)' => sub {
    my ($s5) = grep { $_->{title} =~ /S5/i } @$cases;
    ok(defined $s5, 'S5 case found');
    my $ir_text = $s5->{ir} // '';
    my $decl    = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($ir_text);
    is($decl, 'GAP', 'S5 declared L: GAP');
};

# ---------------------------------------------------------------------------
# SECTION 3: Run S5 (GAP) and verify it does NOT lower
# ---------------------------------------------------------------------------

subtest 'S5 non-ASCII GAP: pure-GAP block stays GAP, not lowered' => sub {
    my ($s5) = grep { $_->{title} =~ /S5/i } @$cases;
    ok(defined $s5, 'S5 found');
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($s5, {});
    is($result->{l_verdict}{verdict}, 'PASS',
        'S5: L verdict PASS (declared GAP, actual GAP — consistent)')
        or diag("  L fail: " . join('; ', @{ $result->{fail_reasons} }));
    is($result->{overall}, 'PASS', 'S5: overall PASS')
        or diag("  fail reasons: " . join('; ', @{ $result->{fail_reasons} }));
};

# ---------------------------------------------------------------------------
# SECTION 4: Negative guard — a string case claiming GREEN with a pure-GAP
#            block must FAIL (harness integrity check)
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

# ---------------------------------------------------------------------------
# SECTION 5: Libperl-free guard — emitted .ll for S1-S4 must not reference
#            Perl_/SV*/sv_ symbols (the LLVM backend must be runtime-free)
# ---------------------------------------------------------------------------

subtest 'S1-S4 emitted .ll is libperl-free' => sub {
    plan tests => scalar(@green_cases);
    for my $case (@green_cases) {
        my $title = $case->{title};
        my $ir_text = $case->{ir} // '';

        my $return_node;
        eval { $return_node = Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($ir_text) };
        if ($@ || !defined $return_node) {
            fail("$title: could not build graph: $@");
            next;
        }

        my (undef, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node);
        my $ll = $meta->{ll_text} // '';

        ok($ll !~ /Perl_|\bSV\b|sv_|libperl/,
            "$title: emitted .ll has no libperl symbols")
            or diag("  libperl symbols found in emitted .ll:\n$ll");
    }
};

done_testing;
