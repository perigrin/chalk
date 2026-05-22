# ABOUTME: Tests that bare-side-effect statements (Call/Assign at statement position) are on the control chain.
# ABOUTME: Strengthens build-graph-reachability.t which only checks VarDecl reachability.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::BareSideEffectsTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::BareSideEffectsTest::grammar();

sub parse_method($source) {
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    $parser->semiring->reset_cache;
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    return undef unless defined $result && !$result->is_zero();
    my ($cls) = grep { $_->name ne 'main' } $mop->classes();
    return undef unless defined $cls;
    my @methods = $cls->methods;
    return undef unless @methods;
    return $methods[0];
}

# Walk the control chain from Return backward via inputs[0].
# Returns the ordered list of side-effect nodes on the chain in SOURCE order
# (predecessors first, Return last). Start node is excluded.
sub control_chain($method) {
    my $graph = $method->graph;
    my @returns = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    return () unless @returns;
    my @rev;  # collected in walk order: Return -> ... -> first stmt
    push @rev, $returns[0];
    my $cur = $returns[0]->inputs->[0];
    while (defined $cur && blessed($cur)) {
        last if $cur->operation eq 'Start';
        push @rev, $cur;
        my $ins = $cur->inputs;
        last unless defined $ins && ref($ins) eq 'ARRAY';
        $cur = $ins->[0];
    }
    return reverse @rev;  # source order: first stmt -> ... -> Return
}

# Probe 1 — bare Call statement (push @list, X) reaches the control chain.
{
    my $source = q{
class P1 {
    method m() {
        my @list = (1, 2);
        push @list, 3;
        return scalar @list;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'P1 method parses');
    if (defined $method) {
        my @chain = control_chain($method);
        my @ops = map { $_->operation } @chain;
        my $has_call = grep { $_ eq 'Call' } @ops;
        ok($has_call,
            "P1: bare 'push' Call is on the control chain (got: " . join(', ', @ops) . ')')
            or diag('control chain: ' . join(', ', @ops));
    }
}

# Probe 2 — bare Call with no data-flow rescue (print "hi") is in the graph
# AND on the control chain. The print Call has no consumer, so it can only
# survive via the control chain.
{
    my $source = q{
class P2 {
    method m() {
        my $x = 1;
        print "hi";
        return $x;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'P2 method parses');
    if (defined $method) {
        my @all_ops = map { $_->operation } $method->graph->nodes->@*;
        my $call_in_graph = grep { $_ eq 'Call' } @all_ops;
        ok($call_in_graph,
            "P2: bare 'print' Call is present in graph (got: @all_ops)");

        my @chain = control_chain($method);
        my @chain_ops = map { $_->operation } @chain;
        my $call_on_chain = grep { $_ eq 'Call' } @chain_ops;
        ok($call_on_chain,
            "P2: bare 'print' Call is on the control chain (got: @chain_ops)");
    }
}

# Probe 3 — bare reassignment ($x = expr at statement position) is on the
# control chain. Today AssignmentExpression returns a BinaryExpr with no
# control input.
{
    my $source = q{
class P3 {
    method m() {
        my $x = 1;
        $x = 2;
        return $x;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'P3 method parses');
    if (defined $method) {
        my @chain = control_chain($method);
        my @chain_ops = map { $_->operation } @chain;
        my $has_assign = grep { $_ eq 'Assign' || $_ eq 'BinaryExpr' } @chain_ops;
        ok($has_assign,
            "P3: bare reassignment is on the control chain (got: @chain_ops)");
    }
}

# Probe 4 — control_chain in source order matches $method->body order.
# This is the property codegen needs to drop $method->body entirely.
{
    my $source = q{
class P4 {
    method m() {
        my $x = 1;
        push @list, 3;
        my $y = 2;
        return $y;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'P4 method parses');
    if (defined $method) {
        my @chain = control_chain($method);
        my @body  = $method->body->@*;
        my @chain_ops = map { $_->operation } @chain;
        my @body_ops  = map { $_->operation } @body;
        is_deeply(\@chain_ops, \@body_ops,
            "P4: control chain matches body order (chain=@chain_ops body=@body_ops)");
    }
}

done_testing();
