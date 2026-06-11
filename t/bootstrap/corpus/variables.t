# ABOUTME: Runner for the variables mdtest corpus topic (constructive format).
# ABOUTME: Exercises A1/A4 (decl+read), A5 (field GAP), C1/C2 (reassign/compound-assign) verdicts.
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
is(scalar(@$cases), 5, 'variables.md has 5 cases');

my @titles = map { $_->{title} } @$cases;
ok((grep { /A1.*my.decl/i     } @titles), 'case: A1 my-decl with init present');
ok((grep { /A4.*my.decl/i     } @titles), 'case: A4 my-decl then assign present');
ok((grep { /A5.*field/i       } @titles), 'case: A5 field param read present');
ok((grep { /C1.*reassign/i    } @titles), 'case: C1 reassign then read present');
ok((grep { /C2.*compound/i    } @titles), 'case: C2 compound assign then read present');

# ---------------------------------------------------------------------------
# SECTION 2: Run all five cases end-to-end
#
# For each case the runner checks:
#   - behavior oracle (perl says the right thing)
#   - ir-shape (graph builds and passes TypedInvariant, or pure-GAP)
#   - L-verdict (declared verdict matches the real L corner)
#
# GREEN cases: graph lowers via lli; lli output == perl oracle.
# (A5 declares class structure via MOP::* lines; its sealed MOP rides to
# the backend through LLVMDriver's mop opt.)
# ---------------------------------------------------------------------------

for my $case (@$cases) {
    my $title = $case->{title};

    subtest "case: $title" => sub {
        my $result = Chalk::CodeGen::Harness::MdtestCorpus->run_case($case, {});

        # Behavior check
        is($result->{behavior}{verdict}, 'PASS',
            "$title: behavior oracle matches")
            or diag("  behavior fail: " . join('; ', @{ $result->{fail_reasons} }));

        # IR-shape check (TypedInvariant on the built graph, or pure-GAP pass)
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

        # For GREEN cases: prove the graph built from the block goes through lli
        # and matches the perl oracle (the load-bearing proof of GREEN).
        my $decl_verdict = Chalk::CodeGen::Harness::MdtestCorpus->parse_l_verdict_from_ir(
            $case->{ir} // '');
        if ($decl_verdict eq 'GREEN') {
            my ($return_node, $case_mop) =
                Chalk::CodeGen::Harness::MdtestCorpus->build_graph_from_ir($case->{ir});
            ok(defined $return_node, "$title: build_graph_from_ir returns a node");
            if (defined $return_node) {
                my ($L, $meta) = Chalk::CodeGen::Harness::LLVMDriver->run($return_node,
                    { (defined $case_mop ? (mop => $case_mop) : ()) });
                ok(!$meta->{marked_unsupported},
                    "$title: built-from-block graph is truly GREEN (not marked_unsupported)");
                my $lli_out  = $L->return_values->[0] // '';
                my $perl_out = $case->{_perl_actual} // '';
                if (length $perl_out) {
                    is($lli_out, $perl_out,
                        "$title: lli output '$lli_out' == perl oracle '$perl_out' (built from block)");
                }
            }
        }
    };
}

done_testing;
