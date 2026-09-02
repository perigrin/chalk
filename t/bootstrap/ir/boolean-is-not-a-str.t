# ABOUTME: Boolean sits under Scalar, not under Str -- `false` is in neither Str nor Num.
# ABOUTME: Substitutability is not membership; the subtype test has two factors and Str fails one.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::Grammar::Perl::TypeLibrary;

# THE SUBTYPE TEST HAS TWO FACTORS:
#
#     A <: B  iff  (A subset-of B) and (every op of B holds for values of A)
#
# FACTOR 2 PASSES FOR Boolean <: Str, and it is why Boolean sat under Str for
# a long time. Every string operation works on a boolean with no coercion --
# measured on perl 5.42.0: "x".true."y".false."z" is "x1yz", length(true) is
# 1 and length(false) is 0, uc(true) is "1", true eq "1", false eq "".
# That is substitutability, and it is HALF the test.
#
# FACTOR 1 FAILS. Str membership asks whether some ADMISSIBLE detour type S
# preserves the value: exists S (S != Str) with C(v) == id_S(v). Measured:
#
#     false  direct Str  ""       via Num  "0"      DIFFER -> not preserved
#     true   direct Str  "1"      via Num  "1"      agree
#
# `true` passes. `false` does not, and one counterexample falsifies membership.
# S=Str against itself is inadmissible (vacuous -- it is the identity on every
# Str), and S=Boolean is inadmissible (circular: Str's definition would depend
# on Boolean, inverting the documented stratification Scalar -> Str -> Num ->
# Int). No admissible S preserves `false`, so Boolean is not a subset of Str.
#
# TESTING ONE VALUE GIVES THE WRONG ANSWER, which is why this file tests both.
# So does testing one factor.
#
# perl-type-system-formal.md already said so: "Scalar contains values that
# belong neither to Str nor to Num - including Boolean (true/false), Undef
# (undef), Ref (references), and DualVars". The implementation contradicted
# the spec; this aligns it. (perl5-son made the same correction in 3da90cb --
# a producer and consumer disagreeing on a subtype relation shows up as a
# coercion that fires on one side and not the other.)

subtest 'the falsifying values, measured rather than assumed' => sub {
    # Direct Str interpretation vs the Num detour, exactly as the membership
    # rule is stated. This is the evidence the lattice edge rests on, so it
    # lives in the test rather than only in a comment.
    no warnings 'numeric';
    my $false_direct = '' . !!0;
    my $false_detour = '' . ((!!0) + 0);
    my $true_direct  = '' . !!1;
    my $true_detour  = '' . ((!!1) + 0);

    is($false_direct, '',  'false interpreted directly as Str is ""');
    is($false_detour, '0', 'false via the Num detour is "0"');
    isnt($false_direct, $false_detour,
        'they DIFFER -- no admissible detour preserves false, so false is not in Str');

    # The trap: true agrees, so a one-value probe reaches the wrong conclusion.
    is($true_direct, $true_detour,
        'true DOES agree via Num -- which is why testing only `true` gets this wrong');
};

subtest 'Boolean is a Scalar and not a Str' => sub {
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Boolean', 'Scalar'),
        'Boolean <: Scalar');
    ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype('Boolean', 'Str'),
        'Boolean is NOT a subtype of Str');

    # Its siblings under Scalar: the other things in neither Str nor Num.
    for my $sib (qw(Undef DualVar Ref)) {
        ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype($sib, 'Scalar'),
            "$sib <: Scalar (Boolean's sibling)");
        ok(!Chalk::Grammar::Perl::TypeLibrary::is_subtype($sib, 'Str'),
            "$sib is NOT a Str either");
    }

    # Str itself is unmoved -- this changes ONE edge, not the spine.
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Num', 'Str'), 'Num <: Str still');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Int', 'Num'), 'Int <: Num still');
    ok(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Str', 'Scalar'), 'Str <: Scalar still');
};

# THE JOINS ARE WHAT CONSUMERS ACTUALLY READ, and they are the reason this
# matters beyond tidiness: join(Boolean, Int) = Str invited a consumer to
# treat `-c $f` and `length $x` as the same kind of thing. They have no common
# type below Scalar.
subtest 'a Boolean joined with a string-spine type is a Scalar' => sub {
    for my $other (qw(Int Num Str)) {
        is(Chalk::Grammar::Perl::TypeLibrary::join_types('Boolean', $other), 'Scalar',
            "join(Boolean, $other) = Scalar");
        is(Chalk::Grammar::Perl::TypeLibrary::join_types($other, 'Boolean'), 'Scalar',
            "join($other, Boolean) = Scalar -- and it commutes");
    }

    # Already siblings by another route; unchanged, and asserted so a future
    # edit that moves Undef is caught here too.
    is(Chalk::Grammar::Perl::TypeLibrary::join_types('Boolean', 'Undef'), 'Scalar',
        'join(Boolean, Undef) = Scalar (unchanged)');

    # The string spine still joins among itself -- if this moved, the change
    # would be wider than one edge.
    is(Chalk::Grammar::Perl::TypeLibrary::join_types('Int', 'Str'), 'Str',
        'join(Int, Str) = Str -- the spine is untouched');
    is(Chalk::Grammar::Perl::TypeLibrary::join_types('Int', 'Num'), 'Num',
        'join(Int, Num) = Num -- the spine is untouched');
};

done_testing;
