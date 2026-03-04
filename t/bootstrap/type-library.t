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

# DualVar: sits in Scalar but outside Str/Num branches
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Scalar'),
    'DualVar is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Any'),
    'DualVar is subtype of Any (transitive)');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Str'),
    'DualVar is NOT subtype of Str');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Num'),
    'DualVar is NOT subtype of Num');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Str', 'DualVar'),
    'Str is NOT subtype of DualVar');

# Glob: top-level type, distinct from GlobRef
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Glob', 'Any'),
    'Glob is subtype of Any');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Glob', 'Scalar'),
    'Glob is NOT subtype of Scalar');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('GlobRef', 'Glob'),
    'GlobRef is NOT subtype of Glob (different branches)');

# ========================================================================
# Builtin signatures - get_builtin / has_builtin
# ========================================================================

# has_builtin returns true for known builtins
for my $name (qw(push pop shift unshift splice keys values delete exists
                  each length chomp chop chr ord join split sprintf substr
                  defined ref scalar die warn bless print say return)) {
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
    is($die_sig->{arg_types}[0], 'Any', 'die arg type is Any (variadic)');
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

# Tightened builtin signatures: specific types where possible, Any for variadic (Perl list flattening)
# push/unshift: variadic args are Any (Perl flattening: accepts scalars AND arrays)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('push');
    is($sig->{arg_types}[1], 'Any', 'push variadic arg type is Any (Perl list flattening)');
}
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('unshift');
    is($sig->{arg_types}[1], 'Any', 'unshift variadic arg type is Any (Perl list flattening)');
}

# splice: offset and length are Int, rest is Any (Perl list flattening)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('splice');
    is($sig->{arg_types}[1], 'Int', 'splice offset arg is Int');
    is($sig->{arg_types}[2], 'Int', 'splice length arg is Int');
    is($sig->{arg_types}[3], 'Any', 'splice replacement args are Any (Perl list flattening)');
}

# length: operates on Str
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('length');
    is($sig->{arg_types}[0], 'Str', 'length arg type is Str');
}

# join: separator is Str, rest is Any (Perl list flattening)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('join');
    is($sig->{arg_types}[0], 'Str', 'join separator arg is Str');
    is($sig->{arg_types}[1], 'Any', 'join rest args are Any (Perl list flattening)');
}

# split: pattern, string, limit
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('split');
    is($sig->{arg_types}[1], 'Str', 'split string arg is Str');
    is($sig->{arg_types}[2], 'Int', 'split limit arg is Int');
}

# substr: 3rd arg (length) is Int
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('substr');
    is($sig->{arg_types}[2], 'Int', 'substr length arg is Int');
}

# bless: 2nd arg is class name (Str)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('bless');
    is($sig->{arg_types}[1], 'Str', 'bless class name arg is Str');
}

# Single-value Scalar-arg builtins: defined, ref, exists, delete
for my $name (qw(defined ref exists delete)) {
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin($name);
    is($sig->{arg_types}[0], 'Scalar', "$name arg type is Scalar");
}

# Variadic builtins: die, warn, print, say, chomp, chop, return, scalar stay Any
# (Perl list flattening: these accept both scalars and arrays)
for my $name (qw(die warn print say chomp chop return scalar)) {
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin($name);
    is($sig->{arg_types}[0], 'Any', "$name arg type is Any (variadic, Perl list flattening)");
}

# sprintf: format args are Any (variadic, Perl list flattening)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('sprintf');
    is($sig->{arg_types}[1], 'Any', 'sprintf variadic arg type is Any (Perl list flattening)');
}

# get_builtin returns undef for unknown names
is(Chalk::Grammar::Perl::TypeLibrary::get_builtin('foo'), undef,
    'get_builtin(foo) returns undef');

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

# ========================================================================
# type_satisfies - check actual type against required type
# ========================================================================

# undef actual type passes permissively (unknown type)
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies(undef, 'Array'),
    'type_satisfies(undef, Array) returns true (permissive)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies(undef, 'Scalar'),
    'type_satisfies(undef, Scalar) returns true (permissive)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies(undef, 'Any'),
    'type_satisfies(undef, Any) returns true (permissive)');

# Any required type always passes
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Int', 'Any'),
    'type_satisfies(Int, Any) returns true');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Array', 'Any'),
    'type_satisfies(Array, Any) returns true');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Code', 'Any'),
    'type_satisfies(Code, Any) returns true');

