# ABOUTME: Which coercions are LEGAL is a T1 fact; T2 must implement each or refuse by name.
# ABOUTME: A legal coercion T2 silently cannot lower is a functor hole, not an illegal coercion.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Analysis;
use Chalk::Target::LLVM::Context;

# WHICH COERCIONS ARE LEGAL IS ENTIRELY A T1 QUESTION. `Str -> Int` is legal
# because perl reads a string as a number and truncates toward zero --
# `int("3.9abc")` is 3. That is a fact about the language's type system and it
# holds whether or not any backend exists to lower it.
#
# SO THE DEPENDENCY RUNS ONE WAY. T1 states the legal conversions; T2's job is
# to implement each one, or to refuse it BY NAME with a reason. T2 having no
# arm for a legal coercion is a hole in the functor -- it is not evidence that
# the coercion is illegal, and T1 must not be edited to match T2's gaps. This
# file is therefore NOT "make the two tables equal"; it is "every legal
# coercion is either lowered or explicitly refused".
#
# The version of this test written first had that backwards, asserting T1 must
# name exactly what T2 lowers, which would let a missing backend arm silently
# delete a legal conversion from the type system (perigrin, 2026-09-02).
#
# `%_COERCIBLE_TO` (Analysis.pm) decides whether the loader INSERTS a Coerce
# node. `_emit_coercion` (Context.pm) decides what the backend can lower.
# Nothing checked that every legal coercion had an implementation, and one did
# not:
#
#   T2 lowers Str->Int at Context.pm:2858 -- perl reads the string as a
#   number then truncates toward zero, so `int("3.9abc")` is 3.
#   T1 omitted it.
#
# The consequence is a LOST LOWERING, not a crash: Analysis.pm declines to
# insert the Coerce, the un-coerced operand travels on, and it GAPs downstream
# for a conversion that works.
#
# IT WENT STALE RATHER THAN BEING WRONG WHEN WRITTEN. The table was authored
# 2026-08-26 (f92c6869) and was accurate then; the backend GAINED the Str->Int
# arm on 2026-08-31 (91d50c1b), added for the %Slot tag dispatch. Nothing
# linked them, so one side moved and the other did not -- which is the failure
# mode two unlinked tables produce, and a better argument for this test than
# "someone forgot a row".
#
# BOTH DIRECTIONS ARE DEFECTS, but they are defects in DIFFERENT LAYERS:
#
#   legal, not lowered  -- a T2 HOLE. The loader mints a Coerce the backend
#                          cannot emit, and it fails one layer late with a
#                          message about lowering rather than about types.
#                          The fix belongs in T2: implement the arm, or refuse
#                          it by name so the reason is legible.
#   lowered, not legal  -- a T1 OMISSION. The backend can do it and the type
#                          system never asks, so the conversion is never
#                          attempted. Silent: nothing errors, the program GAPs
#                          later blaming the wrong thing. This is what
#                          happened with Str->Int.
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
        'T1 OMISSION: no conversion the backend lowers is missing from the type system')
        or diag("  T2 lowers but T1 refuses: @t2_only\n"
              . "  => the loader will not insert this Coerce, and the operand\n"
              . "     GAPs downstream for a conversion that works.");

    # A legal coercion this target cannot lower is a PARTIALITY, and the
    # obligation is to NAME it, not necessarily to close it. T2 is a functor
    # into a category that need not be total over the source -- we map the
    # arrows we can map -- so an unmapped arrow is a legitimate outcome
    # provided it is stated. What is not legitimate is silence: an unnamed
    # gap fails late and blames the type layer for a target's limit.
    #
    # _repr_to_llvm_type already offers exactly this choice in its own
    # message -- "add it to %_REPR_LLVM_TYPE with its machine type, or to
    # %_REPR_NO_MACHINE_TYPE with the reason it has none". This assertion is
    # the same demand one level up, for arrows rather than objects.
    #
    # Either way the fix is in the TARGET. T1 is never edited down to fit a
    # backend's gaps; a second target with different limits must not be able
    # to change what perl does.
    is_deeply(\@t1_only, [],
        'T2 HOLE: every legal coercion has an implementation in this target')
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

    # NO DEPTH RULE EXPLAINED THE OMISSION, and that is worth pinning because
    # it is the charitable reading and it is false. Had the table followed
    # "coerce only to a direct child", Str->Num (one step) present and
    # Str->Int (two steps) absent would be consistent. But Int->Str skips the
    # SAME two levels in the other direction and was present. Five of the six
    # ordered spine pairs were there; the sixth was a hole, not a rule.
    for my $pair (['Int','Num'], ['Int','Str'], ['Num','Int'],
                  ['Num','Str'], ['Str','Int'], ['Str','Num']) {
        my ($a, $b) = $pair->@*;
        ok(t1_admits($a, $b),
            "$a->$b: the scalar spine is coercible in every direction");
    }
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
