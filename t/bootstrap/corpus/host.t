# ABOUTME: Runner for the host mdtest corpus topic (constructive format).
# ABOUTME: Asserts the topic's static inventory + L declarations; behavior/shape/invariant is owned by son-corpus-wide.t.
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
# SECTION 1: Parse host.md and verify the topic's named idioms are present.
#
# This runner asserts the STATIC inventory + L declarations of the corpus file.
# The authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path with hardcoded case counts that went stale on every
# corpus addition (zhi 019f53a0). Retired in favor of the single authoritative
# gate; the presence/declaration checks below lower nothing and stay.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($HOST_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /H1.*capture/i  } @titles), 'case: H1 capture read present');
ok((grep { /H2.*guarded/i  } @titles), 'case: H2 guarded capture present');
ok((grep { /H3.*environ/i  } @titles), 'case: H3 environment read present');

# ---------------------------------------------------------------------------
# SECTION 3: All cases declare L: GREEN
# ---------------------------------------------------------------------------

subtest 'H1-H3 all declare L: GREEN' => sub {
    plan tests => scalar @$cases;
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
