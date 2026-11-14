# ABOUTME: Stringifying undef yields "" -- perl's answer, and a constant one.
# ABOUTME: Undef is the unit type; Unknown is refused -- untyped is not undef.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::Target::LLVM::Context;

# `print undef` prints the empty string. That is perl's answer, and it needs no
# runtime work: `Undef` is a UNIT TYPE, so there is exactly one value to render
# and the result is a compile-time constant.
#
# Both `Undef` and `Unknown` reached _emit_to_str's final die and GAPped:
#
#   GAP: Coerce[Unknown->Str] is not lowered runtime-free (Int, Boolean, Num,
#   Slot and Str are wired; an aggregate has no stringification)
#
# -- which is wrong twice over. Neither is an aggregate, and both have a known
# stringification. The message was written for the aggregate case and swept up
# two scalars that simply had no arm.
#
# They are kept as SEPARATE arms even though both emit "", because they are not
# the same claim:
#
#   Undef   -- this value IS undef. The empty string is its stringification.
#   Unknown -- inference never typed this. "" is right only because a value
#              that reaches stringification untyped can only be treated as
#              perl treats undef; it is a fallback, not a stringification.
#
# The lattice keeps them distinct for exactly that reason (Serialize/JSON.pm:
# "Scalar is a legitimate static answer, Unknown is an inference failure"), and
# collapsing them here would erase the distinction at the one place it becomes
# observable.
#
# UNKNOWN IS NOW REFUSED (2026-10-23). The fallback's premise -- that an
# untyped value reaching stringification can only be undef -- was measured
# false: an inlined `my $y = $n; if ($n) { $y = 9 } return $y` folds to a
# ternary stamped Unknown, and "" was printed for perl's 9. A fallback a wrong
# answer can hide behind is a miscompile, so the arm names the gap instead.

sub emitted ($ctx) {
    return join "\n", map { ( $_->{insts} // [] )->@* }
        ( $ctx->{blocks} // [] )->@*;
}

subtest 'Undef stringifies to the empty string' => sub {
    my $ctx = Chalk::Target::LLVM::Context->new;
    my $ptr = $ctx->_emit_to_str('Undef', '%unused', 'Stringify[Undef]');
    ok defined $ptr, 'it returns a value rather than dying';

    unlike emitted($ctx), qr/\bcall\b/,
        'no runtime call -- a unit type renders at compile time';
};

subtest 'Unknown is refused, not rendered as the empty string' => sub {
    my $ctx = Chalk::Target::LLVM::Context->new;
    my $ptr = eval { $ctx->_emit_to_str('Unknown', '%unused', 'Coerce[Unknown->Str]') };
    ok !defined $ptr, 'no string is made up for it';
    like $@, qr/^GAP: .*Unknown/, 'refused, naming the lattice TOP';
};

subtest 'the length travels with the pointer' => sub {
    # Every arm of _emit_to_str must carry its pointer's byte length: a Str is
    # a (ptr, len) pair, and a consumer slicing an unrecorded length off a
    # shared "" global is how the Boolean arm once printed a stray byte of "1".
    # An empty string's length is 0, and 0 must be carried like any other.
    #
    # `%Str` is an aggregate, so the parts come back as SSA refs rather than
    # literals -- the assertion is that BOTH exist and the length is extracted
    # from the value, not looked up beside it.
    my $ctx = Chalk::Target::LLVM::Context->new;
    my $val = $ctx->_emit_to_str('Undef', '%unused', 'Stringify[Undef]');
    my ($ptr, $len) = $ctx->_str_parts($val);
    ok defined $ptr && defined $len, 'both halves come back';
    like emitted($ctx), qr/insertvalue %Str/,
        'the length rides IN the %Str value';
};

subtest 'a reference reads as perl prints it; what has no reading still refuses' => sub {
    # An ArrayRef once had no stringification here and refused. It has one
    # now (bb521c53): perl prints `ARRAY(0x...)`, Class= in front when
    # blessed, and so does this arm.
    my $ctx = Chalk::Target::LLVM::Context->new;
    my $val = $ctx->_emit_to_str('ArrayRef', '%a', 'Coerce[ArrayRef->Str]');
    ok defined $val, 'an ArrayRef is rendered, not refused';
    like emitted($ctx), qr/"ARRAY"/, 'as ARRAY(0x...)';

    # The arms above must not have widened the die into a catch-all. Void has
    # no value to read, and that refusal is correct.
    my $vctx = Chalk::Target::LLVM::Context->new;
    my $err = dies { $vctx->_emit_to_str('Void', '%v', 'Coerce[Void->Str]') };
    like $err, qr/^GAP: .*no stringification/, 'Void refuses, saying why';
};

done_testing;
