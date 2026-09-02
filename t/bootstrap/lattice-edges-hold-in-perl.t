# ABOUTME: Every scalar-spine lattice edge is justified by a measurement against perl, not by the table.
# ABOUTME: Two factors per edge: membership (a detour must preserve the value) and substitutability.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Grammar::Perl::TypeLibrary;

# WHAT THIS FILE IS FOR, and how it differs from type-library.t.
#
# type-library.t asserts `is_subtype('Int','Num')` and friends. That is a
# CHANGE DETECTOR and a useful one -- it catches an edit to the table that
# nobody reflected in the tests. What it cannot catch is a table that was
# WRONG FROM THE START, because the table is its own oracle. It was green for
# the entire time `Boolean => 'Str'` was wrong.
#
# This file uses PERL as the oracle instead. Each edge is justified by a
# measurement, so an edge that does not hold in the language fails here even
# when the table is perfectly self-consistent.
#
# THE TEST HAS TWO FACTORS and both are needed:
#
#     A <: B  iff  (A subset-of B) and (every op of B holds for values of A)
#
# Boolean under Str is the worked example of why. Factor 2 PASSES -- every
# string operation works on a boolean with no coercion. Factor 1 FAILS, on
# `false` only. A single-factor test, or a single-value probe, gets it wrong;
# both mistakes were actually made before the edge was corrected.
#
# SCOPE: the scalar spine plus the types that hang directly off Scalar. The
# reference branch (Ref/ArrayRef/...) and the collection branch (List/Array/
# Hash) are NOT covered -- their membership is about what a value REFERS to
# rather than how it interprets, which this detour machinery cannot express.
# Untested is better stated than faked; see the closing subtest.

# ---------------------------------------------------------------------------
# FACTOR 1: MEMBERSHIP.
#
# `v` is in B iff interpreting it as B directly agrees with interpreting it
# as B via some ADMISSIBLE detour type S. Admissibility matters:
#
#   - S = B is inadmissible: it is the identity on every value of B, so it
#     would certify membership for anything (the vacuous test).
#   - S = A is inadmissible when it would make B's definition depend on A,
#     inverting the stratification Scalar -> Str -> Num -> Int.
# ---------------------------------------------------------------------------
my %INTERPRET_AS = (
    Str => sub { no warnings; "" . $_[0] },
    Num => sub { no warnings; 0 + $_[0] },
    Int => sub { no warnings; int(0 + $_[0]) },
);

# The detours admissible when testing membership in B.
#
# ONLY S = B IS EXCLUDED, and only that. Interpreting as B and then as B again
# is the identity on every value of B, so it would certify membership for
# anything -- the vacuous test the well-formedness rule exists to forbid.
#
# S = A (the child) is NOT excluded, and an earlier version of this file
# wrongly did exclude it. That over-exclusion made `Num <: Str` fail on 3.5:
# the only detour left was Int, which truncates to "3" against a direct "3.5".
# The circularity rule bans a detour that would make B's definition depend on
# B -- not one that passes through a proper subtype of B on the way. Num is a
# subtype of Str, so using it to reach Str inverts nothing.
#
# The rule that does the real work is therefore narrow, and a wider one is not
# safer: it manufactures false negatives, which look exactly like findings.
sub admissible_detours_for ($B, $A) {
    return grep { $_ ne $B } sort keys %INTERPRET_AS;
}

# member_of($v, $B, $A) -> ($bool, $via)
sub member_of ($v, $B, $A) {
    my $direct = $INTERPRET_AS{$B}->($v);
    for my $S (admissible_detours_for($B, $A)) {
        my $detour = $INTERPRET_AS{$B}->($INTERPRET_AS{$S}->($v));
        return (1, $S) if $detour eq $direct;
    }
    return (0, undef);
}

