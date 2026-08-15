# ABOUTME: _repr_to_llvm_type must GAP loudly on an undef repr, not silently pick 'i64'.
# ABOUTME: Also pins the four defined-repr mappings so the fix cannot break the normal path.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::Target::LLVM::Context;

# _repr_to_llvm_type selects the machine type for a node at lowering time.
# An undef repr previously defaulted to 'Int' (`$repr //= 'Int'`), so a node
# that reached machine-type selection with no representation at all was
# silently emitted as i64 instead of refusing. Every other unknown-repr path
# in this backend refuses loudly (_require_repr, 15 repr=Scalar guards); this
# one guessed, and guessed the one value that matches a real branch.

subtest 'undef repr dies loudly instead of defaulting to i64' => sub {
    my $err;
    eval { Chalk::Target::LLVM::Context::_repr_to_llvm_type(undef) };
    $err = $@;

    ok(defined $err && length $err, '_repr_to_llvm_type(undef) dies')
        or diag('Got no error; silently returned a type instead');

    like($err, qr/GAP|representation|repr/i,
        'error message mentions GAP or representation')
        if defined $err;
};

subtest 'no-argument call dies loudly instead of defaulting to i64' => sub {
    my $err;
    eval { Chalk::Target::LLVM::Context::_repr_to_llvm_type() };
    $err = $@;

    ok(defined $err && length $err, '_repr_to_llvm_type() dies')
        or diag('Got no error; silently returned a type instead');

    like($err, qr/GAP|representation|repr/i,
        'error message mentions GAP or representation')
        if defined $err;
};

subtest 'defined reprs still map correctly' => sub {
    is(Chalk::Target::LLVM::Context::_repr_to_llvm_type('Int'),  'i64',    'Int -> i64');
    is(Chalk::Target::LLVM::Context::_repr_to_llvm_type('Num'),  'double', 'Num -> double');
    is(Chalk::Target::LLVM::Context::_repr_to_llvm_type('Bool'), 'i1',     'Bool -> i1');
    # A Str VALUE is the first-class aggregate { ptr, len, enc }, not a bare
    # pointer: the length travels IN the value so a merge cannot lose it.
    is(Chalk::Target::LLVM::Context::_repr_to_llvm_type('Str'),  '%Str',   'Str -> %Str');
};

done_testing;
