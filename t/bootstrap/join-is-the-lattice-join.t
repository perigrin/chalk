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

subtest 'Boolean does NOT widen into the string chain' => sub {
    # This pinned `Boolean <: Str` on the argument that "perl's booleans ARE
    # the strings 1 and ''". They stringify to those strings; they are not
    # them. Measured on 5.42.0: is_bool("1") and is_bool("") are both FALSE,
    # while `"" . !!1` is "1" and `"" . !!0` is "". A stringification is not
    # an identity, and reading one as the other is substitutability mistaken
    # for membership -- which is exactly what the two-factor subtype test
    # exists to keep apart:
    #
    #     A <: B  iff  (A subset-of B) and (every op of B holds for A)
    #
    # Factor 2 passes: every string operation works on a boolean uncoerced.
    # Factor 1 fails, on `false`: it interprets directly as "" but as "0" via
    # Num, and no admissible detour preserves it. `true` DOES pass, so a
    # one-value probe reaches the wrong answer -- and Boolean has exactly two
    # inhabitants, so failing on `false` fails on half the type.
    #
    # perl-type-system-formal.md always said so ("Scalar contains values that
    # belong neither to Str nor to Num - including Boolean"). The lattice
    # contradicted its own spec until 2777bfa4; perl5-son found and fixed the
    # same inversion independently in 3da90cb.
    #
    # The full derivation, with the measurements, is in
    # t/bootstrap/lattice-edges-hold-in-perl.t and
    # t/bootstrap/ir/boolean-is-not-a-str.t.
    is Chalk::IR::Analysis::_join_repr('Boolean', 'Int'), 'Scalar',
        'Boolean joined with Int is Scalar -- they share no ancestor below it';

    # The other two string-spine joins move for the same reason. Asserted
    # rather than assumed: Num sits between Str and Int, so an edge change
    # that left it behind would not be a coherent lattice.
    is Chalk::IR::Analysis::_join_repr('Boolean', 'Str'), 'Scalar',
        'Boolean joined with Str is Scalar';
    is Chalk::IR::Analysis::_join_repr('Boolean', 'Num'), 'Scalar',
        'Boolean joined with Num is Scalar';

    # And the spine itself is untouched -- this was one edge, not a reshape.
    is Chalk::IR::Analysis::_join_repr('Int', 'Str'), 'Str',
        'Int joined with Str is still Str';
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

# The rule dispatch in _seed_and_propagate_reprs handles 'join' and everything
# else (a rule naming a fixed repr outright). It USED to carry a third arm,
# 'same' -- require both operand reprs to agree, yield that repr -- for And/Or.
# 6d9fc083 moved And/Or onto 'join', which is a strict superset of 'same', and
# nothing has mapped to 'same' since; the arm was unreachable code from that
# commit until it was deleted.
#
# No red test can exist for code nothing can reach, so this is the honest
# check: assert the table cannot revive the arm. If a rule ever needs
# agree-or-nothing semantics again, it comes back with a test that reaches it.
subtest 'the repr rule table names no rule the dispatch cannot run' => sub {
    my $src = do {
        open my $fh, '<', 'lib/Chalk/IR/Analysis.pm' or die "Analysis.pm: $!";
        local $/;
        <$fh>;
    };
    my ($table) = $src =~ /my \%_COMPUTED_REPR = \((.*?)\n\);/s
        or die 'could not find %_COMPUTED_REPR';

    # Strip comments -- the table's prose discusses 'same' at length, on purpose.
    (my $code = $table) =~ s/^\s*#.*$//mg;

    unlike $code, qr/=>\s*'same'/,
        q{no rule maps to 'same' -- the dispatch arm for it is gone};
};

done_testing;
