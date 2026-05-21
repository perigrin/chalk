# ABOUTME: Tests that loop headers produce Phi nodes for loop-carried variables.
# ABOUTME: Per Phase 3c, WhileStatement and ForeachStatement insert Phis at the loop header.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed refaddr);
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LoopPhiTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::LoopPhiTest::grammar();
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

# While loop with a loop-carried variable: $i increments each iteration.
# After Phase 3c, $i must be represented by a Phi at the loop header
# with two operands: pre-loop value (0) and body-final value (Add).
{
    my $source = q{
class C {
    method foo() {
        my $i = 0;
        while ($i) {
            $i = $i + 1
        }
        $i
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'while-loop method parses');

    my $graph = $method->graph;
    my @nodes = $graph->nodes->@*;
    my @loops = grep { $_->operation eq 'Loop' } @nodes;
    my @phis  = grep { $_->operation eq 'Phi' } @nodes;

    ok(scalar @loops >= 1, 'graph contains a Loop node')
        or diag('ops: ' . join(',', map { $_->operation } @nodes));
    ok(scalar @phis >= 1, 'graph contains a Phi node for $i')
        or diag('Phi count: ' . scalar @phis);
}

# Foreach loop also produces a loop Phi for variables modified in body
# (the iterator itself is NOT a Phi - it has its own iterator node).
{
    my $source = q{
class C {
    method foo() {
        my $sum = 0;
        for my $x (1, 2, 3) {
            $sum = $sum + $x
        }
        $sum
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'foreach method parses');

    my $graph = $method->graph;
    my @nodes = $graph->nodes->@*;
    my @loops = grep { $_->operation eq 'Loop' } @nodes;
    my @phis  = grep { $_->operation eq 'Phi' } @nodes;

    ok(scalar @loops >= 1, 'foreach: graph contains Loop node')
        or diag('ops: ' . join(',', map { $_->operation } @nodes));
    ok(scalar @phis >= 1, 'foreach: Phi for $sum (loop-carried accumulator)')
        or diag('Phi count: ' . scalar @phis);
}

done_testing();
