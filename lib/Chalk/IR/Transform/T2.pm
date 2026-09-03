# ABOUTME: T2 rewrites a Chalk-typed graph into an LLVM-typed one, in place.
# ABOUTME: A narrowing analysis, not a table: a stamp is a SET of candidates.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Scalar::Util qw(blessed);

class Chalk::IR::Transform::T2 {

    # T2 IS A NARROWING ANALYSIS, NOT A TYPE MAPPING. perigrin, stating the
    # design (docs/plans/2026-08-31-t2-is-a-narrowing-analysis.md):
    #
    #   "T2 needs to do a type mapping from a Chalk type to an LLVM type but
    #    the types aren't 1:1 ... Num for example is the parent type of Int so
    #    a Num maps to double|i64 and then T2 does narrowing passes to get a
    #    single representation type."
    #
    # A stamp names a type AND EVERYTHING BELOW IT on the lattice, so it
    # denotes a SET of candidate machine types:
    #
    #     Scalar -> everything below, or %Slot    narrowing, else box
    #     Str    -> {%Str, double, i64...}        is it ever rendered?
    #     Num    -> {double, i64...}              is it ever fractional?
    #     Int    -> {i8,u8,...,i64,u64}           sign and range
    #
    # NOTHING ON THE SPINE IS ALREADY CONCRETE. `Str` is not a leaf -- it is
    # second-widest, `Str :> Num` -- and `Int` is not one either, since a
    # bounded positive value could be u8. An earlier draft bucketed Int/Str as
    # "already decided", which would have made this a lookup table with a
    # rounding error.
    #
    # IT COSTS NO NEW FIELD. Node declares ONE stamp field and
    # `representation()` is a read alias over it. So this does not add a slot;
    # it CHANGES WHAT THE ONE FIELD HOLDS -- Chalk type before, LLVM type
    # after, this pass as the boundary. That gives the invariant checker a
    # sharp question: not "is this stamp sound?" but "which vocabulary is this
    # graph in?", and a Chalk name surviving T2 is a T2 bug findable without
    # reasoning about the program at all.

    # SCOPE: THE SPINE COLLAPSE, and only that. Width and sign selection are
    # designed toward and not built -- they need an interval lattice, a
    # widening operator at loop Phis, and sign tracking, none of which exist.
    # Until then `Int` answers `i64` unconditionally.
    #
    # THE SEAM THAT KEEPS THAT HONEST: `_candidates` asks the stamp for its
    # candidate SET and `_choose` picks from it. Adding intervals later shrinks
    # Int's set without changing the pass's shape. A hash literal mapping
    # Int => 'i64' would express none of that, and building one now would bake
    # in the pre-narrowed assumption this split exists to remove.
    our %CANDIDATES = (
        # Decidable today: one candidate, so narrowing is trivially done.
        Boolean  => ['i1'],
        Undef    => ['i1'],
        Object   => ['i8*'],
        ArrayRef => ['i8*'],
        HashRef  => ['i8*'],
        CodeRef  => ['i8*'],
        Array    => ['%Array*'],
        Hash     => ['%Hash*'],

        # THE SPINE. Each names its type and everything below it, so each has
        # more than one candidate and needs a real choice.
        Int      => ['i64'],                       # until intervals: one
        Num      => ['double', 'i64'],
        Str      => ['%Str', 'double', 'i64'],
        Scalar   => ['%Slot', '%Str', 'double', 'i64'],
    );

    # Types that are NOT value types, and so have no machine type at any width.
    # Distinguished from "not yet narrowed": these can never be narrowed,
    # because there is nothing to narrow to.
    our %NOT_A_VALUE = (
        List => "'List' is signature vocabulary -- it answers 'what does this "
              . "parameter position accept?' and denotes a SEQUENCE, so no "
              . "single-value layout exists at any width",
        None => "'None' is the lattice BOTTOM, the empty type, inhabited by "
              . "nothing -- there is no value to lay out",
        Void => "'Void' is arity 0: a position that yields no value, so there "
              . "is nothing to give a layout to",
    );

    # run(\%graphs) -> void. Rewrites every node's stamp in place.
    #
    # IN PLACE, not a copy, because the stamp field is the same slot before and
    # after -- see the no-new-field note above. The graph identity is preserved
    # so every consumer holding a node reference sees the narrowed type.
    sub run ($class, $graphs) {
        for my $gname (sort keys %$graphs) {
            my %seen;
            for my $node ($graphs->{$gname}->nodes->@*) {
                next unless blessed($node);
                next if $seen{ $node->id }++;
                $class->_narrow_node($node, $gname);
            }
        }
        return;
    }

    # _narrow_node($node, $gname) -> void. One node's Chalk stamp becomes its
    # LLVM type, or T2 refuses and says why.
    sub _narrow_node ($class, $node, $gname) {
        my $stamp = $node->stamp;

        # An UNSTAMPED node is not T2's failure to report: inference never
        # reached it, which is a T1 gap. Left alone so the existing NO-REPR
        # diagnostics keep naming the right pass.
        return unless defined $stamp;

        # ALREADY AN LLVM TYPE. `run` is idempotent, and a graph may hold nodes
        # a previous phase narrowed. Recognised by not being a Chalk lattice
        # name rather than by a marker, so nothing has to be threaded.
        return unless exists $CANDIDATES{$stamp}
                   || exists $NOT_A_VALUE{$stamp}
                   || $stamp eq 'Unknown';

        if (my $why = $NOT_A_VALUE{$stamp}) {
            die "T2: cannot narrow '$stamp' in $gname (op="
              . $node->operation . "): $why. Reaching T2 with it means "
              . "non-value vocabulary leaked into the value pipeline.\n";
        }

        # UNKNOWN IS T2 REPORTING ITS OWN FAILURE, and that is the point of
        # moving the die here. Under the old backend-side table this was an
        # emission-time error blaming TypeInference -- the pre-split model
        # showing through, treating a missing narrowing as a T1 bug when the
        # narrowing is T2's job. Now it is reported where the decision is made,
        # with the graph still in hand.
        if ($stamp eq 'Unknown') {
            die "T2: cannot narrow 'Unknown' in $gname (op="
              . $node->operation . "). Unknown is the lattice TOP -- inference "
              . "ran and could not determine this node, so there is no "
              . "candidate set to choose from. This is T2 failing to narrow, "
              . "not a missing table entry.\n";
        }

        $node->set_stamp($class->_choose($node, $stamp));
        return;
    }

    # _choose($node, $stamp) -> the single LLVM type.
    #
    # THE DECISION PROCEDURE. Today it takes the head of the candidate list,
    # which is the widest safe choice for each spine member -- and that is
    # exactly what "nothing has been proven" means. It is written as a choice
    # over a set rather than a lookup so that adding evidence (an interval, a
    # use-site scan) changes THIS function and nothing else.
    #
    # `%Slot` for an unnarrowed Scalar is the FALLBACK, not the goal: the boxed
    # cell you are forced into when nothing was proven. A Scalar that T2 could
    # prove is only ever Int should lower as i64 -- that proof needs intervals
    # and is out of scope, so it boxes.
    sub _choose ($class, $node, $stamp) {
        my $candidates = $CANDIDATES{$stamp}
            or die "T2: no candidate set for '$stamp' (op="
                 . $node->operation . ")\n";
        return $candidates->[0];
    }
}
