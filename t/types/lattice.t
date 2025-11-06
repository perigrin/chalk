# ABOUTME: Tests for Chalk type lattice structure and subtyping relationships
# ABOUTME: Validates the type hierarchy defined in the latent type system specification

use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

# Test type lattice structure per issue #74
# Based on: https://gist.github.com/perigrin/c4780a7511ba1421e49a4a8b385aaa3d

subtest 'Universal types' => sub {
    use_ok('Chalk::Grammar::Chalk::Type::Any');
    use_ok('Chalk::Grammar::Chalk::Type::None');

    my $any = Chalk::Grammar::Chalk::Type::Any->new();
    my $none = Chalk::Grammar::Chalk::Type::None->new();

    # Any is top type - all types are subtypes of Any
    isa_ok($any, 'Chalk::Type');
    ok($any->is_top(), 'Any is top type');

    # None is bottom type - is subtype of all types
    isa_ok($none, 'Chalk::Type');
    ok($none->is_bottom(), 'None is bottom type');
    ok($none->is_subtype_of($any), 'None <: Any');
};

subtest 'Scalar hierarchy' => sub {
    use_ok('Chalk::Grammar::Chalk::Type::Scalar');
    use_ok('Chalk::Grammar::Chalk::Type::Undef');
    use_ok('Chalk::Grammar::Chalk::Type::Boolean');
    use_ok('Chalk::Grammar::Chalk::Type::Str');
    use_ok('Chalk::Grammar::Chalk::Type::Num');
    use_ok('Chalk::Grammar::Chalk::Type::Int');

    my $scalar = Chalk::Grammar::Chalk::Type::Scalar->new();
    my $undef = Chalk::Grammar::Chalk::Type::Undef->new();
    my $boolean = Chalk::Grammar::Chalk::Type::Boolean->new();
    my $str = Chalk::Grammar::Chalk::Type::Str->new();
    my $num = Chalk::Grammar::Chalk::Type::Num->new();
    my $int = Chalk::Grammar::Chalk::Type::Int->new();
    my $any = Chalk::Grammar::Chalk::Type::Any->new();

    # Primary Scalar Chain: Int <: Num <: Str <: Scalar <: Any
    ok($int->is_subtype_of($num), 'Int <: Num');
    ok($num->is_subtype_of($str), 'Num <: Str (round-trip preservation)');
    ok($str->is_subtype_of($scalar), 'Str <: Scalar');
    ok($scalar->is_subtype_of($any), 'Scalar <: Any');

    # Transitive relationships
    ok($int->is_subtype_of($str), 'Int <: Str (transitive)');
    ok($int->is_subtype_of($scalar), 'Int <: Scalar (transitive)');
    ok($int->is_subtype_of($any), 'Int <: Any (transitive)');

    # Other Scalar subtypes
    ok($undef->is_subtype_of($scalar), 'Undef <: Scalar');
    ok($undef->is_subtype_of($any), 'Undef <: Any');
    ok($boolean->is_subtype_of($scalar), 'Boolean <: Scalar');
    ok($boolean->is_subtype_of($any), 'Boolean <: Any');

    # Negative cases - not subtypes
    ok(!$str->is_subtype_of($num), 'NOT: Str <: Num');
    ok(!$num->is_subtype_of($int), 'NOT: Num <: Int');
    ok(!$scalar->is_subtype_of($str), 'NOT: Scalar <: Str');
};

subtest 'Reference hierarchy' => sub {
    use_ok('Chalk::Grammar::Chalk::Type::Ref');
    use_ok('Chalk::Grammar::Chalk::Type::Object');
    use_ok('Chalk::Grammar::Chalk::Type::ScalarRef');
    use_ok('Chalk::Grammar::Chalk::Type::ArrayRef');
    use_ok('Chalk::Grammar::Chalk::Type::HashRef');
    use_ok('Chalk::Grammar::Chalk::Type::CodeRef');

    my $ref = Chalk::Grammar::Chalk::Type::Ref->new();
    my $object = Chalk::Grammar::Chalk::Type::Object->new();
    my $scalarref = Chalk::Grammar::Chalk::Type::ScalarRef->new();
    my $arrayref = Chalk::Grammar::Chalk::Type::ArrayRef->new();
    my $hashref = Chalk::Grammar::Chalk::Type::HashRef->new();
    my $coderef = Chalk::Grammar::Chalk::Type::CodeRef->new();
    my $scalar = Chalk::Grammar::Chalk::Type::Scalar->new();
    my $any = Chalk::Grammar::Chalk::Type::Any->new();

    # All Refs are Scalars: Ref <: Scalar
    ok($ref->is_subtype_of($scalar), 'Ref <: Scalar');
    ok($ref->is_subtype_of($any), 'Ref <: Any');

    # Specific Refs are Refs
    ok($object->is_subtype_of($ref), 'Object <: Ref');
    ok($scalarref->is_subtype_of($ref), 'ScalarRef <: Ref');
    ok($arrayref->is_subtype_of($ref), 'ArrayRef <: Ref');
    ok($hashref->is_subtype_of($ref), 'HashRef <: Ref');
    ok($coderef->is_subtype_of($ref), 'CodeRef <: Ref');

    # Transitive: specific Refs are Scalars
    ok($object->is_subtype_of($scalar), 'Object <: Scalar (transitive)');
    ok($arrayref->is_subtype_of($scalar), 'ArrayRef <: Scalar (transitive)');
};

