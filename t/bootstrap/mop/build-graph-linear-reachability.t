# ABOUTME: Tests that linear method-body graphs are reachable from Return via inputs alone.
# ABOUTME: Per Phase 3a-migration, body_stmts seeding is no longer needed for linear code.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ReachTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly')
    or BAIL_OUT("cannot eval: $@");

my $gen_grammar = Chalk::Grammar::Perl::ReachTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

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

# BFS backward from a set of seed nodes through inputs() alone. Returns the
# set of node-refaddrs reached.
sub reachable_from_inputs(@seeds) {
    my %seen;
    my @worklist = @seeds;
    while (my $n = shift @worklist) {
        next unless defined $n && blessed($n);
        next if $seen{refaddr($n)}++;
        my $ins = $n->inputs() // [];
        for my $in ($ins->@*) {
            next unless defined $in;
            if (ref($in) eq 'ARRAY') {
                push @worklist, $in->@*;
            } else {
                push @worklist, $in;
            }
        }
    }
    return \%seen;
}

# Case 1: linear method body — every VarDecl in the graph is reachable from
# Return through inputs() alone (no body_stmts seed needed).
{
    my $source = q{
class C {
    method foo() {
        my $x = 1;
        my $y = 2;
        my $z = 3;
        return $z;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'linear method parses')
        or BAIL_OUT('no method');

    my $graph = $method->graph;
    isa_ok($graph, 'Chalk::IR::Graph');

    # All nodes in the graph
    my @all = $graph->nodes->@*;
    ok(scalar @all >= 1, 'graph contains nodes')
        or diag('no graph nodes - graph appears empty');

    # The Return node is the exit. Find it.
    my $returns = $graph->returns();
    my @return_nodes = $returns->@*;
    ok(scalar @return_nodes >= 1, 'graph has at least one Return node')
        or diag('no Return - graph has not been populated');

    SKIP: {
        skip 'no Return node to walk from', 1 unless @return_nodes;
        my $reached = reachable_from_inputs(@return_nodes);

        my @vardecls = grep { $_->operation() eq 'VarDecl' } @all;
        ok(scalar @vardecls >= 3, 'graph contains all three VarDecls')
            or diag('found ' . scalar @vardecls . ' VarDecls; ops: '
                . join(',', map { $_->operation } @all));

        my @missing = grep { !$reached->{refaddr($_)} } @vardecls;
        is(scalar @missing, 0,
            'every VarDecl reachable from Return via inputs() alone')
            or diag('missing VarDecls: '
                . join(',', map { 'VarDecl' } @missing));
    }
}

# Case 2: graph's body_stmts seed isn't required for reachability — assert
# that nodes() == reachable-from-cache, no body_stmts dependency. After
# migration, body_stmts will be empty for linear bodies because graph is
# built via merge() at node-construction time.
{
    my $source = q{
class C {
    method bar() {
        my $a = 1;
        return $a;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'simple linear method parses');

    my $graph = $method->graph;
    # Post-Phase 7, body_stmts is gone entirely; the graph is built via
    # merge() and walked bidirectionally via nodes().
    ok(!$graph->can('body_stmts'),
        'graph has no body_stmts (Phase 7)');
}

done_testing();
