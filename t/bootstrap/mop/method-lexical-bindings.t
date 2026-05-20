# ABOUTME: Tests that MethodDefinition registers VarDecl IR nodes as lexical bindings.
# ABOUTME: Per Phase 3a-migration, MethodInfo+MOP::Method expose body VarDecls as metadata.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LexBindTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly')
    or BAIL_OUT("cannot eval: $@");

my $gen_grammar = Chalk::Grammar::Perl::LexBindTest::grammar();
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

# Helper: extract the variable name from a VarDecl node.
sub vardecl_name($node) {
    return undef unless defined $node && blessed($node)
        && $node->operation() eq 'VarDecl';
    my $name_input = $node->name();
    return undef unless defined $name_input && blessed($name_input)
        && $name_input->can('value');
    return $name_input->value();
}

# Case 1: method with three my-declarations registers three lexical bindings.
{
    my $source = q{
class C {
    method foo() {
        my $x = 1;
        my $y = 2;
        my $z = 3;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'three-decl method parses')
        or BAIL_OUT('no method');

    ok($method->can('lexical_bindings'),
        'MOP::Method has lexical_bindings accessor');

    SKIP: {
        skip 'no lexical_bindings accessor', 3
            unless $method->can('lexical_bindings');

        my @bindings = $method->lexical_bindings;
        is(scalar @bindings, 3,
            'three VarDecls registered as lexical bindings');

        my @names = sort map { vardecl_name($_) // '' } @bindings;
        is_deeply(\@names, [qw($x $y $z)],
            'lexical bindings expose the declared variable names');

        my @ops = map { ref($_) && $_->can('operation')
            ? $_->operation : '?' } @bindings;
        is_deeply([sort @ops], [('VarDecl') x 3],
            'every registered binding is a VarDecl IR node');
    }
}

# Case 2: method with no declarations has no lexical bindings.
{
    my $source = q{
class C {
    method foo() {
        return 1;
    }
}
};
    my $method = parse_method($source);
    ok(defined $method, 'no-decl method parses');

    SKIP: {
        skip 'no lexical_bindings accessor', 1
            unless $method->can('lexical_bindings');
        my @bindings = $method->lexical_bindings;
        is(scalar @bindings, 0,
            'method with no declarations has zero lexical bindings');
    }
}

done_testing();
