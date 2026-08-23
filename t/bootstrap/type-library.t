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
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'Unknown'),
    'Scalar is subtype of Unknown');

# Transitive relationships
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Scalar'),
    'Int is subtype of Scalar (transitive)');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Unknown'),
    'Int is subtype of Unknown (transitive)');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Num', 'Unknown'),
    'Num is subtype of Unknown (transitive)');

# Self is subtype of self
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Int'),
    'Int is subtype of Int (reflexive)');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Unknown', 'Unknown'),
    'Unknown is subtype of Unknown (reflexive)');

# Not subtypes
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Num', 'Int'),
    'Num is NOT subtype of Int');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'Str'),
    'Scalar is NOT subtype of Str');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Unknown', 'Scalar'),
    'Unknown is NOT subtype of Scalar');

# Collection types
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Array', 'List'),
    'Array is subtype of List');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Hash', 'List'),
    'Hash is subtype of List');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('List', 'Unknown'),
    'List is subtype of Unknown');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Array', 'Unknown'),
    'Array is subtype of Unknown (transitive)');

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
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Unknown'),
    'None is subtype of Unknown');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Scalar'),
    'None is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Int'),
    'None is subtype of Int');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Array'),
    'None is subtype of Array');

# Boolean, Undef, Regex
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Boolean', 'Scalar'),
    'Boolean is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Undef', 'Scalar'),
    'Undef is subtype of Scalar');
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Regex', 'Scalar'),
    'Regex is subtype of Scalar');

# Code
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Code', 'Unknown'),
    'Code is subtype of Unknown');
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
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Unknown'),
    'DualVar is subtype of Unknown (transitive)');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Str'),
    'DualVar is NOT subtype of Str');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('DualVar', 'Num'),
    'DualVar is NOT subtype of Num');
ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Str', 'DualVar'),
    'Str is NOT subtype of DualVar');

# Glob: top-level type, distinct from GlobRef
ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Glob', 'Unknown'),
    'Glob is subtype of Unknown');
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
    is($die_sig->{arg_types}[0], 'List', 'die arg type is List (variadic)');
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

# Tightened builtin signatures: specific types where possible, List for variadic (Perl list flattening)
# push/unshift: variadic args are List (Perl flattening: accepts scalars AND arrays)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('push');
    is($sig->{arg_types}[1], 'List', 'push variadic arg type is List (Perl list flattening)');
}
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('unshift');
    is($sig->{arg_types}[1], 'List', 'unshift variadic arg type is List (Perl list flattening)');
}

# splice: offset and length are Int, rest is List (Perl list flattening)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('splice');
    is($sig->{arg_types}[1], 'Num', 'splice offset arg is Num');
    is($sig->{arg_types}[2], 'Num', 'splice length arg is Num');
    is($sig->{arg_types}[3], 'List', 'splice replacement args are List (Perl list flattening)');
}

# length: operates on Str
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('length');
    is($sig->{arg_types}[0], 'Str', 'length arg type is Str');
}

# join: separator is Str, rest is List (Perl list flattening)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('join');
    is($sig->{arg_types}[0], 'Str', 'join separator arg is Str');
    is($sig->{arg_types}[1], 'List', 'join rest args are List (Perl list flattening)');
}

# split: pattern, string, limit
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('split');
    is($sig->{arg_types}[1], 'Str', 'split string arg is Str');
    is($sig->{arg_types}[2], 'Num', 'split limit arg is Num');
}

# substr: 3rd arg (length) is Int
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('substr');
    is($sig->{arg_types}[2], 'Num', 'substr length arg is Num');
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

# Variadic builtins: die, warn, print, say, chomp, chop, return, scalar stay List
# (Perl list flattening: these accept both scalars and arrays)
for my $name (qw(die warn print say chomp chop return scalar)) {
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin($name);
    is($sig->{arg_types}[0], 'List', "$name arg type is List (variadic, Perl list flattening)");
}

# sprintf: format args are List (variadic, Perl list flattening)
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('sprintf');
    is($sig->{arg_types}[1], 'List', 'sprintf variadic arg type is List (Perl list flattening)');
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
    is($sig->{result}, 'Boolean', '== result is Boolean');
}

