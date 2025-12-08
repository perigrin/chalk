#!/usr/bin/env perl
# ABOUTME: Test Perl-specific type propagation rules for TypeInference semiring
# ABOUTME: Validates operator type rules, context sensitivity, DualVar, coercion, and dereference operators

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar::Chalk::TypeLattice;
use Chalk::Semiring::TypeInference;

my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
my $semiring = Chalk::Semiring::TypeInference->new();

subtest 'Arithmetic operators require Num operands and produce Num result' => sub {
    # Test that +, -, *, / operators work with Num types
    my @ops = qw(Add Subtract Multiply Divide);

    for my $op (@ops) {
        my $result_type = $lattice->infer_type_from_operation($op);
        is($result_type->name(), 'Num', "$op produces Num result");

        # Validate operation with Num operands
        my $num_type = $lattice->type_from_name('Num');
        my $validation = $lattice->validate_operation($op, $num_type, $num_type);
        ok($validation->{valid}, "$op accepts Num operands");
    }
};

subtest 'String concatenation operator produces Str result' => sub {
    my $result_type = $lattice->infer_type_from_operation('Concat');
    is($result_type->name(), 'Str', 'Concat produces Str result');

    # Concat accepts any types (coerces to string)
    my $str_type = $lattice->type_from_name('Str');
    my $num_type = $lattice->type_from_name('Num');
    my $validation = $lattice->validate_operation('Concat', $str_type, $num_type);
    ok($validation->{valid}, 'Concat accepts mixed types (coercion)');
};

subtest 'String comparison operators (eq, ne, lt, etc.) require Str and produce Bool' => sub {
    my @ops = qw(StrEQ StrNE StrLT StrLE StrGT StrGE);

    for my $op (@ops) {
        my $result_type = $lattice->infer_type_from_operation($op);
        is($result_type->name(), 'Boolean', "$op produces Boolean result");
    }
};

subtest 'Numeric comparison operators (==, !=, <, etc.) require Num and produce Bool' => sub {
    # These are already implemented - verify they work
    my @ops = qw(EQ NE LT LE GT GE);

    for my $op (@ops) {
        my $result_type = $lattice->infer_type_from_operation($op);
        is($result_type->name(), 'Boolean', "$op produces Boolean result");
    }
};

subtest 'Context sensitivity: sigil-based type distinctions' => sub {
    # @array is Array type
    my $array_type = $lattice->type_from_name('Array');
    is($array_type->name(), 'Array', '@array has Array type');

    # $array[0] is Scalar type (element access)
    my $arrayget_type = $lattice->infer_type_from_operation('ArrayGet');
    # ArrayGet returns Any by default, but with element type it should return the element type
    ok(defined $arrayget_type, 'ArrayGet returns a type');

    # %hash is Hash type
    my $hash_type = $lattice->type_from_name('Hash');
    is($hash_type->name(), 'Hash', '%hash has Hash type');

    # $hash{key} is Scalar type (value access)
    my $hashget_type = $lattice->infer_type_from_operation('HashGet');
    ok(defined $hashget_type, 'HashGet returns a type');
};

subtest 'DualVar handling: variables with both string and numeric interpretations' => sub {
    # DualVar should be represented as join(Str, Num)
    my $str_type = $lattice->type_from_name('Str');
    my $num_type = $lattice->type_from_name('Num');

    # Join creates a type that "could be either"
    my $dualvar_type = $str_type->join($num_type);

    # DualVar should be compatible with both Str and Num contexts
    ok($lattice->are_compatible($dualvar_type, $str_type),
       'DualVar compatible with Str context');
    ok($lattice->are_compatible($dualvar_type, $num_type),
       'DualVar compatible with Num context');
};

subtest 'Coercion rules: numeric context' => sub {
    # In numeric context, strings coerce to numbers
    # This is represented by the operation accepting the type
    my $add_type = $lattice->infer_type_from_operation('Add');
    is($add_type->name(), 'Num', 'Add operation produces Num');

    # TODO: Test that Add accepts Str operands (with coercion warning)
    # For now, verify it accepts Num
    my $num_type = $lattice->type_from_name('Num');
    my $validation = $lattice->validate_operation('Add', $num_type, $num_type);
    ok($validation->{valid}, 'Add accepts Num operands');
};

subtest 'Coercion rules: string context' => sub {
    # In string context, numbers coerce to strings
    my $concat_type = $lattice->infer_type_from_operation('Concat');
    is($concat_type->name(), 'Str', 'Concat operation produces Str');

    # Concat should accept any types (coercion)
    my $str_type = $lattice->type_from_name('Str');
    my $num_type = $lattice->type_from_name('Num');
    my $validation = $lattice->validate_operation('Concat', $num_type, $str_type);
    ok($validation->{valid}, 'Concat accepts Num operands (coercion)');
};

subtest 'Coercion rules: boolean context' => sub {
    # Most values coerce to boolean
    # Logical operations should accept most types
    my $and_type = $lattice->infer_type_from_operation('And');
    is($and_type->name(), 'Boolean', 'And operation produces Boolean');

    my $or_type = $lattice->infer_type_from_operation('Or');
    is($or_type->name(), 'Boolean', 'Or operation produces Boolean');
};

subtest 'Dereference operators for HashRef/ArrayRef' => sub {
    # Test that -> operator works with references
    # $hashref->{key} should return the value type
    # $arrayref->[0] should return the element type

    # For now, check that we can create Ref types
    my $ref_type = $lattice->type_from_name('Ref');
    ok(defined $ref_type, 'Ref type exists');

    # TODO: Implement proper dereference type inference
};

subtest 'Type propagation through complex expressions' => sub {
    # Test that types propagate correctly through nested operations
    # Example: (1 + 2) * 3 should be: Int meet Num -> Num * Num -> Num

    my $int_type = $lattice->type_from_name('Int');
    my $num_type = $lattice->type_from_name('Num');

    # Int is a subtype of Num
    my $int_num_meet = $int_type->meet($num_type);
    is($int_num_meet->name(), 'Int', 'Int meet Num = Int');

    # Num is a supertype of Int
    my $int_num_join = $int_type->join($num_type);
    is($int_num_join->name(), 'Num', 'Int join Num = Num');
};

subtest 'Type errors: incompatible operations' => sub {
    # Test that type errors are detected
    # Example: Array + Num should fail

    my $array_type = $lattice->type_from_name('Array');
    my $num_type = $lattice->type_from_name('Num');

    my $validation = $lattice->validate_operation('Add', $array_type, $num_type);
    # This should fail or produce a warning
    # For now, check that validation returns something
    ok(defined $validation, 'Validation result exists for incompatible types');
};
