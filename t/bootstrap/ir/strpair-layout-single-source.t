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
    like($decl, qr/^%Str = type \{.*\}$/,
        'it returns a well-formed LLVM type declaration');

    # THE SIZE ACCESSOR IS GONE ON PURPOSE, and this assertion outlived it.
    # `_strpair_size_bytes` computed the struct size IN PERL -- a second
    # implementation of LLVM's alignment rules, which is the very duplication
    # this file exists to forbid. It was replaced by `_sizeof_llvm_type`, which
    # emits a `ptrtoint getelementptr null` constant expression and lets LLVM
    # compute it from the declaration, so the size CANNOT drift from the struct.
    #
    # The old assertion was never updated and had been dying with "Undefined
    # subroutine" ever since -- measured identical at session-start HEAD, so
    # this guard was dead for the whole time the migration was relying on it.
    ok(defined &Chalk::Target::LLVM::Context::_sizeof_llvm_type,
        'there is a single accessor for the allocation size');
};

subtest 'the allocation size is DERIVED by LLVM, not computed here' => sub {
    plan tests => 3;

    # _sizeof_llvm_type emits a constant EXPRESSION rather than a number: LLVM
    # evaluates it against the type declaration in the same module, so the two
    # cannot disagree. That is strictly better than agreeing-by-test, which is
    # what the previous version of this subtest checked (and what a perl-side
    # re-implementation of LLVM's alignment rules can only ever approximate).
    my $expr = Chalk::Target::LLVM::Context::_sizeof_llvm_type('%Str');

    like($expr, qr/\bptrtoint\b/,
        'the size is a ptrtoint constant expression, not a literal');
    like($expr, qr/\%Str/,
        'and it is computed from the %Str type itself');
    unlike($expr, qr/\b\d+\b(?!\s*\))/,
        'no bare byte count is baked into it');
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