# String comparison
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('eq');
    ok(defined $sig, 'get_binary_op(eq) returns defined value');
    is($sig->{left}, 'Str', 'eq left operand is Str');
    is($sig->{result}, 'Boolean', 'eq result is Boolean');
}

# Logical operators
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('&&');
    ok(defined $sig, 'get_binary_op(&&) returns defined value');
    is($sig->{left}, 'List', '&& left operand is List');
    is($sig->{result}, 'Unknown', '&& result is Unknown (it returns an operand)');
}

# Regex binding
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('=~');
    ok(defined $sig, 'get_binary_op(=~) returns defined value');
    is($sig->{left}, 'Str', '=~ left operand is Str');
    is($sig->{right}, 'Regex', '=~ right operand is Regex');
    is($sig->{result}, 'Boolean', '=~ result is Boolean');
}

# isa operator
{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op('isa');
    ok(defined $sig, 'get_binary_op(isa) returns defined value');
    is($sig->{left}, 'Scalar', 'isa left operand is Scalar');
    is($sig->{result}, 'Boolean', 'isa result is Boolean');
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
    is($sig->{left}, 'List', '= left operand is List');
    is($sig->{result}, 'Unknown', '= result is Unknown (it yields the assigned value)');
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
    is($sig->{operand}, 'List', 'unary ! operand is List');
    is($sig->{result}, 'Boolean', 'unary ! result is Boolean');
}

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('\\');
    ok(defined $sig, 'get_unary_op(\\) returns defined value');
    is($sig->{operand}, 'List', 'unary \\ operand is List');
    is($sig->{result}, 'Ref', 'unary \\ result is Ref');
}

{
    my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op('not');
    ok(defined $sig, 'get_unary_op(not) returns defined value');
    is($sig->{result}, 'Boolean', 'unary not result is Boolean');
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
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies(undef, 'Unknown'),
    'type_satisfies(undef, List) returns true (permissive)');

# A List required type always passes -- perl flattens into list context
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Int', 'Unknown'),
    'type_satisfies(Int, List) returns true');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Array', 'Unknown'),
    'type_satisfies(Array, List) returns true');
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Code', 'Unknown'),
    'type_satisfies(Code, List) returns true');

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
ok(Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Glob', 'Unknown'),
    'type_satisfies(Glob, List) returns true');
ok(!Chalk::Grammar::Perl::TypeLibrary::type_satisfies('Glob', 'Scalar'),
    'type_satisfies(Glob, Scalar) returns false');

# return builtin signature: propagates argument type
{
    my $return_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('return');
    ok(defined $return_sig, 'get_builtin(return) returns defined value');
    is($return_sig->{min_arity}, 0, 'return min_arity is 0');
    is($return_sig->{arg_types}[0], 'List', 'return first arg type is List (variadic)');
    is($return_sig->{return_type}, 'List', 'return return_type is List');
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

# Boolean context: everything narrows to Boolean
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('List', 'Boolean'), 'Boolean',
    'narrow_type(List, Boolean) = Boolean');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Str', 'Boolean'), 'Boolean',
    'narrow_type(Str, Boolean) = Boolean');
is(Chalk::Grammar::Perl::TypeLibrary::narrow_type('Array', 'Boolean'), 'Boolean',
    'narrow_type(Array, Boolean) = Boolean');

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

# ========================================================================
# Builtin arg types: Num-accepting position args (substr, splice, split)
# ========================================================================
# Arithmetic expressions produce Num, so builtins that take positional
# integer args must accept Num to avoid rejecting e.g. substr($s, 0, $x - $y).

{
    my $substr_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('substr');
    is($substr_sig->{arg_types}[1], 'Num',
        'substr arg 2 (offset) accepts Num');
    is($substr_sig->{arg_types}[2], 'Num',
        'substr arg 3 (length) accepts Num');
}

{
    my $splice_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('splice');
    is($splice_sig->{arg_types}[1], 'Num',
        'splice arg 2 (offset) accepts Num');
    is($splice_sig->{arg_types}[2], 'Num',
        'splice arg 3 (length) accepts Num');
}

{
    my $split_sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin('split');
    is($split_sig->{arg_types}[2], 'Num',
        'split arg 3 (limit) accepts Num');
}

# ========================================================================
# Type bitset representation (Section 3.3 of design doc)
# ========================================================================

