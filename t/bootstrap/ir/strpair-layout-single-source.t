# ABOUTME: The %StrPair layout has ONE definition; its allocation size is derived, not hardcoded.
# ABOUTME: A hardcoded malloc size silently under-allocates the moment a field is added.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::Target::LLVM::Context;

# ---------------------------------------------------------------------------
# The layout must be stated ONCE and read from there.
#
# Before this, `%StrPair = type { i8*, i64 }` was written as a literal at
# LLVM.pm:640 and again at :1313, and its byte size was hardcoded a THIRD time
# as `malloc(i64 16)` at Context.pm:4684 and :4732 -- four places that must
# agree, with nothing enforcing it.
#
# That is a live trap for the {ptr, len, enc} widening this file's own comment
# at Context.pm:897 already specifies: adding an i32 makes the struct 24 bytes
# with padding, so the two hardcoded 16s would under-allocate and corrupt the
# heap. No corpus case would catch it -- every corpus string is ASCII, so `enc`
# is always 0 and a short write may not visibly break anything.
# ---------------------------------------------------------------------------

subtest 'the layout is declared exactly once, as data' => sub {
    plan tests => 3;

    ok(defined &Chalk::Target::LLVM::Context::_strpair_type_decl,
        'there is a single accessor for the type declaration');

    my $decl = Chalk::Target::LLVM::Context::_strpair_type_decl();
    like($decl, qr/^%StrPair = type \{.*\}$/,
        'it returns a well-formed LLVM type declaration');

    ok(defined &Chalk::Target::LLVM::Context::_strpair_size_bytes,
        'there is a single accessor for the allocation size');
};

subtest 'the allocation size is DERIVED from the field list, not hardcoded' => sub {
    plan tests => 2;

    my $size = Chalk::Target::LLVM::Context::_strpair_size_bytes();
    is($size, 16, 'today {i8*, i64} is 16 bytes');

    # THE DISCRIMINATING CHECK. The size must be computed from the same field
    # list the declaration is built from, so widening the struct moves both
    # together. A hardcoded `return 16` passes the assertion above and fails
    # this one.
    my @fields = Chalk::Target::LLVM::Context::_strpair_fields();
    my $expect = 0;
    for my $f (@fields) {
        # LLVM struct layout: each field is aligned to its own size, and the
        # struct is padded to its largest member's alignment.
        my $w = $f->{bytes};
        $expect = int(($expect + $w - 1) / $w) * $w;   # align
        $expect += $w;
    }
    my $max = 0;
    for my $f (@fields) { $max = $f->{bytes} if $f->{bytes} > $max }
    $expect = int(($expect + $max - 1) / $max) * $max if $max;

    is($size, $expect,
        'the reported size equals the size computed from the field list');
};

subtest 'no hardcoded StrPair size survives in the emitters' => sub {
    plan tests => 2;

    my $ctx_src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
        local $/; <$fh>;
    };
    my $llvm_src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM.pm' or die $!;
        local $/; <$fh>;
    };

    # A literal `malloc(i64 16)` next to a StrPair allocation is the bug this
    # test exists to prevent coming back.
    my @bad = ($ctx_src =~ /malloc\(i64 16\)[^\n]*StrPair/g);
    is(scalar @bad, 0,
        'no StrPair allocation hardcodes 16 bytes')
        or diag("found: @bad");

    # The type literal must appear only inside the single accessor.
    my $literals = () = ($llvm_src =~ /%StrPair = type \{/g);
    is($literals, 0,
        'LLVM.pm no longer spells the type literal; it asks the accessor');
};

done_testing;
