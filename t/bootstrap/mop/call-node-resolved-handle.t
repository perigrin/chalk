# ABOUTME: Tests that a Call node's target is a Chalk::MOP::Method reference, not a string.
# ABOUTME: Per Phase 4, CallExpression resolves the callee via $mop->find_method().
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CallHandleTest/g;
eval $generated;
is($@, '', 'grammar evals') or BAIL_OUT("eval: $@");
my $gen_grammar = Chalk::Grammar::Perl::CallHandleTest::grammar();

# Parse a class with two methods where one calls the other. The Call
# node for $self->bar() inside foo() should have its target resolved to
# the MOP::Method handle for `bar`, not the literal string 'bar'.
my $source = q{
class Calc {
    method bar() { return 1; }
    method foo() { $self->bar() }
}
};

my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
my $result = $parser->parse_value($source);
ok(defined $result && !$result->is_zero(), 'class with cross-method call parses')
    or BAIL_OUT('parse');

my ($cls) = grep { $_->name eq 'Calc' } $mop->classes();
ok(defined $cls, 'Calc class on MOP');

my ($foo) = grep { $_->name eq 'foo' } $cls->methods;
my ($bar) = grep { $_->name eq 'bar' } $cls->methods;
ok(defined $foo && defined $bar, 'both methods registered');

SKIP: {
    skip 'methods not found', 2 unless defined $foo && defined $bar;

    # Walk foo's graph for a Call node and check its target.
    my @calls;
    for my $n ($foo->graph->nodes->@*) {
        push @calls, $n if blessed($n) && $n->operation eq 'Call';
    }
    ok(scalar @calls >= 1, 'foo has at least one Call node in graph')
        or diag('ops: ' . join(',',
            map { $_->operation } $foo->graph->nodes->@*));

    SKIP: {
        skip 'no Call nodes', 1 unless @calls;
        # At least one Call's resolved target is a MOP::Method matching bar.
        my $resolved = grep {
            my $t = $_->can('target') ? $_->target() : undef;
            defined $t && blessed($t) && $t isa Chalk::MOP::Method
                && $t->name eq 'bar';
        } @calls;
        ok($resolved,
            'Call->target is a Chalk::MOP::Method handle for bar');
    }
}

done_testing();
