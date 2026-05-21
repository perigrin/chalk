# ABOUTME: Tests Phi placement for if-inside-loop and loop-inside-if.
# ABOUTME: Per Phase 3c, mixed control flow produces correct Phi at each merge point.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LoopIfTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::LoopIfTest::grammar();
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

# Case 1: if inside loop. The if's merge produces a Phi for $x; the
# loop's header then produces another Phi for $x carrying the merge.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        while ($x) {
            if ($x) { $x = 1 } else { $x = 2 }
        }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'if-inside-loop parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;
    # Expect >=2: one for if/else merge, one for loop header.
    ok(scalar @phis >= 2, 'if-inside-loop: at least 2 Phis')
        or diag('Phi count: ' . scalar @phis);
}

# Case 2: loop inside if. Loop's header Phi for loop-carried var; the
# enclosing if/else's merge produces a Phi merging the post-loop scope
# vs the else-branch's scope.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        if ($x) {
            while ($x) {
                $x = $x + 1
            }
        } else {
            $x = 99
        }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'loop-inside-if parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;
    ok(scalar @phis >= 2, 'loop-inside-if: at least 2 Phis')
        or diag('Phi count: ' . scalar @phis);
}

done_testing();
