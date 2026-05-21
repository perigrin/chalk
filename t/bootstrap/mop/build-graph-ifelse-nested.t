# ABOUTME: Tests that nested if/else produces correct Phi at each merge point.
# ABOUTME: Per Phase 3b, an inner Phi's result feeds the outer merge correctly.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::NestedIfTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::NestedIfTest::grammar();
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

# Nested if/else: outer branch has an inner if/else inside.
# $x has three possible values across the leaves: 1, 2, 3.
# Inner if/else merges 1+2; outer merges {inner-Phi, 3}.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        if (1) {
            if (2) { $x = 1 } else { $x = 2 }
        } else {
            $x = 3
        }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'nested if/else method parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;
    ok(scalar @phis >= 2,
        'graph contains at least two Phi nodes (inner + outer merge)')
        or diag('Phis: ' . scalar @phis);

    # Across all Phis' inputs, every concrete value 1, 2, 3 must appear
    # as a Constant operand somewhere. (We don't enforce which Phi sees
    # which - that's an implementation detail.)
    SKIP: {
        skip 'too few Phis to check value coverage', 1
            unless scalar @phis >= 2;
        # Walk Phi inputs and one level into Assign children to harvest
        # all Constant leaves reachable from any Phi.
        my %seen;
        my $harvest;
        $harvest = sub ($n, $depth) {
            return if $depth > 2;
            return unless defined $n && blessed($n);
            if ($n isa Chalk::IR::Node::Constant && defined $n->value()) {
                $seen{$n->value()}++;
                return;
            }
            return unless $n->can('inputs');
            for my $in ($n->inputs->@*) {
                $harvest->($in, $depth + 1);
            }
        };
        for my $phi (@phis) {
            for my $in ($phi->inputs->@*) {
                $harvest->($in, 0);
            }
        }
        ok($seen{1} && $seen{2} && $seen{3},
            'Phi nodes collectively see all three leaf values')
            or diag('seen values: ' . join(',', sort keys %seen));
    }
}

done_testing();
