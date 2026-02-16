# ABOUTME: Unit tests for Chalk::Grammar::Perl::TypeLibrary type hierarchy and signatures.
# ABOUTME: Tests is_subtype, builtin lookups, operator signatures, and tag-to-type mapping.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# ========================================================================
# Module loads
# ========================================================================

use_ok('Chalk::Grammar::Perl::TypeLibrary');

# ========================================================================
# Type hierarchy - is_subtype
# ========================================================================

# Direct parent relationships
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Num'),
    'Int is subtype of Num');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Num', 'Str'),
    'Num is subtype of Str');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Str', 'Scalar'),
    'Str is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'Any'),
    'Scalar is subtype of Any');

# Transitive relationships
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Scalar'),
    'Int is subtype of Scalar (transitive)');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Any'),
    'Int is subtype of Any (transitive)');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Num', 'Any'),
    'Num is subtype of Any (transitive)');

# Self is subtype of self
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Int'),
    'Int is subtype of Int (reflexive)');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Any', 'Any'),
    'Any is subtype of Any (reflexive)');

# Not subtypes
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Num', 'Int'),
    'Num is NOT subtype of Int');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'Str'),
    'Scalar is NOT subtype of Str');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Any', 'Scalar'),
    'Any is NOT subtype of Scalar');

# Collection types
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Array', 'List'),
    'Array is subtype of List');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Hash', 'List'),
    'Hash is subtype of List');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('List', 'Any'),
    'List is subtype of Any');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Array', 'Any'),
    'Array is subtype of Any (transitive)');

# Ref hierarchy
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Ref', 'Scalar'),
    'Ref is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('ArrayRef', 'Ref'),
    'ArrayRef is subtype of Ref');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('HashRef', 'Ref'),
    'HashRef is subtype of Ref');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('CodeRef', 'Ref'),
    'CodeRef is subtype of Ref');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Object', 'Ref'),
    'Object is subtype of Ref');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('ScalarRef', 'Ref'),
    'ScalarRef is subtype of Ref');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('GlobRef', 'Ref'),
    'GlobRef is subtype of Ref');

# None is subtype of everything
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Any'),
    'None is subtype of Any');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Scalar'),
    'None is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Int'),
    'None is subtype of Int');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Array'),
    'None is subtype of Array');

# Bool, Undef, Regex
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Bool', 'Scalar'),
    'Bool is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Undef', 'Scalar'),
    'Undef is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Regex', 'Scalar'),
    'Regex is subtype of Scalar');

# Code
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Code', 'Any'),
    'Code is subtype of Any');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Code', 'Scalar'),
    'Code is NOT subtype of Scalar');

# Cross-branch: Array is not Scalar, Hash is not Scalar
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Array', 'Scalar'),
    'Array is NOT subtype of Scalar');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Hash', 'Scalar'),
    'Hash is NOT subtype of Scalar');

# ========================================================================
# Builtin signatures - get_builtin / has_builtin
# ========================================================================

# has_builtin returns true for known builtins
for my $name (qw(push pop shift unshift splice keys values delete exists
                  each length chomp chop chr ord join split sprintf substr
                  defined ref scalar die warn bless print say)) {
    ok(Chalk::Grammar::Perl::TypeLibrary::has_builtin($name),
        "has_builtin('$name') returns true");
}

# has_builtin returns true for map/grep/sort (block-first builtins)
for my $name (qw(map grep sort)) {
    ok(Chalk::Grammar::Perl::TypeLibrary::has_builtin($name),
        "has_builtin('$name') returns true");
}

# has_builtin returns false for non-builtins and keywords
for my $name (qw(foo bar class if my)) {
    ok(!Chalk::Grammar::Perl::TypeLibrary::has_builtin($name),
        "has_builtin('$name') returns false");
}

# get_builtin returns signature hash for known builtins
{
    my $push_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('push');
    ok(defined $push_sig, 'get_builtin(push) returns defined value');
    is($push_sig->{min_arity}, 2, 'push min_arity is 2');
    is($push_sig->{arg_types}[0], 'Array', 'push first arg type is Array');
    is($push_sig->{return_type}, 'Int', 'push return type is Int');
}

{
    my $pop_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('pop');
    ok(defined $pop_sig, 'get_builtin(pop) returns defined value');
    is($pop_sig->{min_arity}, 1, 'pop min_arity is 1');
    is($pop_sig->{arg_types}[0], 'Array', 'pop first arg type is Array');
    is($pop_sig->{return_type}, 'Scalar', 'pop return type is Scalar');
}

