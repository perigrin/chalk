# ABOUTME: T1's coercion table must name exactly the conversions T2 can lower.
# ABOUTME: A pair T2 lowers but T1 denies is a lost lowering; the reverse is a late GAP.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Analysis;
use Chalk::Target::LLVM::Context;

# TWO TABLES, ONE CLAIMING TO MIRROR THE OTHER, NOTHING ENFORCING IT.
#
# `%_COERCIBLE_TO` (Analysis.pm) decides whether the loader INSERTS a Coerce
# node. Its own comment says it "mirrors the arms _lower_coerce implements".
# `_emit_coercion` (Context.pm) decides what the backend can actually lower.
# Nothing checked that the two agreed, and they did not:
#
#   T2 lowers Str->Int at Context.pm:2858 -- perl reads the string as a
#   number then truncates toward zero, so `int("3.9abc")` is 3.
#   T1 omitted it.
#
# The consequence is a LOST LOWERING, not a crash: Analysis.pm declines to
# insert the Coerce, the un-coerced operand travels on, and it GAPs downstream
# for a conversion the backend has had all along.
#
# BOTH DIRECTIONS OF DISAGREEMENT ARE DEFECTS, and they fail differently:
#
#   T1 yes / T2 no  -- the loader mints a Coerce the backend cannot lower,
#                      turning a clear type error into a confusing "not
#                      lowered runtime-free" GAP one layer too late. This is
#                      the direction the original comment worried about.
#   T2 yes / T1 no  -- a conversion that works is never attempted. Silent:
#                      nothing errors, the program simply GAPs later for the
#                      wrong reason. This is the direction that actually
#                      happened.
#
# ASK THE BACKEND, DO NOT GREP IT. Several pairs are lowered by shared paths
# (_emit_to_str for `* -> Str`, the %Slot tag dispatch) that no
# `$from eq X && $to eq Y` line names, so a grep over arms under-reports what
# T2 can do and would have made this test agree by accident.

my @SCALARS = qw(Int Num Str Boolean Undef);

# T2's real answer: try it and see whether it dies.
sub t2_lowers ($from, $to) {
    my $ctx = Chalk::Target::LLVM::Context->new;
    return eval { $ctx->_emit_coercion('%probe', $from, $to, 'mirror-probe'); 1 } ? 1 : 0;
}

# T1's answer, through its own public-ish predicate rather than a copy of the
# table -- a copy here would drift the same way the original pair did.
sub t1_admits ($from, $to) {
    return Chalk::IR::Analysis::_coercion_exists($from, $to) ? 1 : 0;
}

subtest 'every scalar pair agrees between T1 and T2' => sub {
    my (@t1_only, @t2_only);

    for my $from (@SCALARS) {
        for my $to (@SCALARS) {
            next if $from eq $to;
            my ($t1, $t2) = (t1_admits($from, $to), t2_lowers($from, $to));
            next if $t1 == $t2;
            push @{ $t1 ? \@t1_only : \@t2_only }, "$from->$to";
        }
    }

    is_deeply(\@t2_only, [],
        'no conversion the backend lowers is denied by T1 (a LOST LOWERING)')
        or diag("  T2 lowers but T1 refuses: @t2_only\n"
              . "  => the loader will not insert this Coerce, and the operand\n"
              . "     GAPs downstream for a conversion that works.");

    is_deeply(\@t1_only, [],
        'no conversion T1 admits is unlowerable by the backend (a LATE GAP)')
        or diag("  T1 admits but T2 cannot lower: @t1_only\n"
              . "  => the loader mints a Coerce that fails one layer later.");
};

# The specific pair that was wrong, asserted by name so the regression has a
# home rather than only being covered by the sweep above.
subtest 'Str->Int specifically' => sub {
    ok(t2_lowers('Str', 'Int'),
        'the backend lowers Coerce(Str->Int)');
    ok(t1_admits('Str', 'Int'),
        'and T1 admits it, so the loader will insert one');

    # Its neighbours, to show the shape is coherent: perl reads a string as a
    # number and then truncates, so Str->Int is Str->Num composed with
    # Num->Int rather than an independent rule.
    ok(t1_admits('Str', 'Num'), 'Str->Num, the first half');
    ok(t1_admits('Num', 'Int'), 'Num->Int, the second half');
};

# THE ABSENCES ARE A RULE, NOT A LIST. Of 20 ordered pairs, 16 are coercible
# and the 4 that are not all share a target: nothing coerces TO undef. Undef
# is a one-element type and no operation on a value produces it, so this is a
# statement about the type rather than four independent facts.
subtest 'nothing coerces to Undef, and that is the only exclusion' => sub {
    for my $from (grep { $_ ne 'Undef' } @SCALARS) {
        is(t1_admits($from, 'Undef'), 0, "$from does not coerce to Undef");
        is(t2_lowers($from, 'Undef'), 0, "and the backend does not lower it either");
    }
};

done_testing;