subtest 'List hierarchy' => sub {
    use_ok('Chalk::Grammar::Chalk::Type::List');
    use_ok('Chalk::Grammar::Chalk::Type::Array');
    use_ok('Chalk::Grammar::Chalk::Type::Hash');

    my $list = Chalk::Grammar::Chalk::Type::List->new();
    my $array = Chalk::Grammar::Chalk::Type::Array->new(element_type => Chalk::Grammar::Chalk::Type::Any->new());
    my $hash = Chalk::Grammar::Chalk::Type::Hash->new(value_type => Chalk::Grammar::Chalk::Type::Any->new());
    my $any = Chalk::Grammar::Chalk::Type::Any->new();

    # Array and Hash are subtypes of List (ephemeral type)
    ok($array->is_subtype_of($list), 'Array <: List');
    ok($hash->is_subtype_of($list), 'Hash <: List');
    ok($list->is_subtype_of($any), 'List <: Any');

    # Array and Hash are direct subtypes of List, transitive to Any
    ok($array->is_subtype_of($any), 'Array <: Any (transitive)');
    ok($hash->is_subtype_of($any), 'Hash <: Any (transitive)');
};

subtest 'Code type' => sub {
    use_ok('Chalk::Grammar::Chalk::Type::Code');

    my $code = Chalk::Grammar::Chalk::Type::Code->new();
    my $any = Chalk::Grammar::Chalk::Type::Any->new();

    # Code is direct subtype of Any (not Scalar)
    ok($code->is_subtype_of($any), 'Code <: Any');
    ok(!$code->is_subtype_of(Chalk::Grammar::Chalk::Type::Scalar->new()), 'NOT: Code <: Scalar');
};

subtest 'Type names' => sub {
    # Each type should have a canonical name
    is(Chalk::Grammar::Chalk::Type::Any->new()->name(), 'Any', 'Any type name');
    is(Chalk::Grammar::Chalk::Type::None->new()->name(), 'None', 'None type name');
    is(Chalk::Grammar::Chalk::Type::Scalar->new()->name(), 'Scalar', 'Scalar type name');
    is(Chalk::Grammar::Chalk::Type::Int->new()->name(), 'Int', 'Int type name');
    is(Chalk::Grammar::Chalk::Type::Num->new()->name(), 'Num', 'Num type name');
    is(Chalk::Grammar::Chalk::Type::Str->new()->name(), 'Str', 'Str type name');
    is(Chalk::Grammar::Chalk::Type::Boolean->new()->name(), 'Boolean', 'Boolean type name');
    is(Chalk::Grammar::Chalk::Type::Undef->new()->name(), 'Undef', 'Undef type name');
    is(Chalk::Grammar::Chalk::Type::Ref->new()->name(), 'Ref', 'Ref type name');
    is(Chalk::Grammar::Chalk::Type::List->new()->name(), 'List', 'List type name');
    is(Chalk::Grammar::Chalk::Type::Code->new()->name(), 'Code', 'Code type name');
};

subtest 'Parameterized types' => sub {
    # Array and Hash have type parameters
    my $int_array = Chalk::Grammar::Chalk::Type::Array->new(
        element_type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    my $str_array = Chalk::Grammar::Chalk::Type::Array->new(
        element_type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    ok($int_array->element_type()->isa('Chalk::Grammar::Chalk::Type::Int'), 'Array[Int] has Int element type');
    ok($str_array->element_type()->isa('Chalk::Grammar::Chalk::Type::Str'), 'Array[Str] has Str element type');

    my $int_hash = Chalk::Grammar::Chalk::Type::Hash->new(
        value_type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    ok($int_hash->value_type()->isa('Chalk::Grammar::Chalk::Type::Int'), 'Hash[Int] has Int value type');
};

done_testing();