{
    my $keys_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('keys');
    ok(defined $keys_sig, 'get_builtin(keys) returns defined value');
    is($keys_sig->{min_arity}, 1, 'keys min_arity is 1');
    is($keys_sig->{arg_types}[0], 'Hash', 'keys first arg type is Hash');
    is($keys_sig->{return_type}, 'List', 'keys return type is List');
}

{
    my $die_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('die');
    ok(defined $die_sig, 'get_builtin(die) returns defined value');
    is($die_sig->{min_arity}, 0, 'die min_arity is 0');
    is($die_sig->{return_type}, 'None', 'die return type is None');
}

{
    my $bless_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('bless');
    ok(defined $bless_sig, 'get_builtin(bless) returns defined value');
    is($bless_sig->{min_arity}, 1, 'bless min_arity is 1');
    is($bless_sig->{arg_types}[0], 'Ref', 'bless first arg type is Ref');
    is($bless_sig->{return_type}, 'Object', 'bless return type is Object');
}

# Block-first builtins: map, grep, sort
{
    my $map_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('map');
    ok(defined $map_sig, 'get_builtin(map) returns defined value');
    is($map_sig->{min_arity}, 2, 'map min_arity is 2');
    is($map_sig->{arg_types}[0], 'Code', 'map first arg type is Code');
    is($map_sig->{arg_types}[1], 'List', 'map second arg type is List');
    is($map_sig->{return_type}, 'List', 'map return type is List');
}

{
    my $grep_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('grep');
    ok(defined $grep_sig, 'get_builtin(grep) returns defined value');
    is($grep_sig->{min_arity}, 2, 'grep min_arity is 2');
    is($grep_sig->{arg_types}[0], 'Code', 'grep first arg type is Code');
    is($grep_sig->{arg_types}[1], 'List', 'grep second arg type is List');
    is($grep_sig->{return_type}, 'List', 'grep return type is List');
}

{
    my $sort_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('sort');
    ok(defined $sort_sig, 'get_builtin(sort) returns defined value');
    is($sort_sig->{min_arity}, 1, 'sort min_arity is 1');
    is($sort_sig->{arg_types}[0], 'List', 'sort first arg type is List');
    is($sort_sig->{return_type}, 'List', 'sort return type is List');
}

# get_builtin returns undef for unknown names
is(Chalk::Grammar::Perl::TypeLibrary::get_builtin('foo'), undef,
    'get_builtin(foo) returns undef');

# ========================================================================
# Tag-to-type mapping
# ========================================================================

is(Chalk::Grammar::Perl::TypeLibrary::tag_to_type('is_array_typed'), 'Array',
    'tag_to_type(is_array_typed) returns Array');
is(Chalk::Grammar::Perl::TypeLibrary::tag_to_type('is_hash_typed'), 'Hash',
    'tag_to_type(is_hash_typed) returns Hash');
is(Chalk::Grammar::Perl::TypeLibrary::tag_to_type('is_scalar_typed'), 'Scalar',
    'tag_to_type(is_scalar_typed) returns Scalar');
is(Chalk::Grammar::Perl::TypeLibrary::tag_to_type('unknown_tag'), undef,
    'tag_to_type(unknown_tag) returns undef');

# ========================================================================
# tags_satisfy_type - check semiring value tags against required type
# ========================================================================

# Array-typed value satisfies Array requirement
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_array_typed => true }, 'Array'),
    'array-tagged value satisfies Array');

# Array-typed value satisfies List requirement (Array is subtype of List)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_array_typed => true }, 'List'),
    'array-tagged value satisfies List');

# Array-typed value satisfies Any requirement
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_array_typed => true }, 'Any'),
    'array-tagged value satisfies Any');

# Hash-typed value satisfies Hash requirement
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_hash_typed => true }, 'Hash'),
    'hash-tagged value satisfies Hash');

# Hash-typed value satisfies List requirement (Hash is subtype of List)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_hash_typed => true }, 'List'),
    'hash-tagged value satisfies List');

# Scalar-typed value satisfies Scalar requirement
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_scalar_typed => true }, 'Scalar'),
    'scalar-tagged value satisfies Scalar');

# Scalar-typed value does NOT satisfy Array requirement
ok(!Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_scalar_typed => true }, 'Array'),
    'scalar-tagged value does NOT satisfy Array');

# Array-typed value does NOT satisfy Hash requirement
ok(!Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true, is_array_typed => true }, 'Hash'),
    'array-tagged value does NOT satisfy Hash');

# Untagged value satisfies Any requirement (anything satisfies Any)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Any'),
    'untagged value satisfies Any');

# Untagged value does NOT satisfy Array requirement (strict: taggable type)
ok(!Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Array'),
    'untagged value does NOT satisfy Array (strict taggable)');

