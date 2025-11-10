# ABOUTME: Tests for type tracking in the semantic semiring
# ABOUTME: Validates that type information flows through parsing contexts

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Scalar;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::EvalContext;
use Chalk::Semiring::Semantic;
use Chalk::Grammar;

subtest 'EvalContext can store type information' => sub {
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();

    my $ctx = Chalk::EvalContext->new(
        focus => 42,
        children => [],
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef,
        type => $int_type
    );

    ok(defined($ctx->type), 'Context has type field');
    isa_ok($ctx->type, 'Chalk::Grammar::Chalk::Type::Int', 'Type is Int');
    ok($ctx->type->is_subtype_of(Chalk::Grammar::Chalk::Type::Num->new()),
       'Int type is subtype of Num');
};

subtest 'Semantic semiring has type_env field' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => { '$x' => Chalk::Grammar::Chalk::Type::Int->new() }
    );

    ok(defined($semiring->type_env), 'Semiring has type_env field');
    is(ref($semiring->type_env), 'HASH', 'type_env is a hash');
    isa_ok($semiring->type_env->{'$x'}, 'Chalk::Grammar::Chalk::Type::Int',
           'type_env can store variable types');
};

subtest 'Type inference from literal rules' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    # Test integer literal
    my $int_rule = Chalk::GrammarRule->new(
        lhs => 'Number',
        rhs => ['%INTEGER%']
    );
    my $int_type = $semiring->infer_type_from_rule($int_rule);
    isa_ok($int_type, 'Chalk::Grammar::Chalk::Type::Int', 'INTEGER infers Int type');

    # Test float literal
    my $float_rule = Chalk::GrammarRule->new(
        lhs => 'Number',
        rhs => ['%FLOAT%']
    );
    my $float_type = $semiring->infer_type_from_rule($float_rule);
    isa_ok($float_type, 'Chalk::Grammar::Chalk::Type::Num', 'FLOAT infers Num type');

    # Test string literal
    my $str_rule = Chalk::GrammarRule->new(
        lhs => 'String',
        rhs => ['%SINGLE_QUOTED_STRING%']
    );
    my $str_type = $semiring->infer_type_from_rule($str_rule);
    isa_ok($str_type, 'Chalk::Grammar::Chalk::Type::Str', 'String literal infers Str type');
};

subtest 'Type inference from variable sigils' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    # Test scalar variable ($x)
    my $scalar_rule = Chalk::GrammarRule->new(
        lhs => 'ScalarVariable',
        rhs => ['$', 'Identifier']
    );
    my $scalar_type = $semiring->infer_type_from_rule($scalar_rule);
    isa_ok($scalar_type, 'Chalk::Grammar::Chalk::Type::Scalar',
           'Scalar variable infers Scalar type');

    # Test array variable (@arr)
    my $array_rule = Chalk::GrammarRule->new(
        lhs => 'ArrayVariable',
        rhs => ['@', 'Identifier']
    );
    my $array_type = $semiring->infer_type_from_rule($array_rule);
    isa_ok($array_type, 'Chalk::Grammar::Chalk::Type::Array',
           'Array variable infers Array type');
    ok(defined($array_type->element_type), 'Array has element_type');
    isa_ok($array_type->element_type, 'Chalk::Grammar::Chalk::Type::Any',
           'Array element_type defaults to Any');

    # Test hash variable (%hash)
    my $hash_rule = Chalk::GrammarRule->new(
        lhs => 'HashVariable',
        rhs => ['%', 'Identifier']
    );
    my $hash_type = $semiring->infer_type_from_rule($hash_rule);
    isa_ok($hash_type, 'Chalk::Grammar::Chalk::Type::Hash',
           'Hash variable infers Hash type');
    ok(defined($hash_type->value_type), 'Hash has value_type');
    isa_ok($hash_type->value_type, 'Chalk::Grammar::Chalk::Type::Any',
           'Hash value_type defaults to Any');
};

subtest 'Type inference from operations' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    # Test addition operation
    my $add_rule = Chalk::GrammarRule->new(
        lhs => 'Addition',
        rhs => ['Term', '+', 'Term']
    );
    my $add_type = $semiring->infer_type_from_rule($add_rule);
    isa_ok($add_type, 'Chalk::Grammar::Chalk::Type::Num',
           'Addition operation infers Num type');

    # Test string concatenation
    my $concat_rule = Chalk::GrammarRule->new(
        lhs => 'Concatenation',
        rhs => ['StringExpression', '.', 'StringExpression']
    );
    my $concat_type = $semiring->infer_type_from_rule($concat_rule);
    isa_ok($concat_type, 'Chalk::Grammar::Chalk::Type::Str',
           'Concatenation operation infers Str type');

    # Test range operator
    my $range_rule = Chalk::GrammarRule->new(
        lhs => 'Range',
        rhs => ['Expression', '..', 'Expression']
    );
    my $range_type = $semiring->infer_type_from_rule($range_rule);
    isa_ok($range_type, 'Chalk::Grammar::Chalk::Type::List',
           'Range operation infers List type');
};

subtest 'Default type inference' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    # Unknown rule should default to Any
    my $unknown_rule = Chalk::GrammarRule->new(
        lhs => 'UnknownConstruct',
        rhs => ['something', 'else']
    );
    my $unknown_type = $semiring->infer_type_from_rule($unknown_rule);
    isa_ok($unknown_type, 'Chalk::Grammar::Chalk::Type::Any',
           'Unknown constructs infer Any type');
};

subtest 'Type tracking in init_element_from_rule' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    my $int_rule = Chalk::GrammarRule->new(
        lhs => 'Number',
        rhs => ['%INTEGER%']
    );

    my $elem = $semiring->init_element_from_rule($int_rule, 0, 2);

    ok(defined($elem), 'Element created from rule');
    ok(defined($elem->context), 'Element has context');
    ok(defined($elem->context->type), 'Context has type');
    isa_ok($elem->context->type, 'Chalk::Grammar::Chalk::Type::Int',
           'Integer literal element has Int type');
};

subtest 'Type propagation in comonad operations' => sub {
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();

    my $ctx = Chalk::EvalContext->new(
        focus => 42,
        children => [],
        start_pos => 0,
        end_pos => 2,
        env => {},
        grammar => undef,
        rule => undef,
        type => $int_type
    );

    # Test fmap preserves type
    my $mapped = $ctx->fmap(sub { $_[0] * 2 });
    ok(defined($mapped->type), 'fmap preserves type field');
    isa_ok($mapped->type, 'Chalk::Grammar::Chalk::Type::Int', 'fmap preserves Int type');

    # Test extend preserves type
    my $extended = $ctx->extend(sub { 100 });
    ok(defined($extended->type), 'extend preserves type field');
    isa_ok($extended->type, 'Chalk::Grammar::Chalk::Type::Int', 'extend preserves Int type');

    # Test duplicate preserves type
    my $duplicated = $ctx->duplicate();
    ok(defined($duplicated->type), 'duplicate preserves type field');
    isa_ok($duplicated->type, 'Chalk::Grammar::Chalk::Type::Int', 'duplicate preserves Int type');
};

done_testing();
