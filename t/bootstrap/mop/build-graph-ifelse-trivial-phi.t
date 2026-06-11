# ABOUTME: Tests Phi creation at if/else merges when both branches assign the
# ABOUTME: same source value: statement-effect identity makes the Assigns distinct.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

my $raw_ir = perl_pipeline();
ok(defined $raw_ir) or BAIL_OUT('pipeline');
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TrivialPhiTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::TrivialPhiTest::grammar();
ok(defined $gen_grammar);

sub parse_method($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    return undef unless defined $result && !$result->is_zero();
    my ($cls) = grep { $_->name ne 'main' } $mop->classes();
    return undef unless defined $cls;
    my @methods = $cls->methods;
    return undef unless @methods;
    return $methods[0];
}

# `$x` is assigned the same SOURCE value in both branches — but the two
# Assigns are distinct statement effects (%STATEMENT_EFFECT_OPS per-call
# identity: two textually-identical effects must never share a node, or one
# of two sequential identical stores is silently dropped). The bindings hold
# the Assign node, so the merge sees two distinct values and creates a Phi.
# That Phi is CORRECT: each arm carries its branch's effect node. Folding it
# away because both effects produce the same value is value-level CSE — an
# optimizer-layer concern, not a bindings-merge concern.
#
# History: this file originally asserted ZERO Phis here. That expectation
# depended on Assign hash-consing (both branches collapsing to ONE node),
# which is the statement-collapse miscompile family (whole-branch review C3).
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        if (1) { $x = 5 } else { $x = 5 }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'trivial-phi method parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;
    is(scalar @phis, 1,
        'one Phi when both branches assign the same value via distinct effects')
        or diag('Phis: ' . scalar @phis);
    if (@phis == 1) {
        my @arm_ops = map { blessed($_) ? $_->operation : 'undef' }
            grep { defined } $phis[0]->inputs()->@*;
        is_deeply(\@arm_ops, ['Assign', 'Assign'],
            'Phi arms are the two distinct branch Assign effects');
        my ($a, $b) = grep { defined } $phis[0]->inputs()->@*;
        isnt($a->id, $b->id, 'the two arms are distinct per-call nodes');
    }
}

# A variable NOT touched by either branch keeps its identity-shared binding
# straight through the merge — no Phi. This is the identity-based no-merge
# path that legitimately survives statement-effect identity.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        my $y = 1;
        if (1) { $y = 5 } else { $y = 6 }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'untouched-variable method parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;
    is(scalar @phis, 1,
        'only the divergent variable gets a Phi; the untouched one does not');
}

done_testing();
