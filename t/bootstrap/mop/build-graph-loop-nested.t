# ABOUTME: Tests that nested loops produce correct Phis at each loop header.
# ABOUTME: Per Phase 3c, every loop header that has loop-carried vars gets a Phi.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LoopNestedTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::LoopNestedTest::grammar();
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

# Two nested loops, each with its own loop-carried variable.
# Outer loop: $i. Inner loop: $j. Both should produce Phis at their
# respective loop headers.
{
    my $source = q{
class C {
    method foo() {
        my $i = 0;
        my $j = 0;
        while ($i) {
            while ($j) {
                $j = $j + 1
            }
            $i = $i + 1
        }
        $i
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'nested-loop method parses');

    my $graph = $method->graph;
    my @loops = grep { $_->operation eq 'Loop' } $graph->nodes->@*;
    my @phis  = grep { $_->operation eq 'Phi' } $graph->nodes->@*;

    ok(scalar @loops >= 2, 'two Loop nodes (outer + inner)')
        or diag('Loop count: ' . scalar @loops);
    ok(scalar @phis >= 2, 'at least two Phis (one per loop header)')
        or diag('Phi count: ' . scalar @phis);
}

done_testing();