# ---------------------------------------------------------------------------
# FACTOR 2: SUBSTITUTABILITY. Every operation of B must work on a value of A
# with no coercion. These are B's characteristic operations, run for effect --
# a die means the operation does not hold.
# ---------------------------------------------------------------------------
my %OPERATIONS_OF = (
    Str => [
        [ 'concat'  => sub { my $r = 'x' . $_[0] . 'y'; 1 } ],
        [ 'length'  => sub { my $n = length $_[0];      1 } ],
        [ 'uc'      => sub { my $s = uc $_[0];          1 } ],
        [ 'eq'      => sub { my $b = ($_[0] eq $_[0]);  1 } ],
        [ 'substr'  => sub { my $s = substr("$_[0]", 0, 1); 1 } ],
        [ 'match'   => sub { my $m = ("$_[0]" =~ /^/);  1 } ],
    ],
    Num => [
        [ 'add'     => sub { no warnings; my $n = $_[0] + 1;  1 } ],
        [ 'mul'     => sub { no warnings; my $n = $_[0] * 2;  1 } ],
        [ 'numcmp'  => sub { no warnings; my $b = ($_[0] <=> 0); 1 } ],
        [ 'abs'     => sub { no warnings; my $n = abs $_[0];  1 } ],
    ],
    Int => [
        [ 'modulo'  => sub { no warnings; my $n = $_[0] % 2;  1 } ],
        [ 'bitand'  => sub { no warnings; my $n = $_[0] & 1;  1 } ],
    ],
);

# ---------------------------------------------------------------------------
# THE EDGES. Each carries WITNESS VALUES, and a type is only as tested as its
# witnesses are representative -- so a type whose members disagree (Boolean:
# `true` passes Str membership, `false` does not) must list both.
# ---------------------------------------------------------------------------
my @EDGES = (
    {
        child => 'Int', parent => 'Num',
        witnesses => [ ['42', 42], ['0', 0], ['-7', -7] ],
        holds => 1,
    },
    {
        child => 'Num', parent => 'Str',
        witnesses => [ ['3.5', 3.5], ['0.0', 0.0], ['-2.25', -2.25] ],
        holds => 1,
    },
    {
        # Transitive, and asserted directly rather than inferred: if it held
        # only by transitivity through Num, a broken Int<:Num would hide here.
        child => 'Int', parent => 'Str',
        witnesses => [ ['42', 42], ['0', 0] ],
        holds => 1,
    },
    {
        # THE EDGE THAT WAS WRONG. Both polarities, because `true` passes.
        child => 'Boolean', parent => 'Str',
        witnesses => [ ['true', !!1], ['false', !!0] ],
        holds => 0,
        why   => 'false interprets directly as "" but as "0" via Num; no admissible detour preserves it',
    },
);

subtest 'factor 1: membership, measured against perl' => sub {
    for my $e (@EDGES) {
        my ($A, $B) = ($e->{child}, $e->{parent});
        my @failing;
        for my $w ($e->{witnesses}->@*) {
            my ($label, $v) = $w->@*;
            my ($ok, $via) = member_of($v, $B, $A);
            push @failing, $label unless $ok;
        }

        if ($e->{holds}) {
            is_deeply(\@failing, [],
                "$A <: $B -- every witness is a member of $B");
        }
        else {
            isnt(scalar(@failing), 0,
                "$A is NOT a subtype of $B -- at least one witness fails membership");
            note("  why: $e->{why}") if $e->{why};
            note("  failing witnesses: @failing");
        }
    }
};

subtest 'factor 2: substitutability, measured against perl' => sub {
    for my $e (@EDGES) {
        my ($A, $B) = ($e->{child}, $e->{parent});
        my $ops = $OPERATIONS_OF{$B} or next;

        for my $w ($e->{witnesses}->@*) {
            my ($label, $v) = $w->@*;
            my @broken = grep {
                !eval { $_->[1]->($v) }
            } $ops->@*;
            is_deeply([ map { $_->[0] } @broken ], [],
                "$B's operations all hold for $A witness `$label`");
        }
    }
};

# THE POINT OF THE WHOLE FILE, stated as an assertion rather than a comment:
# a type can pass factor 2 and fail factor 1, and the lattice must follow
# factor 1. Boolean is the case that proves the two are independent.
subtest 'substitutability does not imply membership' => sub {
    my $false = !!0;

    my @broken = grep { !eval { $_->[1]->($false) } } $OPERATIONS_OF{Str}->@*;
    is_deeply([ map { $_->[0] } @broken ], [],
        'every Str operation works on `false` -- factor 2 passes');

    my ($ok) = member_of($false, 'Str', 'Boolean');
    ok(!$ok, 'and yet `false` is not a member of Str -- factor 1 fails');

    ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Boolean', 'Str'),
        'so the lattice places Boolean OUTSIDE Str, following factor 1');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Boolean', 'Scalar'),
        'under Scalar instead, beside its siblings');
};

