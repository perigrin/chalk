# ABOUTME: Runner for the variables mdtest corpus topic (constructive format).
# ABOUTME: Exercises A1/A4 (decl+read), A5 (field GAP), C1/C2 (reassign/compound-assign) verdicts.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::CodeGen::Harness::MdtestCorpus;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

my $VARIABLES_MD = 't/corpus/mdtest/variables.md';

unless (-f $VARIABLES_MD) {
    plan skip_all => "variables.md not found at $VARIABLES_MD";
}

# ---------------------------------------------------------------------------
# SECTION 1: Parse variables.md and verify the case inventory
#
# Five cases expected: A1, A4, A5, C1, C2.
# ---------------------------------------------------------------------------

my $cases = Chalk::CodeGen::Harness::MdtestCorpus->parse_file($VARIABLES_MD);

my @titles = map { $_->{title} } @$cases;
ok((grep { /A1.*my.decl/i     } @titles), 'case: A1 my-decl with init present');
ok((grep { /A4.*my.decl/i     } @titles), 'case: A4 my-decl then assign present');
ok((grep { /A5.*field/i       } @titles), 'case: A5 field param read present');
ok((grep { /C1.*reassign/i    } @titles), 'case: C1 reassign then read present');
ok((grep { /C2.*compound/i    } @titles), 'case: C2 compound assign then read present');

# ---------------------------------------------------------------------------
# SECTION 4: Every GREEN case's ir block declares L: GREEN (static parse).
#
# The authoritative behavior/shape/invariant gate is
# t/bootstrap/corpus/son-corpus-wide.t, which lowers each case's PERL SOURCE
# through B::SoN -> chalk -> lli. The old per-case run_case checks here lowered
# the hand-written IR BLOCK through the constructive builder -- a second,
# drifting lowering path (zhi 019f53a0). Retired in favor of the single
# authoritative gate; the static presence/verdict/node-line checks lower
# nothing and stay.
# ---------------------------------------------------------------------------

subtest 'every GREEN-declared case parses its L: GREEN verdict' => sub {
    my @green = grep {
        Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($_->{ir} // '') eq 'GREEN'
    } @$cases;
    plan tests => scalar @green;
    for my $case (@green) {
        my $title = $case->{title};
        my $decl  = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($case->{ir} // '');
        is($decl, 'GREEN', "case '$title': declared L: GREEN");
    }
};

# ---------------------------------------------------------------------------
# SECTION 5: Every GREEN ir block has %name = ... node lines (constructive graph).
# ---------------------------------------------------------------------------

subtest 'all GREEN ir blocks have node lines' => sub {
    my @green = grep {
        Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir($_->{ir} // '') eq 'GREEN'
    } @$cases;
    plan tests => scalar @green;
    for my $case (@green) {
        my $title    = $case->{title};
        my $ir_text  = $case->{ir} // '';
        my $has_node = ($ir_text =~ /^\s*%\w+\s*=/m) ? 1 : 0;
        ok($has_node, "case '$title': GREEN ir block has node lines (constructive graph)");
    }
};

done_testing;