# Untagged value does NOT satisfy Hash requirement (strict: taggable type)
ok(!Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Hash'),
    'untagged value does NOT satisfy Hash (strict taggable)');

# Untagged value satisfies Str requirement (permissive: no scan-time tag for Str)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Str'),
    'untagged value satisfies Str (permissive non-taggable)');

# Untagged value satisfies Scalar requirement (permissive: Scalar not in taggable set)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Scalar'),
    'untagged value satisfies Scalar (permissive non-taggable)');

# Untagged value satisfies Ref requirement (permissive)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Ref'),
    'untagged value satisfies Ref (permissive non-taggable)');

# Untagged value satisfies Int requirement (permissive)
ok(Chalk::Grammar::Perl::TypeLibrary::tags_satisfy_type(
    { valid => true }, 'Int'),
    'untagged value satisfies Int (permissive non-taggable)');

# ========================================================================
# Binary operator signatures - get_binary_op
# ========================================================================

# Arithmetic operators
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('+');
    ok(defined $sig, 'get_binary_op(+) returns defined value');
    is($sig->{left}, 'Num', '+ left operand is Num');
    is($sig->{right}, 'Num', '+ right operand is Num');
    is($sig->{result}, 'Num', '+ result is Num');
}

# String concatenation
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('.');
    ok(defined $sig, 'get_binary_op(.) returns defined value');
    is($sig->{left}, 'Str', '. left operand is Str');
    is($sig->{result}, 'Str', '. result is Str');
}

# Numeric comparison
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('==');
    ok(defined $sig, 'get_binary_op(==) returns defined value');
    is($sig->{result}, 'Bool', '== result is Bool');
}

# String comparison
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('eq');
    ok(defined $sig, 'get_binary_op(eq) returns defined value');
    is($sig->{left}, 'Str', 'eq left operand is Str');
    is($sig->{result}, 'Bool', 'eq result is Bool');
}

# Logical operators
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('&&');
    ok(defined $sig, 'get_binary_op(&&) returns defined value');
    is($sig->{left}, 'Any', '&& left operand is Any');
    is($sig->{result}, 'Any', '&& result is Any');
}

# Regex binding
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('=~');
    ok(defined $sig, 'get_binary_op(=~) returns defined value');
    is($sig->{left}, 'Str', '=~ left operand is Str');
    is($sig->{right}, 'Regex', '=~ right operand is Regex');
    is($sig->{result}, 'Bool', '=~ result is Bool');
}

# isa operator
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('isa');
    ok(defined $sig, 'get_binary_op(isa) returns defined value');
    is($sig->{left}, 'Scalar', 'isa left operand is Scalar');
    is($sig->{result}, 'Bool', 'isa result is Bool');
}

# Range operator
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('..');
    ok(defined $sig, 'get_binary_op(..) returns defined value');
    is($sig->{result}, 'List', '.. result is List');
}

# Assignment
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('=');
    ok(defined $sig, 'get_binary_op(=) returns defined value');
    is($sig->{left}, 'Any', '= left operand is Any');
    is($sig->{result}, 'Any', '= result is Any');
}

# Unknown operator
is(Chalk::Grammar::Perl::TypeLibrary::get_binary_op('???'), undef,
    'get_binary_op(???) returns undef');

# ========================================================================
# Unary operator signatures - get_unary_op
# ========================================================================

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('-');
    ok(defined $sig, 'get_unary_op(-) returns defined value');
    is($sig->{operand}, 'Num', 'unary - operand is Num');
    is($sig->{result}, 'Num', 'unary - result is Num');
}

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('!');
    ok(defined $sig, 'get_unary_op(!) returns defined value');
    is($sig->{operand}, 'Any', 'unary ! operand is Any');
    is($sig->{result}, 'Bool', 'unary ! result is Bool');
}

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('\\');
    ok(defined $sig, 'get_unary_op(\\) returns defined value');
    is($sig->{operand}, 'Any', 'unary \\ operand is Any');
    is($sig->{result}, 'Ref', 'unary \\ result is Ref');
}

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('not');
    ok(defined $sig, 'get_unary_op(not) returns defined value');
    is($sig->{result}, 'Bool', 'unary not result is Bool');
}

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('~');
    ok(defined $sig, 'get_unary_op(~) returns defined value');
    is($sig->{operand}, 'Int', 'unary ~ operand is Int');
    is($sig->{result}, 'Int', 'unary ~ result is Int');
}

is(Chalk::Grammar::Perl::TypeLibrary::get_unary_op('???'), undef,
    'get_unary_op(???) returns undef');

done_testing;