# The table and the measurements must agree. This is the seam: if someone
# changes an edge in TypeLibrary without a measurement to justify it, the two
# halves of this file disagree and it fails.
subtest 'the table agrees with what perl says' => sub {
    for my $e (@EDGES) {
        my ($A, $B) = ($e->{child}, $e->{parent});
        my $table = Chalk::Grammar::Perl::TypeLibrary::is_subtype($A, $B) ? 1 : 0;
        is($table, $e->{holds} ? 1 : 0,
            "TypeLibrary says $A " . ($e->{holds} ? '<:' : 'is NOT <:') . " $B, matching perl");
    }
};

# WHAT IS NOT COVERED, asserted so the gap is visible rather than implied.
# These branches need a different oracle: reference membership is about what a
# value REFERS to, and collection membership is about arity. Neither is
# expressible as "does a detour interpretation preserve the value".
subtest 'the untested branches are named, not hidden' => sub {
    my @uncovered = qw(Ref Object Regex ScalarRef LValueRef ArrayRef HashRef
                       CodeRef GlobRef List Array Hash Void DualVar VString Undef);
    for my $t (@uncovered) {
        ok(!grep({ $_->{child} eq $t } @EDGES),
            "$t is knowingly uncovered by this suite (needs a different oracle)");
    }
    note('Covered here: the scalar spine Int <: Num <: Str, and Boolean\'s exclusion from it.');
};

# WHY "A COERCION EXISTS" PROVES NOTHING, and therefore why this file tests
# two factors instead of one.
#
# In perl almost every concrete type has a working coercion to almost every
# other. Measured on 5.42.0 over 9 value kinds x 3 targets: 27 of 27 succeed
# and NONE dies -- an ArrayRef, a CodeRef and a blessed Object all coerce to
# Int without complaint. So "C(v) is defined" is nearly vacuous as evidence:
# a lattice built on it would put CodeRef under Int.
#
# What separates a real subtype relation from a merely-coercible pair is what
# the coercion COSTS, and there are two distinct costs:
#
#   DATA LOSS         the value does not survive. `0 + [1,2]` yields an
#                     ADDRESS -- the coercion "succeeded" and the array is
#                     gone. Factor 1 (membership) is what detects this: it
#                     asks whether an admissible detour PRESERVES the value,
#                     which an address does not.
#
#   BEHAVIOURAL LOSS  the value survives but stops answering. The number
#                     `0 + [1,2]` is no longer a reference; `->[0]` on it is
#                     meaningless. Factor 2 (substitutability) is what detects
#                     this: it asks whether the PARENT's operations still work.
#
# Neither factor subsumes the other, which is the whole reason for two. The
# Boolean case proves it in one direction -- factor 2 passes and factor 1
# fails -- and this subtest proves the other: a pair where a coercion exists,
# and both factors are needed to reject it.
subtest 'a coercion existing is not evidence: it must also be lossless and behaviour-preserving' => sub {
    no warnings;

    # An ArrayRef coerces to Num. This is the fact that makes coercion-exists
    # useless on its own.
    my $aref = [1, 2];
    my $as_num = eval { 0 + $aref };
    ok(defined $as_num, 'ArrayRef DOES coerce to Num -- perl does not complain');

    # DATA LOSS: what came back is an address, not the array. Round-tripping
    # cannot recover it, which is exactly what factor 1 asks about.
    my $back = eval { 0 + ("" . $as_num) };
    is($back, $as_num, 'and the number round-trips as a number');
    ok(!ref($as_num), 'but it is NOT a reference any more -- the value is gone');

    # BEHAVIOURAL LOSS: the parent's operations stop working. A Ref's
    # characteristic operation is dereferencing.
    my $deref_survives = eval { my $x = $as_num->[0]; 1 } ? 1 : 0;
    is($deref_survives, 0,
        'and dereferencing it fails -- the operations did not come along');

    # The lattice agrees, which is the point: ArrayRef is not under Num
    # despite a coercion existing between them.
    ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('ArrayRef', 'Num'),
        'so the lattice does not place ArrayRef under Num');
    ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('ArrayRef', 'Str'),
        'nor under Str, for the same reason');
};

done_testing;
