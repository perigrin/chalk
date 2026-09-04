# ABOUTME: T2 rewrites a Chalk-typed graph into an LLVM-typed one, in place.
# ABOUTME: A narrowing analysis, not a table: a stamp is a SET of candidates.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Scalar::Util qw(blessed);
use Chalk::IR::Value;   # narrow_num tests operands with isa

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
    # THE MAPPING IS INJECTIVE, AND THAT IS A DESIGN REQUIREMENT, not an
    # accident of which names were free.
    #
    # `Boolean` and `Undef` both denote one bit and would both answer `i1`;
    # `ArrayRef`, `HashRef`, `CodeRef` and `Object` are all boxed pointers and
    # would all answer `i8*`. Collapsed that way, a consumer holding `i1`
    # cannot tell which type it had -- so a site asking "is this an Undef?"
    # starts firing on Booleans too, silently. A check meaning two things at
    # once is the failure mode this codebase keeps recording.
    #
    # LLVM ENFORCES THE DISTINCTION FOR FREE, because named struct types are
    # NOMINAL. Measured against lli-15:
    #
    #     %Bool  = type { i1 }
    #     %Undef = type { i1 }
    #     ... extractvalue %Undef %b
    #     -> error: '%b' defined with type '%Bool = type { i1 }' but expected
    #        '%Undef = type { i1 }'
    #
    # Two structurally identical types stay distinct and mixing them is a
    # VERIFIER error rather than a silent pass. The backend already depends on
    # this for %Str, %Slot, %Array and %Hash -- these brands only apply it
    # consistently.
    #
    # THE COST HAS A TRIVIAL INVERSE, which is why it is not really a cost. A
    # branded value is a struct wrapping its payload, so it costs an
    # insertvalue/extractvalue pair. perigrin: "even if LLVM's optimizer didn't
    # we could trivially write a post-T2 optimizer that did unwind them" --
    # unwrapping a single-field struct needs no analysis at all. So the brand
    # is a COMPILE-TIME fact that has done its job the moment T2's output is
    # checked, and correctness never depends on the unwrapping happening.
    # (LLVM's own optimizer flattens single-field structs routinely, so the
    # pass may never need writing; that is a measurement, not an assumption.)
    our %CANDIDATES = (
        # Decidable today: one candidate, so narrowing is trivially done.
        # BRANDED where the underlying machine type is shared -- see above.
        Boolean  => ['%Boolean'],    # { i1 }, distinct from Undef
        Undef    => ['%Undef'],      # { i1 }, distinct from Boolean
        Object   => ['%Object*'],
        ArrayRef => ['%ArrayRef*'],
        HashRef  => ['%HashRef*'],
        CodeRef  => ['%CodeRef*'],
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

    # llvm_type_for($chalk_type) -> the LLVM type a DECLARED type narrows to.
    #
    # THE MOP IS NOT REWRITTEN, DELIBERATELY. A field's declared type, a
    # method's return type and a sub's are the program's own view of itself,
    # and the MOP is intended to become a RUNTIME metaobject -- perigrin:
    # "the long term thoughts of the MOP being potentially a runtime MOP".
    # `$obj->meta->field('n')->type` must answer `Int`, because that is what
    # the LANGUAGE says; `i64` is a compilation artifact with no business
    # surviving into a running program.
    #
    # So the Chalk type stays canonical on the metaobject and the LLVM type is
    # DERIVED HERE, on demand. That makes a runtime MOP correct by
    # construction: nothing ever writes a compile-time type into it, so nothing
    # can leak. It also explains why MOP::Field has no `set_type` and why
    # `set_return_type` refuses this rewrite -- it enforces narrowing WITHIN
    # the Chalk lattice, and crossing to LLVM vocabulary is a different
    # operation that should not borrow that door.
    #
    # THIS IS NOT "consumers deciding encoding one site at a time", which the
    # T2 design rightly forbids. That objection is to N INDEPENDENT decisions;
    # this is ONE decision in one place, called from wherever a declared type
    # meets the backend (measured: 3 such sites, all in Target/LLVM.pm). The
    # graph nodes are still REWRITTEN -- only the metaobject, which outlives
    # compilation, keeps its own vocabulary.
    sub llvm_type_for ($class, $chalk_type) {
        return undef unless defined $chalk_type;
        # Already an LLVM type, or a name T2 does not narrow (Unknown reaching
        # here is the caller's to diagnose): pass it through unchanged.
        return $chalk_type unless exists $CANDIDATES{$chalk_type};
        return $CANDIDATES{$chalk_type}[0];
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
    # narrow_num($node) -> 'double' or 'i64'. THE ONLY MULTI-CANDIDATE CHOICE.
    #
    # `Num` maps to {double, i64} and every other Chalk type has one candidate,
    # so this is where the representation question is actually asked. Getting
    # it wrong is a live miscompile, pinned as a GAP in
    # t/corpus/mdtest/arithmetic.md:
    #
    #     my $n = 9007199254740993; my $s = $n + 0.0;
    #     perl:  9007199254740993      chalk: 9.00719925474099e+15
    #
    # `%_REPR_LLVM_TYPE` maps Num to double unconditionally, so the sitofp
    # cannot hold an i64 above 2^53. That table is a DEFAULT executed before any
    # constraint is seen; this is the same decision made after.
    #
    # THREE CONSTRAINT SOURCES, measured at 36 of 54 Num nodes directly and 46
    # of 54 after propagation
    # (docs/plans/2026-09-04-narrowing-reaches-85-percent.md):
    #
    #   (a) a consumer states a requirement
    #   (b) a fractional literal constrains itself
    #   (c) every value input is already Int -- the inputs PROVE i64
    #
    # Source (c) is the strongest and was the one missed in the first design
    # pass: it proves i64 rather than merely failing to contradict it.
    #
    # ORDER MATTERS AND IS NOT ARBITRARY. Fractional evidence is checked first
    # because it is POSITIVE evidence about this value, while "all inputs are
    # Int" is evidence about its operands. A node with one fractional and one
    # integral input is a double, and reversing the order would call it i64.
    sub narrow_num ($class, $node) {
        my $stamp = $node->stamp // '';
        die "T2: narrow_num expects a Num-stamped node, got '"
          . ($stamp eq '' ? '(unstamped)' : $stamp) . "' (op="
          . $node->operation . ")\n"
            unless $stamp eq 'Num';

        # (b) A FRACTIONAL LITERAL IS ITS OWN CONSTRAINT. Nothing needs to
        # observe `1.5` to know it cannot be an integer.
        return 'double' if $class->_is_fractional_constant($node);

        # (b') A FRACTIONAL INPUT propagates the same way. Checked before (c)
        # so that Add(Int, 1.5) is a double rather than being claimed by the
        # all-Int rule -- which it would not be, since 1.5 is not Int, but
        # stating the order makes the dependency explicit rather than
        # incidental.
        for my $in (($node->inputs // [])->@*) {
            next unless defined $in && ref $in && $in->can('operation');
            return 'double' if $class->_is_fractional_constant($in);
        }

        # (c) EVERY VALUE INPUT IS ALREADY Int. The operands prove the result
        # needs no float, which is exactly the 2^53 case: a Coerce(Int -> Num)
        # over an Int constant has nothing fractional anywhere near it.
        my @vals = grep { defined $_ && ref $_ && $_ isa Chalk::IR::Value }
                   (($node->inputs // [])->@*);
        if (@vals) {
            my $every_int = 1;
            for my $v (@vals) {
                $every_int = 0 unless ($v->stamp // '') eq 'Int';
            }
            return 'i64' if $every_int;
        }

        # DEFAULT, AND IT IS FORCED RATHER THAN CHOSEN. An unobserved Num has
        # no most-general representation -- double and i64 are incomparable and
        # the emitter needs a concrete type -- so something must pick, and that
        # is what defaulting IS. GHC states the impossibility directly: you
        # cannot have both representation polymorphism and principal types.
        #
        # A NAMED RULE, not an `array->[0]`. Kept as its own sub for two
        # reasons: the reason belongs somewhere findable, and a test can
        # INVERT it to prove a constraint is load-bearing rather than merely
        # agreeing with the default. That check earned its keep immediately --
        # the 2^53 subtest passed with source (c) disabled, because `i64` is
        # also the default, and only the inverted-default run showed the rule
        # firing.
        return $class->_default_num_repr;
    }

    # _default_num_repr -> the representation an unobserved Num takes.
    #
    # FORCED, NOT CHOSEN. An unobserved Num has no most-general representation:
    # `double` and `i64` are incomparable and the emitter needs a concrete
    # type, so something must pick arbitrarily -- which is what defaulting IS.
    # GHC states the impossibility directly: you cannot have both
    # representation polymorphism and principal types.
    #
    # `i64` is the honest pick because it is what perl does: a literal stays an
    # IV until something makes it an NV. And there is no wrapping-i64 semantics
    # to preserve either -- `use64bitint` is a BUILD FLAG, and IV_MAX+1
    # promotes (B::IV -> B::PVIV, value intact) rather than wrapping.
    sub _default_num_repr ($class) { return 'i64' }

    # _is_fractional_constant($node) -> bool. A Constant whose value is not an
    # integer literal. Asked of the node itself and of its inputs.
    sub _is_fractional_constant ($class, $node) {
        return false unless $node->can('operation');
        return false unless $node->operation eq 'Constant';
        return false unless $node->can('value');
        my $v = $node->value;
        return false unless defined $v;
        return $v !~ /\A-?\d+\z/ ? true : false;
    }

    sub _choose ($class, $node, $stamp) {
        my $candidates = $CANDIDATES{$stamp}
            or die "T2: no candidate set for '$stamp' (op="
                 . $node->operation . ")\n";
        return $candidates->[0];
    }
}
