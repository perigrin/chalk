#!/usr/bin/env perl
# ABOUTME: Tests for Grammar→IR type conversion
# ABOUTME: Issue #478 - Ensure Grammar types don't leak into IR/codegen phases

use 5.42.0;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Type::Convert;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Bool;
use Chalk::IR::Type::String;
use Chalk::IR::Type::Array;
use Chalk::IR::Type::Hash;
use Chalk::IR::Type::Code;
use Chalk::IR::Type::Ref;
use Chalk::IR::Type::Object;
use Chalk::IR::Type::Undef;
use Chalk::IR::Type::Scalar;

use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Boolean;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::Grammar::Chalk::Type::None;

subtest 'grammar_to_ir converts numeric types' => sub {
    my $int_grammar = Chalk::Grammar::Chalk::Type::Int->new();
    my $int_ir = Chalk::IR::Type::Convert->grammar_to_ir($int_grammar);
    isa_ok $int_ir, ['Chalk::IR::Type::Integer'], 'Int → Integer';

    my $num_grammar = Chalk::Grammar::Chalk::Type::Num->new();
    my $num_ir = Chalk::IR::Type::Convert->grammar_to_ir($num_grammar);
    isa_ok $num_ir, ['Chalk::IR::Type::Float'], 'Num → Float';

    my $bool_grammar = Chalk::Grammar::Chalk::Type::Boolean->new();
    my $bool_ir = Chalk::IR::Type::Convert->grammar_to_ir($bool_grammar);
    isa_ok $bool_ir, ['Chalk::IR::Type::Bool'], 'Boolean → Bool';
};

subtest 'grammar_to_ir converts string type' => sub {
    my $str_grammar = Chalk::Grammar::Chalk::Type::Str->new();
    my $str_ir = Chalk::IR::Type::Convert->grammar_to_ir($str_grammar);
    isa_ok $str_ir, ['Chalk::IR::Type::String'], 'Str → String';
};

subtest 'grammar_to_ir converts collection types' => sub {
    # Grammar Array requires element_type param
    my $int_grammar = Chalk::Grammar::Chalk::Type::Int->new();
    my $array_grammar = Chalk::Grammar::Chalk::Type::Array->new(element_type => $int_grammar);
    my $array_ir = Chalk::IR::Type::Convert->grammar_to_ir($array_grammar);
    isa_ok $array_ir, ['Chalk::IR::Type::Array'], 'Array -> Array';

    # Grammar Hash requires value_type param
    my $hash_grammar = Chalk::Grammar::Chalk::Type::Hash->new(value_type => $int_grammar);
    my $hash_ir = Chalk::IR::Type::Convert->grammar_to_ir($hash_grammar);
    isa_ok $hash_ir, ['Chalk::IR::Type::Hash'], 'Hash -> Hash';
};

subtest 'grammar_to_ir converts special types' => sub {
    my $any_grammar = Chalk::Grammar::Chalk::Type::Any->new();
    my $any_ir = Chalk::IR::Type::Convert->grammar_to_ir($any_grammar);
    isa_ok $any_ir, ['Chalk::IR::Type::Top'], 'Any → Top';

    my $none_grammar = Chalk::Grammar::Chalk::Type::None->new();
    my $none_ir = Chalk::IR::Type::Convert->grammar_to_ir($none_grammar);
    isa_ok $none_ir, ['Chalk::IR::Type::Bottom'], 'None → Bottom';
};

subtest 'is_grammar_type correctly identifies Grammar types' => sub {
    my $grammar_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $ir_type = Chalk::IR::Type::Integer->TOP();

    ok Chalk::IR::Type::Convert->is_grammar_type($grammar_type),
        'Grammar type is identified';
    ok !Chalk::IR::Type::Convert->is_grammar_type($ir_type),
        'IR type is not a Grammar type';
    ok !Chalk::IR::Type::Convert->is_grammar_type(undef),
        'undef is not a Grammar type';
};

subtest 'is_ir_type correctly identifies IR types' => sub {
    my $grammar_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $ir_type = Chalk::IR::Type::Integer->TOP();

    ok Chalk::IR::Type::Convert->is_ir_type($ir_type),
        'IR type is identified';
    ok !Chalk::IR::Type::Convert->is_ir_type($grammar_type),
        'Grammar type is not an IR type';
    ok !Chalk::IR::Type::Convert->is_ir_type(undef),
        'undef is not an IR type';
};

subtest 'ensure_ir_type passes through IR types unchanged' => sub {
    my $ir_int = Chalk::IR::Type::Integer->constant(42);
    my $result = Chalk::IR::Type::Convert->ensure_ir_type($ir_int);

    is refaddr($result), refaddr($ir_int),
        'IR type passes through unchanged';
};

subtest 'ensure_ir_type converts Grammar types' => sub {
    my $grammar_int = Chalk::Grammar::Chalk::Type::Int->new();
    my $result = Chalk::IR::Type::Convert->ensure_ir_type($grammar_int);

    isa_ok $result, ['Chalk::IR::Type::Integer'],
        'Grammar type is converted to IR type';
    ok !Chalk::IR::Type::Convert->is_grammar_type($result),
        'Result is not a Grammar type';
};

subtest 'ensure_ir_type handles undef' => sub {
    my $result = Chalk::IR::Type::Convert->ensure_ir_type(undef);

    isa_ok $result, ['Chalk::IR::Type::Top'],
        'undef converts to Top';
};

subtest 'new IR types exist and work' => sub {
    # Test String
    my $str = Chalk::IR::Type::String->TOP();
    ok $str->is_top, 'String TOP is top';

    my $str_const = Chalk::IR::Type::String->constant("hello");
    ok $str_const->is_constant, 'String constant is constant';
    is $str_const->value, "hello", 'String constant has correct value';

    # Test Array
    my $arr = Chalk::IR::Type::Array->TOP();
    ok $arr->is_top, 'Array TOP is top';

    # Test Hash
    my $hash = Chalk::IR::Type::Hash->TOP();
    ok $hash->is_top, 'Hash TOP is top';

    # Test Code
    my $code = Chalk::IR::Type::Code->TOP();
    ok $code->is_top, 'Code TOP is top';

    # Test Ref
    my $ref = Chalk::IR::Type::Ref->TOP();
    ok $ref->is_top, 'Ref TOP is top';

    # Test Object
    my $obj = Chalk::IR::Type::Object->TOP();
    ok $obj->is_top, 'Object TOP is top';

    my $point = Chalk::IR::Type::Object->of('Point');
    is $point->class_name, 'Point', 'Object::of sets class name';

    # Test Undef
    my $undef = Chalk::IR::Type::Undef->TOP();
    ok $undef->is_constant, 'Undef is constant (the undef value)';

    # Test Scalar
    my $scalar = Chalk::IR::Type::Scalar->TOP();
    ok $scalar->is_top, 'Scalar TOP is top';
};
