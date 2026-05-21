# ABOUTME: Tests that ANY valid method body reaches every stmt from start via inputs().
# ABOUTME: Per Phase 3c, generalizes the linear-only reachability check from 3a.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ReachAnyTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::ReachAnyTest::grammar();
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

# Walk backward from a set of seed nodes through inputs() alone.
# Returns the set of node-refaddrs reached.
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

# For each kind of body, check that every VarDecl in the graph is
# reachable from a Return via inputs() alone, AND that body_stmts seed
# is empty (graph built via merge, not seeded).
sub check_reachability($method, $label) {
    my $graph = $method->graph;
    my @all = $graph->nodes->@*;
    my @vardecls = grep { $_->operation eq 'VarDecl' } @all;
    my @returns  = grep { $_->operation eq 'Return' } @all;

    SKIP: {
        skip "$label: no VarDecls or Returns to walk", 1
            unless @vardecls && @returns;
        my $reached = reachable_from_inputs(@returns);
        my @missing = grep { !$reached->{refaddr($_)} } @vardecls;
        is(scalar @missing, 0,
            "$label: every VarDecl reachable from Return via inputs() alone")
            or diag("missing $label VarDecls: " . scalar @missing);
    }

    ok(!$graph->can('body_stmts'),
        "$label: graph has no body_stmts (Phase 7)");
}

# Linear method (already tested by 3a; revalidated here)
{
    my $source = q{
class C {
    method foo() {
        my $x = 1;
        my $y = 2;
        return $y;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'linear method parses');
    check_reachability($method, 'linear') if defined $method;
}

# If/else method
{
    my $source = q{
class C {
    method foo() {
        my $x = 0;
        if (1) { $x = 1 } else { $x = 2 }
        return $x;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'if/else method parses');
    check_reachability($method, 'if/else') if defined $method;
}

# While loop
{
    my $source = q{
class C {
    method foo() {
        my $i = 0;
        while ($i) {
            $i = $i + 1
        }
        return $i;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'while-loop method parses');
    check_reachability($method, 'while-loop') if defined $method;
}

done_testing();