# type_bitset returns an integer for each type
{
    my $int_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Int');
    ok(defined $int_bits, 'type_bitset(Int) returns defined value');
    ok($int_bits > 0, 'type_bitset(Int) is a positive integer');
}

# Subtype check via bitwise AND: IsSubtype(child, parent) = (parent & child) == child
{
    my $int_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Int');
    my $num_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Num');
    my $str_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Str');
    my $scalar_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Scalar');
    my $any_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('List');

    # Int is subtype of Num: (Num & Int) == Int
    is(($num_bits & $int_bits), $int_bits, 'bitwise: Int is subtype of Num');
    # Int is subtype of Str: (Str & Int) == Int
    is(($str_bits & $int_bits), $int_bits, 'bitwise: Int is subtype of Str');
    # Int is subtype of Scalar: (Scalar & Int) == Int
    is(($scalar_bits & $int_bits), $int_bits, 'bitwise: Int is subtype of Scalar');
    # Int is subtype of Unknown: (Unknown & Int) == Int
    is(($any_bits & $int_bits), $int_bits, 'bitwise: Int is subtype of Unknown');

    # Num is NOT subtype of Int: (Int & Num) != Num
    isnt(($int_bits & $num_bits), $num_bits, 'bitwise: Num is NOT subtype of Int');
    # Scalar is NOT subtype of Str: (Str & Scalar) != Scalar
    isnt(($str_bits & $scalar_bits), $scalar_bits, 'bitwise: Scalar is NOT subtype of Str');
}

# Cross-branch types have disjoint bitsets
{
    my $array_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Array');
    my $scalar_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Scalar');
    my $code_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Code');

    isnt(($scalar_bits & $array_bits), $array_bits, 'bitwise: Array is NOT subtype of Scalar');
    isnt(($scalar_bits & $code_bits), $code_bits, 'bitwise: Code is NOT subtype of Scalar');
}

# Ref hierarchy
{
    my $ref_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Ref');
    my $arrayref_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('ArrayRef');
    my $hashref_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('HashRef');
    my $coderef_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('CodeRef');
    my $object_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('Object');

    is(($ref_bits & $arrayref_bits), $arrayref_bits, 'bitwise: ArrayRef is subtype of Ref');
    is(($ref_bits & $hashref_bits), $hashref_bits, 'bitwise: HashRef is subtype of Ref');
    is(($ref_bits & $coderef_bits), $coderef_bits, 'bitwise: CodeRef is subtype of Ref');
    is(($ref_bits & $object_bits), $object_bits, 'bitwise: Object is subtype of Ref');
}

# None has a unique bitset of 0 (subtype of everything by convention)
{
    my $none_bits = Chalk::Grammar::Perl::TypeLibrary::type_bitset('None');
    is($none_bits, 0, 'type_bitset(None) is 0 (bottom type)');
}

# is_subtype uses bitwise ops internally — verify it still works
# (These duplicate existing tests but confirm the new implementation path)
{
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Unknown'),
        'is_subtype still works with bitsets: Int <: List');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('ArrayRef', 'Scalar'),
        'is_subtype still works with bitsets: ArrayRef <: Scalar');
    ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Code', 'Scalar'),
        'is_subtype still works with bitsets: Code NOT <: Scalar');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('None', 'Hash'),
        'is_subtype still works with bitsets: None <: Hash');
}

# ---------------------------------------------------------------------------
# Unknown: the PESSIMISTIC top type, and the only top.
#
# It means inference has not determined the type, and NOTHING may be done with
# the value until it is narrowed -- so Unknown reaching the backend is a BUG.
# Distinct from Scalar, a legitimate static answer naming one value whose
# concrete type was never narrowed: the backend's Scalar GAP must be able to
# tell "this scalar type is not lowered yet" from "nothing ever typed this".
# ---------------------------------------------------------------------------

subtest 'Unknown is top: every type is a subtype of it' => sub {
    for my $t (qw(Int Num Str Boolean Undef Scalar ArrayRef HashRef CodeRef
                  Object Array Hash Code Glob List Ref None
                  VString LValueRef GlobRef Regex Void DualVar IO Format)) {
        ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype($t, 'Unknown'),
            "$t <: Unknown");
    }
};

