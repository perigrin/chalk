# ABOUTME: Tests that trivial Phi (both operands identical) is eliminated inline.
# ABOUTME: Per Phase 3b, IfStatement merges-with-phis runs _remove_trivial_phi.
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

# `$x` is assigned the SAME value in both branches. Phi would have both
# operands equal -> trivial -> eliminated. No Phi should appear.
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
    is(scalar @phis, 0,
        'no Phi node when both branches assign identical value')
        or diag('Phis: ' . scalar @phis);
}

# Trivial-elimination only fires for IDENTICAL nodes by identity.
# Two separately-constructed Constants with the same value are also
# hash-consed to the same identity, so this case is trivial too.
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        if (1) { $x = 'same' } else { $x = 'same' }
        $x
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'identity-elim method parses');

    my $graph = $method->graph;
    my @phis = grep { $_->operation eq 'Phi' } $graph->nodes->@*;
    is(scalar @phis, 0,
        'no Phi node for hash-consed-identical branch values');
}

done_testing();