# Subtype relationships
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Int', 'Scalar'),
    'type_satisfies(Int, Scalar) returns true (subtype)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Array', 'List'),
    'type_satisfies(Array, List) returns true (subtype)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Hash', 'List'),
    'type_satisfies(Hash, List) returns true (subtype)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Num', 'Str'),
    'type_satisfies(Num, Str) returns true (subtype)');

# Exact match
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Array', 'Array'),
    'type_satisfies(Array, Array) returns true (exact)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Scalar', 'Scalar'),
    'type_satisfies(Scalar, Scalar) returns true (exact)');

# Non-subtypes fail
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Scalar', 'Array'),
    'type_satisfies(Scalar, Array) returns false');
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Array', 'Hash'),
    'type_satisfies(Array, Hash) returns false');
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Code', 'Scalar'),
    'type_satisfies(Code, Scalar) returns false');
# Str is concrete (not polymorphic), so Str does NOT satisfy Int
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Str', 'Int'),
    'type_satisfies(Str, Int) returns false (concrete supertype, not polymorphic)');

# Scalar is polymorphic — a Scalar variable could hold an Int at runtime
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Scalar', 'Int'),
    'type_satisfies(Scalar, Int) returns true (polymorphic supertype)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Scalar', 'Str'),
    'type_satisfies(Scalar, Str) returns true (polymorphic supertype)');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Scalar', 'Regex'),
    'type_satisfies(Scalar, Regex) returns true (polymorphic supertype)');
# But Scalar does NOT satisfy Array (different branches)
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Scalar', 'Array'),
    'type_satisfies(Scalar, Array) returns false (incompatible branches)');

# DualVar type_satisfies: not polymorphic
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('DualVar', 'Scalar'),
    'type_satisfies(DualVar, Scalar) returns true (subtype)');
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('DualVar', 'Str'),
    'type_satisfies(DualVar, Str) returns false (not polymorphic)');
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('DualVar', 'Num'),
    'type_satisfies(DualVar, Num) returns false (not polymorphic)');

# Glob type_satisfies
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Glob', 'Any'),
    'type_satisfies(Glob, Any) returns true');
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Glob', 'Scalar'),
    'type_satisfies(Glob, Scalar) returns false');

# return builtin signature: propagates argument type
{
    my $return_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('return');
    ok(defined $return_sig, 'get_builtin(return) returns defined value');
    is($return_sig->{min_arity}, 0, 'return min_arity is 0');
    is($return_sig->{arg_types}[0], 'Any', 'return first arg type is Any (variadic)');
    is($return_sig->{return_type}, 'Any', 'return return_type is Any');
}

# ========================================================================
# narrow_type - context-based type narrowing
# ========================================================================

# Scalar context: Array/Hash → Int (count), List → Scalar, others unchanged
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Array', 'Scalar'), 'Int',
    'narrow_type(Array, Scalar) = Int (count)');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Hash', 'Scalar'), 'Int',
    'narrow_type(Hash, Scalar) = Int (count)');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('List', 'Scalar'), 'Scalar',
    'narrow_type(List, Scalar) = Scalar');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Str', 'Scalar'), 'Str',
    'narrow_type(Str, Scalar) = Str (already scalar-ish)');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Int', 'Scalar'), 'Int',
    'narrow_type(Int, Scalar) = Int (already scalar-ish)');

# Bool context: everything narrows to Bool
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('List', 'Bool'), 'Bool',
    'narrow_type(List, Bool) = Bool');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Str', 'Bool'), 'Bool',
    'narrow_type(Str, Bool) = Bool');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Array', 'Bool'), 'Bool',
    'narrow_type(Array, Bool) = Bool');

# Void context: discards type info
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Int', 'Void'), undef,
    'narrow_type(Int, Void) = undef');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Array', 'Void'), undef,
    'narrow_type(Array, Void) = undef');

# No context (undef): no narrowing
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Num', undef), 'Num',
    'narrow_type(Num, undef) = Num (no narrowing)');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Array', undef), 'Array',
    'narrow_type(Array, undef) = Array (no narrowing)');

# Undef type: no narrowing regardless of context
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type(undef, 'Scalar'), undef,
    'narrow_type(undef, Scalar) = undef (no type to narrow)');

# List context: keep as-is
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Array', 'List'), 'Array',
    'narrow_type(Array, List) = Array (list context preserves)');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Str', 'List'), 'Str',
    'narrow_type(Str, List) = Str (list context preserves)');

done_testing;
