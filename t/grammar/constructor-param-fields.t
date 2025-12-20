# ABOUTME: Tests :param field extraction from ClassDeclaration
# ABOUTME: Verifies Class type correctly tracks constructor parameters
use 5.42.0;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;

use lib "$RealBin/../../lib";
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::TypeRegistry;
use Chalk::Semiring::Semantic;

# Load all necessary rule classes for semantic actions
use Chalk::Grammar::Chalk::Rule::ClassDeclaration;
use Chalk::Grammar::Chalk::Rule::QualifiedIdentifier;
use Chalk::Grammar::Chalk::Rule::Identifier;
use Chalk::Grammar::Chalk::Rule::Block;
use Chalk::Grammar::Chalk::Rule::StatementList;
use Chalk::Grammar::Chalk::Rule::Statement;
use Chalk::Grammar::Chalk::Rule::Assignment;
use Chalk::Grammar::Chalk::Rule::VariableDeclaration;
use Chalk::Grammar::Chalk::Rule::Variable;
use Chalk::Grammar::Chalk::Rule::ScalarVar;
use Chalk::Grammar::Chalk::Rule::LexicalDeclarator;
use Chalk::Grammar::Chalk::Rule::ExpressionList;
use Chalk::Grammar::Chalk::Rule::Expression;
use Chalk::Grammar::Chalk::Rule::Attribute;
use Chalk::Grammar::Chalk::Rule::AttributeList;
use Chalk::Grammar::Chalk::Rule::Number;

# Reset registry for clean tests
Chalk::Grammar::Chalk::TypeRegistry->instance()->reset();

# Test 1: Class type should have param_fields accessor
{
    my $class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'TestClass',
        fields => { '$x' => undef },
        param_fields => [
            { name => '$x', required => 1 },
        ],
    );

    ok($class->can('param_fields'), 'Class type has param_fields method');
    my $params = $class->param_fields;
    is(ref($params), 'ARRAY', 'param_fields returns arrayref');
    is(scalar(@$params), 1, 'param_fields has 1 entry');
    is($params->[0]{name}, '$x', 'param field name is $x');
    is($params->[0]{required}, 1, 'param field is required');
}

# Test 2: Optional param field with default
{
    my $class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Counter',
        fields => { '$count' => undef },
        param_fields => [
            { name => '$count', required => 0, default => 'some_default_node' },
        ],
    );

    my $params = $class->param_fields;
    is($params->[0]{required}, 0, 'param field with default is not required');
    ok(exists $params->[0]{default}, 'param field has default entry');
}

# Test 3: Mixed required and optional params
{
    my $class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => { '$x' => undef, '$y' => undef },
        param_fields => [
            { name => '$x', required => 1 },
            { name => '$y', required => 0, default => 'zero_node' },
        ],
    );

    my $params = $class->param_fields;
    is(scalar(@$params), 2, 'Point has 2 param fields');

    my ($x_param) = grep { $_->{name} eq '$x' } @$params;
    my ($y_param) = grep { $_->{name} eq '$y' } @$params;

    ok($x_param->{required}, '$x is required');
    ok(!$y_param->{required}, '$y is optional');
}

# Test 4: Field without :param should not appear in param_fields
{
    my $class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Internal',
        fields => { '$public' => undef, '$internal' => undef },
        param_fields => [
            { name => '$public', required => 1 },
            # $internal has no :param, so it's not in param_fields
        ],
    );

    my $params = $class->param_fields;
    is(scalar(@$params), 1, 'only :param fields in param_fields');
    is($params->[0]{name}, '$public', 'only $public is a param');
}

# Test 5: Parse actual class and verify :param extraction
# This tests ClassDeclaration's ability to extract :param from source
{
    # Reset registry before parsing
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Load grammar from BNF file
    my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
    open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
    my $bnf_content = do { local $/; <$grammar_fh> };
    close $grammar_fh;
    my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

    # Create parser with Semantic semiring
    my $semiring = Chalk::Semiring::Semantic->new(
        env => {},
        grammar => $chalk_grammar
    );
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => $semiring
    );

    my $source = q{
        class Point {
            field $x :param :reader;
            field $y :param = 0;
            field $internal;
        }
    };

    # Parse and register the class
    my $ast = $parser->parse_string($source);
    ok(defined $ast, 'parsed ClassDeclaration successfully');

    # Get the registered class
    ok($registry->has_class('Point'), 'Point class is registered');

    my $point_class = $registry->lookup('Point');
    ok($point_class->is_complete, 'Point class is complete');

    # Check param_fields extraction
    my $params = $point_class->param_fields;
    is(ref($params), 'ARRAY', 'param_fields is arrayref from parsed class');

    # Should have 2 :param fields ($x required, $y optional), not $internal
    is(scalar(@$params), 2, 'parsed class has 2 :param fields');

    my ($x_param) = grep { $_->{name} eq '$x' } @$params;
    my ($y_param) = grep { $_->{name} eq '$y' } @$params;

    ok(defined $x_param, '$x was extracted as :param');
    ok(defined $y_param, '$y was extracted as :param');

    ok($x_param->{required}, '$x is required (no default)');
    ok(!$y_param->{required}, '$y is optional (has default)');
}

done_testing();
