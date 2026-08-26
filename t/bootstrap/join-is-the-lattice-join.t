# ABOUTME: `_join_repr` IS `TypeLibrary::join_types` folded over its arms -- a
# ABOUTME: total function on the lattice, with no second widening order of its own.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::IR::Analysis;
use Chalk::Grammar::Perl::TypeLibrary;

# _join_repr used to scan its own arms for one that is a supertype of all the
# others, returning undef when no arm dominates. That is a PARTIAL join: it can
# only ever answer with a type someone already named, so a pair whose least
# upper bound is neither arm (Undef and Int meet only at Scalar) came back
# undef -- read downstream as "inference failed" when the lattice had an answer
# all along.
#
# TypeLibrary::join_types is the total one, and it is the authority: the lattice
# lives in ONE file, and a second widening order in Analysis.pm is the same
# duplication %_REPR_RANK already was. _join_repr folds it left over the arms.
#
# The empty-arm `return undef` stays. No arms is not a join with an answer.

subtest 'a pair with no dominating arm still has a join' => sub {
    is Chalk::IR::Analysis::_join_repr('Undef', 'Int'), 'Scalar',
        'Undef and Int are siblings under Scalar -- the join is Scalar, not undef';

    is Chalk::IR::Analysis::_join_repr('ArrayRef', 'Int'), 'Scalar',
        'a reference and an Int join at Scalar';

    is Chalk::IR::Analysis::_join_repr('Array', 'Int'), 'List',
        'an aggregate and a scalar join at List, not Scalar';
};

subtest 'Boolean widens into the string chain' => sub {
    # PINNED DELIBERATELY. `Boolean <: Str` is INTENDED -- perigrin ruled on it
    # 2026-08-26. Perl's booleans ARE the strings "1" and "", and the lattice
    # says so. If this assertion ever fails, the lattice was changed; do NOT
    # "fix" it by making Boolean a sibling of the chain.
    is Chalk::IR::Analysis::_join_repr('Boolean', 'Int'), 'Str',
        'Boolean joined with Int is Str (Boolean <: Str is intended)';
};

subtest 'Slot has no place on the lattice, and the join says so' => sub {
    is Chalk::IR::Analysis::_join_repr('Slot', 'Int'), 'Unknown',
        'Slot shares no ancestor with Int -- Unknown, the pessimistic top';

    is Chalk::IR::Analysis::_join_repr('Slot', 'Slot'), 'Slot',
        'but two Slots are a Slot -- the equal-shortcut fires before absorption';

    is Chalk::IR::Analysis::_join_repr('Slot', 'Unknown'), 'Unknown',
        'and Unknown absorbs a Slot like anything else';
};

subtest 'no arms is not a join' => sub {
    is Chalk::IR::Analysis::_join_repr(), undef,
        'the empty fold returns undef, not a lattice element';
};

# The fold must BE join_types, not merely agree with it on the cases above.
subtest 'the fold agrees with the lattice on every pair of stamps' => sub {
    my @stamps = qw(Int Num Str Boolean Undef Object ArrayRef HashRef
                    Array Hash Slot Regex Scalar List Unknown None);
    my @disagree;
    for my $l (@stamps) {
        for my $r (@stamps) {
            my $got  = Chalk::IR::Analysis::_join_repr($l, $r);
            my $want = Chalk::Grammar::Perl::TypeLibrary::join_types($l, $r);
            push @disagree, "$l,$r: got @{[ $got // 'undef' ]} want $want"
                unless defined $got && $got eq $want;
        }
    }
    is \@disagree, [], 'every ordered pair folds to the lattice join';
};

done_testing;