subtest 'Unknown is not a subtype of anything below top' => sub {
    for my $t (qw(Scalar Str Num Int Boolean Ref List Code)) {
        ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Unknown', $t),
            "Unknown NOT <: $t");
    }
    # Unknown is the ONLY top: a second one would make join ambiguous.
    ok(!defined Chalk::Grammar::Perl::TypeLibrary::type_bitset('Any'),
        'Any is not a type');
};

subtest 'Unknown is DISTINCT from Scalar (the bug this exists to prevent)' => sub {
    ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Unknown', 'Scalar'),
        'Unknown is NOT a Scalar -- an untyped value is not "some scalar"');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'Unknown'),
        'Scalar IS an Unknown (Unknown is top)');
};

# ---------------------------------------------------------------------------
# operand_repr_for_ir_op: the IR asks the same signature tables the parser asks.
# ---------------------------------------------------------------------------

subtest 'operand_repr_for_ir_op reads the signature, per position' => sub {
    my $f = \&Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op;

    # Ord and Chr USED to be asserted here. They were removed: no such node
    # types exist, so those entries could never be consulted and these
    # assertions pinned nothing while reading as coverage. The map is now
    # checked against the factory in
    # t/bootstrap/ir/typelibrary-is-the-coercion-authority.t.
    is($f->('Length', 0), 'Str', 'Length position 0 wants Str (length => arg_types [Str])');

    # ...and NOT beyond its arity. `length` is not variadic, so it has no
    # opinion about a second operand it does not take.
    is($f->('Length', 1), undef, 'Length position 1 declines -- length is not variadic');

    # Binary ops answer per position from left/right.
    is($f->('Concat', 0), 'Str', 'Concat position 0 wants Str');
    is($f->('Concat', 1), 'Str', 'Concat position 1 wants Str');

    # The five string comparisons the old hand-written list omitted. These are
    # the ops %_STR_CONTEXT_OPS never had, and no code change was needed to
    # cover them -- the signature already said so.
    for my $op (qw(StrLt StrGt StrLe StrGe StrCmp)) {
        is($f->($op, 0), 'Str', "$op position 0 wants Str (was absent from the old list)");
        is($f->($op, 1), 'Str', "$op position 1 wants Str");
    }
};

subtest 'operand_repr_for_ir_op DECLINES rather than guessing' => sub {
    my $f = \&Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op;

    # Unmapped op: no opinion, so the caller leaves the operand alone.
    is($f->('Add', 0), undef, 'Add is unmapped -- no opinion, not a guess');
    is($f->('NoSuchOpXYZ', 0), undef, 'an unknown op declines');

    # The bitwise family is deliberately absent: `&` is (Int,Int)->Int while
    # `&.` is a Str operator and BOTH lower to BitAnd, so the node does not
    # determine its operand types and no single answer is correct.
    for my $op (qw(BitAnd BitOr BitXor)) {
        is($f->($op, 0), undef,
            "$op declines -- numeric `&` and string `&.` share this node type");
    }

    # Print is absent BY DESIGN. The builtin is variadic over List because perl
    # flattens a LIST into it; the NODE's Str-only contract is a different
    # claim, stated on the node in Serialize/JSON.pm. Conflating them would
    # reject `print @a`, which is a legal program.
    is($f->('Print', 0), undef,
        'Print declines -- the builtin is variadic List, the node contract is separate');
};

subtest 'accepts_operand_repr covers the conflated Length node' => sub {
    my $f = \&Chalk::Grammar::Perl::TypeLibrary::accepts_operand_repr;

    # Chalk's Length node serves BOTH `length($str)` and @a-in-scalar-context,
    # so it accepts aggregates as-is. Perl's own `length` does NOT: measured,
    # `length(@a)` on a 3-element array is 1 (the array goes to scalar context,
    # then length("3")), so this set is a bridge over a producer conflation,
    # not a fact about perl.
    for my $repr (qw(Array ArrayRef Hash HashRef Str)) {
        ok($f->('Length', $repr), "Length accepts $repr as-is (no coercion)");
    }
    ok(!$f->('Length', 'Int'),
        'Length does NOT accept Int -- an Int operand still coerces to Str, which is S13');

    ok(!$f->('Concat', 'ArrayRef'), 'Concat accepts no set -- it has a plain signature');
    ok(!$f->('Length', undef),      'an undef repr is never accepted');
};

done_testing;
