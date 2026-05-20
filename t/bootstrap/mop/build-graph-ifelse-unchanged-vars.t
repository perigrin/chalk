# ABOUTME: Tests that vars unchanged in both branches get no Phi.
# ABOUTME: Per Phase 3b, only divergent bindings produce a Phi.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir) or BAIL_OUT('pipeline');
my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::UnchangedVarsTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::UnchangedVarsTest::grammar();
ok(defined $gen_grammar);

sub parse_method($source) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
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

# $x is assigned only in the then-branch; $y is unchanged in both branches.
# Only $x should get a Phi (then-branch value vs pre-branch value of $x).
# $y should get NO Phi because both branches see the pre-branch binding.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        my $y = 99;
        if (1) {
            $x = 1
        } else {
            $x = 2
        }
        $y
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'method parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;

    # We can't easily ask "which variable does this Phi represent" without
    # walking the merged scope. Approximation: only $x diverges across the
    # two branches, so exactly one Phi should land in the graph.
    is(scalar @phis, 1,
        'exactly one Phi (for $x); $y unchanged in both branches gets none')
        or diag('Phi count: ' . scalar @phis);
}

done_testing();
