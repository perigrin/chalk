# ABOUTME: Tests that MethodDefinition synthesizes/collects Return nodes correctly.
# ABOUTME: Per Phase 3a-migration, fall-through synthesizes Return; explicit Returns preserved.
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

# Build the generated Perl grammar once.
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR')
    or BAIL_OUT('cannot build pipeline');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ImplicitRetTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly')
    or BAIL_OUT("cannot eval: $@");

my $gen_grammar = Chalk::Grammar::Perl::ImplicitRetTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

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

sub return_ops($graph) {
    return () unless defined $graph;
    my @r;
    for my $n ($graph->returns->@*) {
        push @r, $n->operation();
    }
    return @r;
}

# Case 1: fall-through synthesizes a Return wrapping the final expression.
{
    my $source = q{
class C {
    method foo() {
        42
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'fall-through method parses');

    my $graph = $method->graph;
    my @returns = $graph->returns->@*;
    is(scalar @returns, 1, 'fall-through synthesizes exactly one Return')
        or diag('got ' . scalar @returns . ' returns');

    SKIP: {
        skip 'no Return synthesized', 1 unless @returns;
        is($returns[0]->operation, 'Return',
            'synthesized exit is a Return (not Unwind)');
    }
}

# Case 2: explicit `return` is preserved as the method's Return exit.
{
    my $source = q{
class C {
    method foo() {
        return 42;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'explicit-return method parses');

    my $graph = $method->graph;
    my @returns = $graph->returns->@*;
    is(scalar @returns, 1, 'explicit return yields exactly one Return exit');

    SKIP: {
        skip 'no Return', 1 unless @returns;
        is($returns[0]->operation, 'Return', 'exit is a Return');
    }
}

# Case 3: nested Return inside an if-branch is collected as a method exit,
# alongside the fall-through synthetic Return.
{
    my $source = q{
class C {
    method foo() {
        if (1) { return 1 }
        2
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'nested-Return method parses');

    my $graph = $method->graph;
    my @ops = return_ops($graph);
    my $return_count = scalar grep { $_ eq 'Return' } @ops;
    ok($return_count >= 2,
        'method has two Return exits (nested + fall-through)')
        or diag('return ops: ' . join(',', @ops));
}

# Case 4: a Return inside a nested sub does NOT become a method exit of the
# enclosing method. The inner sub has its own graph.
{
    my $source = q{
class C {
    method foo() {
        my $helper = sub { return 99 };
        42
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'method-with-inner-sub parses');

    my $graph = $method->graph;
    my @returns = $graph->returns->@*;
    # Exactly one Return at this level: the fall-through 'return 42'.
    # The inner sub's `return 99` lives on the SubInfo's own graph and
    # must not pollute the outer method's exits.
    is(scalar @returns, 1,
        'inner-sub Return does not become an outer-method exit')
        or diag('returns: ' . scalar @returns
            . ', ops: ' . join(',', return_ops($graph)));
}

done_testing();
