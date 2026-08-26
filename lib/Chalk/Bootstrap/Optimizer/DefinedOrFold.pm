# ABOUTME: Folds a DefinedOr whose LHS element read is statically decided.
# ABOUTME: The proof is a Chalk IR fact, so the merge never reaches lowering.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed);

use Chalk::Bootstrap::Optimizer::Pass;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON ();   # _static_miss / _element_at

# `$a[9] // 42` over a three-element literal array is STATICALLY 42: the read
# provably misses, so `//` has a compile-time answer. `$a[1] // 42` is
# statically the element, for the mirror reason.
#
# WHY FOLD RATHER THAN LOWER IT. An unfolded merge puts a %Slot arm and an i64
# arm into one phi, and LLVM has no union type -- so lowering must pick one of:
#
#   (1) unbox the Slot to the other arm's type. Needs the payload's type AND
#       needs the payload to REALLY BE that type. A Slot node carries neither,
#       so this is the only option that can be WRONG -- measured, it emits
#       `phi %Str [ i64 ... ]` for a Str-element array and does not compile.
#       Worse in the polarity where both encodings are i64: no complaint.
#   (2) box the other arm into a %Slot. Sound given nothing; costs a box, and
#       a Str payload costs a malloc.
#   (3) prove one arm dead and delete the merge. This pass.
#
# (3) is free and available whenever the index is a literal over a literal
# aggregate. What it does NOT cover -- a dynamic index, a non-literal container
# -- is left standing for (2), deliberately: folding without a proof would be
# inventing a decision, which is (1)'s mistake wearing a different hat.
#
# WHY IT IS A PASS. `_static_miss` reads the container node and the index node
# and answers from the graph alone -- a Chalk IR fact, needing no serializer and
# no target. The loader's job is to reproduce the graph the frontend
# serialized, and nothing else
# (docs/plans/2026-08-24-loader-analysis-pipeline.md); typing that graph is the
# inference transformation's job, and discharging a decided branch is an
# optimizer's.
class Chalk::Bootstrap::Optimizer::DefinedOrFold
    :isa(Chalk::Bootstrap::Optimizer::Pass) {

    method name()  { return 'DefinedOrFold' }
    method scope() { return 'graph' }

    # run($graph, $factory) -> $graph
    #
    # $factory is accepted for signature parity with the other graph-scoped
    # passes (DCE takes one); this pass mints no nodes, so it goes unused. The
    # dead LHS is left for DCE to sweep rather than unlinked here -- one pass,
    # one job.
    method run($graph, $factory = undef) {
        die "run() requires a Chalk::IR::Graph"
            unless defined $graph && blessed($graph) && $graph isa Chalk::IR::Graph;

        my @nodes = $graph->nodes->@*;
        for my $node (@nodes) {
            next unless blessed($node) && $node->can('inputs');
            my $inputs = $node->inputs or next;

            for my $i (0 .. $inputs->$#*) {
                my $dor = $inputs->[$i];
                next unless blessed($dor) && $dor->can('operation')
                         && $dor->operation eq 'DefinedOr';

                my $folded = $self->_fold($dor) // next;
                $dor->remove_consumer($node);
                $folded->add_consumer($node);
                $inputs->[$i] = $folded;
            }
        }

        return $graph;
    }

    # _fold($dor) -> the surviving arm, or undef when nothing is provable.
    method _fold($dor) {
        my ($lhs, $rhs) = ($dor->inputs // [])->@*;
        return undef unless blessed($lhs) && blessed($rhs);
        return undef unless $lhs->can('operation') && $lhs->operation eq 'Subscript';

        my ($container, $index) = ($lhs->inputs // [])->@*;
        return undef unless blessed($container) && blessed($index);

        # Only a CONSTANT index over a literal aggregate is decidable. Both
        # helpers below check that themselves; the early return keeps a dynamic
        # index from being asked at all.
        return undef unless $index->can('operation')
                         && $index->operation eq 'Constant';

        # A provable MISS: the read yields undef, so `//` yields the RHS.
        return $rhs
            if Chalk::IR::Serialize::JSON::_static_miss($container, $index);

        # Otherwise the read may be a provable HIT -- resolvable to the very
        # element node, which makes the RHS dead.
        return $self->_element_at($container, $index);
    }

    # _element_at($container, $index) -> the element node, or undef.
    #
    # A provable HIT: the literal aggregate's element at a literal index.
    #
    # RESOLUTION MUST MIRROR _static_miss. Its own comment records why: when the
    # two disagreed, an out-of-bounds NESTED read ($r->[1][5]) took the hit path
    # and read 0 instead of undef -- a silent miscompile found by the R8
    # adversarial review. Same resolution, same flattening bail-out, or the same
    # class of bug returns here.
    method _element_at($container, $index) {
        $container = Chalk::IR::Serialize::JSON::_resolve_aggregate(
            Chalk::IR::Serialize::JSON::_unwrap_ref($container));
        return undef unless defined $container && blessed($container);

        my @in = $container->inputs->@*;

        # Perl list-flattening: a nested aggregate occupies ONE input slot but
        # expands to many elements at runtime, so a positional index over the
        # input list is wrong. _static_miss bails here for the same reason.
        return undef if grep {
            blessed($_) && ($_->operation eq 'ArrayRef' || $_->operation eq 'HashRef')
        } @in;

        my $op = $container->operation;
        if ($op eq 'ArrayRef') {
            return undef unless ($index->const_type // '') eq 'integer';
            my $i = $index->value;
            $i += scalar @in if $i < 0;          # perl's from-the-end
            return undef if $i < 0 || $i > $#in; # _static_miss owns the miss
            return $in[$i];
        }
        if ($op eq 'HashRef') {
            my $key = $index->value // return undef;
            for my $i (grep { $_ % 2 == 0 } 0 .. $#in) {   # even = keys
                my $k = $in[$i];
                next unless blessed($k) && $k->operation eq 'Constant';
                return $in[ $i + 1 ] if ($k->value // '') eq $key;
            }
            return undef;
        }
        return undef;
    }
}
