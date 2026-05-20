# ABOUTME: Tests that variables only READ in loops don't get Phis.
# ABOUTME: Per Phase 3c, only loop-carried (modified) variables get a header Phi.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LoopUnusedTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::LoopUnusedTest::grammar();
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

# $i is loop-carried (modified). $k is only read inside the body
# (never reassigned). Expected: exactly one Phi (for $i), none for $k.
{
    my $source = q{
class C {
    method foo() {
        my $i = 0;
        my $k = 99;
        while ($i) {
            $i = $i + $k
        }
        $i
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'method parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;

    is(scalar @phis, 1,
        'exactly one Phi (for $i); $k only read, gets none')
        or diag('Phi count: ' . scalar @phis);
}

done_testing();
