# ABOUTME: Tests that linear side-effect statements chain control inputs back to Start.
# ABOUTME: Per Phase 3a-migration, VarDecl/Assign/Call must thread through scope->control.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed refaddr);
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build the generated Perl grammar once.
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR')
    or BAIL_OUT('cannot build pipeline');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CtrlChainTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly')
    or BAIL_OUT("cannot eval: $@");

my $gen_grammar = Chalk::Grammar::Perl::CtrlChainTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# Parse a class with a single method and return the method's MethodInfo.
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

# Find the Start node within a method's graph; first node of class Start.
sub start_of($graph) {
    return undef unless defined $graph;
    return $graph->start();
}

# Walk a side-effect node's control chain. The chain is "the chain of CFG
# predecessors reachable through inputs()[0] (control) at each step". The
# walk stops at Start. Returns the list of nodes traversed (excluding the
# starting node and Start itself), or undef if Start was never reached.
sub control_chain($node) {
    return undef unless defined $node && blessed($node);
    my @chain;
    my $cur = $node;
    my %seen;
    while (defined $cur) {
        last if $cur->operation() eq 'Start';
        return undef if $seen{refaddr($cur)}++;
        push @chain, $cur;
        my $ins = $cur->inputs() // [];
        my $next = $ins->[0];
        return undef unless defined $next && blessed($next);
        $cur = $next;
    }
    return \@chain;
}

# Case 1: single side-effect statement (a my-decl) chains back to Start.
{
    my $source = q{
class C {
    method foo() {
        my $x = 1;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'single-decl method parses and registers')
        or BAIL_OUT('cannot proceed without MethodInfo');

    my $graph = $method->graph;
    isa_ok($graph, 'Chalk::IR::Graph', 'method has a graph');

    my $start = start_of($graph);
    ok(defined $start, 'graph has a Start node');

    # Find a VarDecl in the graph
    my @vardecls;
    for my $node ($graph->nodes->@*) {
        push @vardecls, $node if $node->operation() eq 'VarDecl';
    }
    ok(scalar @vardecls >= 1, 'graph contains at least one VarDecl')
        or diag('node ops: ' . join(',', map { $_->operation() } $graph->nodes->@*));

    SKIP: {
        skip 'no VarDecl to chain-check', 1 unless @vardecls;
        my $chain = control_chain($vardecls[0]);
        ok(defined $chain,
            'VarDecl control chain reaches Start via inputs[0]');
    }
}

# Case 2: two side-effect statements — the second's control points at the
# first, and the first's control points at Start.
{
    my $source = q{
class C {
    method foo() {
        my $x = 1;
        my $y = 2;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'two-decl method parses');

    my $graph = $method->graph;
    my @vardecls = grep { $_->operation() eq 'VarDecl' } $graph->nodes->@*;
    is(scalar @vardecls, 2, 'graph has exactly two VarDecls')
        or diag('node ops: ' . join(',', map { $_->operation() } $graph->nodes->@*));

    SKIP: {
        skip 'wrong VarDecl count', 2 unless scalar @vardecls == 2;
        # Find them by their variable name input.
        my %by_name;
        for my $vd (@vardecls) {
            my $name_input = $vd->inputs->[0];
            next unless defined $name_input && blessed($name_input)
                && $name_input->can('value');
            $by_name{$name_input->value()} = $vd;
        }
        ok(exists $by_name{'$x'}, 'found VarDecl for $x');
        ok(exists $by_name{'$y'}, 'found VarDecl for $y');

        SKIP: {
            skip 'missing one of the VarDecls', 2
                unless exists $by_name{'$x'} && exists $by_name{'$y'};
            my $x_chain = control_chain($by_name{'$x'});
            my $y_chain = control_chain($by_name{'$y'});

            ok(defined $x_chain, '$x VarDecl chain reaches Start');
            # $y's chain should include $x as a predecessor
            ok(defined $y_chain
                && grep { defined && refaddr($_) == refaddr($by_name{'$x'}) }
                    $y_chain->@*,
                '$y VarDecl chain passes through $x VarDecl');
        }
    }
}

done_testing();
