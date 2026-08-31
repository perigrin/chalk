# ABOUTME: A Str SSA value is a first-class aggregate {ptr, len, enc}, not a bare i8*.
# ABOUTME: The length rides IN the value, so it cannot desynchronize from the pointer.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::Target::LLVM::Context;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS.
#
# A Str SSA value was a bare `i8*` with its byte length in the `_str_len_table`
# side channel. That was never a design — it is C's `char*` habit, and this
# codebase knew it was insufficient from the first commit that introduced it
# (e602f231, "a Str via printf(\"%.*s\", len, ptr) from the tracked
# _str_len_table ... embedded-NUL safe"): the table was born in the same breath
# as the pointer, precisely because the pointer alone is not a string.
#
# The tell is that NOT ONE consumer uses the pointer alone. printf("%.*s"),
# memcmp, memcpy and chalk_str_to_num all take (ptr, len). When every use site
# needs two things, those two things are one value.
#
# LLVM has first-class aggregates: a struct can be an SSA value, returned,
# phi'd, and read with extractvalue. Verified against lli 15 directly. So the
# side table was standing in for a struct the target supported all along.
# ---------------------------------------------------------------------------

subtest 'the Str value type is declared, with three fields' => sub {
    plan tests => 4;

    ok(defined &Chalk::Target::LLVM::Context::_str_fields,
        'the Str field list is a single source of truth');

    my @f = Chalk::Target::LLVM::Context::_str_fields();
    is(scalar @f, 3, 'a Str is THREE fields: ptr, len, enc');
    is($f[0]{name}, 'ptr', 'field 0 is the data pointer');
    is($f[1]{name}, 'len', 'field 1 is the byte length');
};

subtest 'the encoding field exists and is field 2' => sub {
    plan tests => 2;
    my @f = Chalk::Target::LLVM::Context::_str_fields();
    is($f[2]{name}, 'enc', 'field 2 is the encoding tag');
    is($f[2]{llvm}, 'i32', 'the encoding is a tagged i32, not a bool flag');
};

# ---------------------------------------------------------------------------
# The size must stay DERIVED -- and it is now LLVM that derives it. Adding the
# third field makes the struct 24 bytes with tail padding, and a hardcoded 16
# would under-allocate and corrupt the heap silently, because every corpus
# string is ASCII so `enc` is always 0.
#
# This subtest used to call _str_size_bytes and then RE-COMPUTE the expected
# value with the same alignment arithmetic -- a third copy of LLVM's layout
# rules, checking a second copy against itself. Both are gone: the emitted IR
# asks LLVM via `getelementptr null, i64 1`, so the size cannot disagree with
# the struct. What is worth pinning now is that the ALLOCATION SITES go through
# that helper rather than restating a number.
# ---------------------------------------------------------------------------
subtest 'the size is asked of LLVM, never restated in perl' => sub {
    plan tests => 4;

    ok(!Chalk::Target::LLVM::Context->can('_str_size_bytes'),
       'the perl-side size function is gone');

    my $sz = Chalk::Target::LLVM::Context::_sizeof_llvm_type('%Str');
    like($sz, qr/getelementptr/, 'the size is a getelementptr constant expression');
    like($sz, qr/\Q%Str\E/,      'it names %Str, so it tracks the declaration');

    # The field list survives as the declaration's source, so a third field
    # still moves the emitted struct -- which is what moves the size.
    my @f = Chalk::Target::LLVM::Context::_str_fields();
    is(scalar(@f), 3, '{ptr, len, enc} -- three fields');
};

subtest 'the type declaration is built from the fields' => sub {
    plan tests => 2;
    my $decl = Chalk::Target::LLVM::Context::_str_type_decl();
    like($decl, qr/^%Str = type \{ i8\*, i64, i32 \}$/,
        'declaration names all three field types in order');
    unlike($decl, qr/StrPair/,
        'the value type is %Str — StrPair was the two-field name it outgrew');
};

done_testing;
