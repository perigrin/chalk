# ABOUTME: Runner for the host mdtest corpus topic (constructive format).
# ABOUTME: H1-H3 exercise $N capture edges + %ENV reads (G7); all lower GREEN via lli==perl.
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

my $HOST_MD = 't/corpus/mdtest/host.md';

unless (-f $HOST_MD) {
    plan skip_all => "host.md not found at $HOST_MD";
}

# H3 reads $ENV{CHALK_G7_TEST}; both the perl-oracle and lli child processes
# inherit this runner's environment (see the case prose in host.md).
local $ENV{CHALK_G7_TEST} = 'hostval';

# ---------------------------------------------------------------------------
# SECTION 1: Parse host.md and verify case inventory
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($HOST_MD);
is(scalar(@$cases), 3, 'host.md has 3 cases (H1-H3)');

my @titles = map { $_->{title} } @$cases;
ok((grep { /H1.*capture/i  } @titles), 'case: H1 capture read present');
ok((grep { /H2.*guarded/i  } @titles), 'case: H2 guarded capture present');
ok((grep { /H3.*environ/i  } @titles), 'case: H3 environment read present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all cases end-to-end
#
# For each case: behavior must PASS (perl oracle), ir-shape must not FAIL,
# and the L verdict must PASS (declared GREEN backed by an actual lowering
# with lli==perl).
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        is($result->{behavior}{verdict}, 'PASS', "$title: behavior oracle matches")
            or diag('  behavior fail: ' . join('; ', @{ $result->{fail_reasons} }));
        isnt($result->{ir_shape}{verdict}, 'FAIL', "$title: ir-shape not FAIL")
            or diag('  ir-shape fail: ' . join('; ', @{ $result->{fail_reasons} }));
        is($result->{l_verdict}{verdict}, 'PASS', "$title: L verdict matches")
            or diag('  L fail: ' . join('; ', @{ $result->{fail_reasons} }));
        is($result->{overall}, 'PASS', "$title: overall PASS")
            or diag('  fail reasons: ' . join('; ', @{ $result->{fail_reasons} }));
    };
}

# ---------------------------------------------------------------------------
# SECTION 3: All cases declare L: GREEN
# ---------------------------------------------------------------------------

subtest 'H1-H3 all declare L: GREEN' => sub {
    plan tests => 3;
    for my $case (@$cases) {
        my $decl = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($case->{ir} // '');
        is($decl, 'GREEN', "case '$case->{title}': declared L: GREEN");
    }
};

# ---------------------------------------------------------------------------
# SECTION 4: Negative guard — a GREEN claim without a graph must FAIL
# ---------------------------------------------------------------------------

subtest 'guard: pure-GAP block with L: GREEN for a capture read FAILS L verdict' => sub {
    my $fake_green_md = <<'END_MD';
# Fake

## Fake GREEN capture case

```perl
# source
my $s = "ab"; $s =~ /(a)/; $1
```

```behavior
return: Str:a
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
    my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($fake_cases->[0], {});

    is($result->{l_verdict}{verdict}, 'FAIL', 'pure-GAP block claiming L: GREEN is FAIL');
    is($result->{overall}, 'FAIL', 'overall is FAIL');
};

done_testing;
