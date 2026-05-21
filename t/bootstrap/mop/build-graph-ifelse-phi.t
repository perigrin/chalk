# ABOUTME: Tests that if/else merge creates Phi for vars that differ between branches.
# ABOUTME: Per Phase 3b, IfStatement inserts Phi at the Region for divergent bindings.
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
ok(defined $raw_ir, 'perl_pipeline produces grammar IR') or BAIL_OUT('pipeline');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::IfElsePhiTest/g;
eval $generated;
is($@, '', 'generated grammar evals cleanly') or BAIL_OUT("eval: $@");

my $gen_grammar = Chalk::Grammar::Perl::IfElsePhiTest::grammar();
ok(defined $gen_grammar, 'grammar loaded');

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

# `$x` differs between branches: then-branch assigns 1, else-branch assigns 2.
# After the if/else, $x must be a Phi node merging both values.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        if (1) { $x = 1 } else { $x = 2 }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'method with divergent if/else parses')
        or BAIL_OUT('no method');

    my $graph = $method->graph;
    my @nodes = $graph->nodes->@*;
    my @phis = grep { $_->operation eq 'Phi' } @nodes;
    ok(scalar @phis >= 1, 'graph contains at least one Phi node')
        or diag('ops: ' . join(',', map { $_->operation } @nodes));

    # The Phi merges the per-branch scope bindings for $x. Each branch
    # binds $x to an Assign IR node (the BinaryExpr for `$x = 1` and
    # `$x = 2` respectively). The Phi's two value inputs should be those
    # two Assign nodes; descending into each Assign's `right` operand
    # yields the Constant value (1 / 2).
    SKIP: {
        skip 'no Phi to inspect', 2 unless @phis;
        my $phi = $phis[0];
        my %seen_vals;
        for my $v ($phi->inputs->@*) {
            next unless defined $v && blessed($v);
            # Direct Constant child
            if ($v isa Chalk::IR::Node::Constant && defined $v->value()) {
                $seen_vals{$v->value()}++;
                next;
            }
            # Walk one level into Assign-like nodes to find the value
            if ($v->operation() =~ /^(?:Assign|Add|Subtract|Multiply|Divide|Concat|Constant)$/) {
                for my $inner ($v->inputs->@*) {
                    next unless defined $inner && blessed($inner)
                        && $inner isa Chalk::IR::Node::Constant
                        && defined $inner->value();
                    $seen_vals{$inner->value()}++;
                }
            }
        }
        ok($seen_vals{1} || $seen_vals{'1'},
            'Phi merge reaches then-branch value 1')
            or diag('seen: ' . join(',', sort keys %seen_vals));
        ok($seen_vals{2} || $seen_vals{'2'},
            'Phi merge reaches else-branch value 2')
            or diag('seen: ' . join(',', sort keys %seen_vals));
    }
}

done_testing();
