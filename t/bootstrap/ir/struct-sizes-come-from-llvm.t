# ABOUTME: Struct allocation sizes are computed by LLVM from the type, not by hand.
# ABOUTME: A hand-written size is a silent under-allocation the day a field lands.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Target::LLVM::Context;
my $C = 'Chalk::Target::LLVM::Context';

# WHY: `$n * 16` for %Slot and `$npairs * 48` for %HashEntry duplicated LLVM's
# own layout arithmetic in perl. Add a field and the multiplier is WRONG with
# no error anywhere -- an under-allocated buffer, which is a wrong answer
# rather than a compile failure. The `getelementptr null, i64 1` idiom asks
# LLVM for the size of the type it is already emitting, so the two cannot drift.

subtest 'a sizeof helper exists and produces the null-GEP idiom' => sub {
    ok $C->can('_sizeof_llvm_type'), '_sizeof_llvm_type exists';
    my $s = $C->_sizeof_llvm_type('%Slot');
    like $s, qr/getelementptr/,        'uses getelementptr';
    like $s, qr/null/,                 'from the null pointer';
    like $s, qr/i64 1/,                'one element past';
    like $s, qr/ptrtoint/,             'converted to an integer';
    like $s, qr/\Q%Slot\E/,            'names the type it is sizing';
};

subtest 'no allocation site carries a hand-written struct size' => sub {
    # CODE ONLY. An earlier version of this test grepped the whole file and
    # went red against the COMMENTS that describe the literals being removed --
    # a false RED, and the mirror image of the false GREENs this project has
    # collected. Strip comment lines first so the assertion is about what runs.
    my @code;
    open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
    while (my $l = <$fh>) {
        next if $l =~ /^\s*#/;
        push @code, $l;
    }
    my $code = join '', @code;

    unlike $code, qr/\$n \* 16/,      'no literal 16 for a Slot array';
    unlike $code, qr/\$npairs \* 48/, 'no literal 48 for HashEntry';

    # Struct allocations must not take a literal count. A NON-struct byte
    # buffer legitimately does -- Stringify[Int]'s digit buffer is 24 bytes of
    # characters, not a %Struct -- so this checks the struct sites by name.
    for my $ty (qw(Slot Array Hash HashEntry StrPair Str)) {
        unlike $code, qr/malloc\(i64 \d+\)[^\n]*\b\Q$ty\E\b/,
            "no literal-sized malloc labelled $ty";
    }

    # And every struct allocation that remains goes through the helper.
    my $n_sizeof = () = $code =~ /_sizeof_llvm_type|_sizeof_times/g;
    ok $n_sizeof >= 5, "struct sizes come from the helper ($n_sizeof uses)";
};

subtest 'the perl-side layout arithmetic is gone' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
        local $/; <$fh>;
    };
    unlike $src, qr/sub _struct_size_bytes/,
        '_struct_size_bytes is deleted -- LLVM computes sizes now';
    for my $gone (qw(_slot_size_bytes _str_size_bytes _strpair_size_bytes)) {
        unlike $src, qr/sub \Q$gone\E\b/, "$gone is deleted";
    }
};

done_testing;
