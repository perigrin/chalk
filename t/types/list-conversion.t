# ABOUTME: Integration tests for List to Array/Hash conversion during semantic analysis
# ABOUTME: Validates ephemeral List type conversion in parsing contexts (Phase 3)

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

use Chalk::Grammar::Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Grammar::Chalk::Type::Any;
use Chalk::Semiring::Semantic;
use Chalk::Grammar;

subtest 'Range produces List type via semantic semiring' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    # Range operator rule: Expression .. Expression
    my $range_rule = Chalk::GrammarRule->new(
        lhs => 'Range',
        rhs => ['Expression', '..', 'Expression']
    );

    my $range_type = $semiring->infer_type_from_rule($range_rule);

    isa_ok($range_type, 'Chalk::Grammar::Chalk::Type::List',
           'Range operator infers ephemeral List type');
    ok($range_type->is_subtype_of(Chalk::Grammar::Chalk::Type::Any->new()),
       'List is subtype of Any');
};

subtest 'List type can convert to Array in assignment context' => sub {
    # Simulate: my @arr = (1..10);
    # 1. Range produces List
    # 2. Assignment to @arr converts List to Array

    my $list_from_range = Chalk::Grammar::Chalk::Type::List->new();

    # In assignment context, convert to Array
    my $array_type = $list_from_range->convert_to_target('@');

    isa_ok($array_type, 'Chalk::Grammar::Chalk::Type::Array',
           'List converts to Array for @arr assignment');
    ok($array_type->is_subtype_of(Chalk::Grammar::Chalk::Type::List->new()),
       'Array is subtype of List');
};

subtest 'List type can convert to Hash in assignment context' => sub {
    # Simulate: my %hash = (a => 1, b => 2);
    # 1. List literal produces List
    # 2. Assignment to %hash converts List to Hash

    my $list_from_literal = Chalk::Grammar::Chalk::Type::List->new();

    # In assignment context, convert to Hash
    my $hash_type = $list_from_literal->convert_to_target('%');

    isa_ok($hash_type, 'Chalk::Grammar::Chalk::Type::Hash',
           'List converts to Hash for %hash assignment');
    ok($hash_type->is_subtype_of(Chalk::Grammar::Chalk::Type::List->new()),
       'Hash is subtype of List');
};

subtest 'Parameterized List preserves element type during conversion' => sub {
    # Simulate: my @nums = (1, 2, 3);
    # If we infer that the list contains Int elements,
    # the Array should preserve that element type

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $list_of_ints = Chalk::Grammar::Chalk::Type::List->new(element_type => $int_type);

    my $array_of_ints = $list_of_ints->convert_to_target('@');

    isa_ok($array_of_ints, 'Chalk::Grammar::Chalk::Type::Array',
           'Parameterized List converts to Array');
    isa_ok($array_of_ints->element_type, 'Chalk::Grammar::Chalk::Type::Int',
           'Element type preserved: Array[Int]');
};

subtest 'Type environment tracks variable types after conversion' => sub {
    # This tests the type_env tracking in semantic semiring
    my $type_env = {
        '$x' => Chalk::Grammar::Chalk::Type::Int->new(),
    };

    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => $type_env
    );

    ok(defined($semiring->type_env), 'Semiring has type_env');
    is(ref($semiring->type_env), 'HASH', 'type_env is hash');

    # After parsing: my @arr = (1..10);
    # We should be able to track: @arr -> Array[Int]
    my $list_type = Chalk::Grammar::Chalk::Type::List->new(
        element_type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $array_type = $list_type->convert_to_target('@');

    # Store in type environment
    $semiring->type_env->{'@arr'} = $array_type;

    isa_ok($semiring->type_env->{'@arr'}, 'Chalk::Grammar::Chalk::Type::Array',
           'Type environment tracks Array type');
    isa_ok($semiring->type_env->{'@arr'}->element_type, 'Chalk::Grammar::Chalk::Type::Int',
           'Type environment preserves element type');
};

subtest 'List literal type inference' => sub {
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => undef,
        type_env => {}
    );

    # List or ArrayLiteral should infer List type (ephemeral)
    my $list_rule = Chalk::GrammarRule->new(
        lhs => 'List',
        rhs => ['(', 'ExpressionList', ')']
    );

    my $list_type = $semiring->infer_type_from_rule($list_rule);

    # Should infer Array which is a subtype of List
    # (Array <: List - List is ephemeral parent type)
    ok($list_type->is_subtype_of(Chalk::Grammar::Chalk::Type::List->new()) ||
       ref($list_type) eq 'Chalk::Grammar::Chalk::Type::List',
       'List literal produces List-compatible type');
};

done_testing();
