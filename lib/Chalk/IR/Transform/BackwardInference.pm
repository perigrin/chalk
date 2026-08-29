# ABOUTME: Backward type inference -- a use site constrains its operands.
# ABOUTME: Ported from B::SoN's _infer_backward; fills holes, never preempts a source.
use 5.42.0;
use utf8;

package Chalk::IR::Transform::BackwardInference;

use Scalar::Util qw(blessed);
use Chalk::Grammar::Perl::TypeLibrary ();

# A DELIBERATE MIRROR of perl5-son's `_infer_backward` (lib/B/SoN.pm).
#
# The two repos run the same type-inference engine and cannot share a library:
# the SoN/Chalk namespace divorce means B::SoN stands alone, and a runtime
# dependency on chalk would put the producer inside the consumer. So the choice
# is deliberate mirror vs accidental re-derivation, and only one is honest --
# the same reasoning that produced `B/SoN/TypeLibrary.pm` as a labelled copy of
# chalk's `%BINARY_OP_SIGNATURES`.
#
# perigrin ruled 2026-08-29 that the PRODUCER's implementation is the source of
# truth for chalk. What obliges this copy to track it: chalk's corpus gate runs
# producer output through chalk's lowering, so a disagreement about what an
# operator yields surfaces BEHAVIOURALLY rather than silently. That is the only
# enforcement either side has.
#
# TRANSLATION from the original, which is otherwise line-for-line:
#   SoN::IR::Value        -> Chalk::IR::Value
#   $node->stamp->type    -> $node->stamp        (chalk's stamp IS the type
#                                                 string; the producer wraps it
#                                                 in a one-field object)
#   SoN::IR::Stamp::meet  -> TypeLibrary::meet_types
#   B::SoN::TypeLibrary   -> Chalk::Grammar::Perl::TypeLibrary
#
# THE RULE THIS PASS OBEYS, and the reason it is not simply "constrain
# everything": backward inference FILLS A HOLE, it never PREEMPTS A SOURCE. It
# is valid only where the type is genuinely open -- a slot read with no other
# source. Everything else has an authoritative source elsewhere: a Call's type
# is its callee's return type, a Subscript's is its container's element type, a
# Phi's is the join of its arms. Ignoring that shipped a miscompile in the
# producer (a Call stamped from its CALLER's requirement, wire asserting a
# return type the callee did not have).

# _thread_through_coerce($node) -> the value beneath any Coerce chain.
#
# A COERCE IS TRANSPARENT TO A REQUIREMENT. `$s . "!"` has the Concat consuming
# a Coerce, not $s, so a requirement would stop at a node that is already Str.
# Descend to the value underneath: it is the one with no forward seed, and the
# one the requirement is about.
sub _thread_through_coerce ($node) {
    my $hops = 0;
    while ($node && blessed($node) && $node->operation eq 'Coerce' && $hops++ < 8) {
        $node = ($node->inputs // [])->[0];
    }
    return $node;
}

# _is_backward_inferable($node) -- may a USE SITE decide this node's type?
# Only a slot read with no other source. See THE RULE above.
sub _is_backward_inferable ($node) {
    my $op = $node->operation;
    return true if $op eq 'PadAccess';
    return true if $op eq 'FieldAccess';
    return true if $op eq 'Parameter';
    return false;
}

# The declared type of a scalar-slot read is `Scalar`; meeting it with the
# requirement is what narrows. A node whose declaration says nothing takes the
# requirement directly.
sub _declared_slot_type ($node) {
    my $op = $node->operation;
    return 'Scalar' if $op eq 'PadAccess' || $op eq 'FieldAccess';
    return undef;
}

# run(\%graphs) -> count of nodes newly stamped.
sub run ($graphs) {
    # TERMINATION. Three independent things bound this loop, in order of
    # strength:
    #
    #   1. The `Unknown` gate below. A node is only ever considered while its
    #      stamp is literally 'Unknown', and filling it removes it from
    #      consideration for good -- so each node moves AT MOST ONCE and the
    #      loop is bounded by the number of holes. This is what actually
    #      terminates the pass today (measured: 8 chained holes settle in 2
    #      rounds).
    #   2. Kildall's store discipline at the write site -- meet the node's own
    #      stamp into the result, and store only on a change. That is what
    #      keeps the chain monotone if (1) is ever loosened, which is exactly
    #      what an optimistic CCP-style phase for recursive calls would need.
    #   3. $ROUNDS, a belt. It must never be the thing that stops the loop:
    #      exhausting it would silently TRUNCATE inference, leaving holes
    #      unfilled with no signal. Hence the die below -- reaching the cap is
    #      a bug in (1) or (2), not a tuning problem to be fixed by raising it.
    my $ROUNDS  = 10;
    my $stamped = 0;

    for my $round (1 .. $ROUNDS) {
        my $changed = 0;

        for my $gname (sort keys $graphs->%*) {
            my $graph = $graphs->{$gname} or next;

            # Collect, per value node, the requirements its consumers impose.
            my %required;
            for my $node ($graph->nodes->@*) {
                my $op_name = $node->operation;
                my @inputs  = ($node->inputs // [])->@*;
                for my $i (0 .. $#inputs) {
                    my $want = Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op(
                        $op_name, $i
                    ) // next;
                    my $operand = $inputs[$i] or next;
                    next unless blessed($operand) && $operand->isa('Chalk::IR::Value');

                    $operand = _thread_through_coerce($operand);
                    next unless $operand
                        && blessed($operand)
                        && $operand->isa('Chalk::IR::Value');

                    # Two uses of one value both constrain it: MEET the
                    # requirements, so the value must satisfy both.
                    my $have = $required{ $operand->id };
                    $required{ $operand->id } = defined $have
                        ? Chalk::Grammar::Perl::TypeLibrary::meet_types($have, $want)
                        : $want;
                }
            }

            for my $node ($graph->nodes->@*) {
                next unless blessed($node) && $node->isa('Chalk::IR::Value');
                next unless ($node->stamp // '') eq 'Unknown';
                next unless _is_backward_inferable($node);
                my $want = $required{ $node->id } or next;
                next if $want eq 'Unknown';

                # Kildall's store discipline, in the descending direction:
                # fold every source -- the declaration, the requirement, AND
                # the stamp already on the node -- into a single meet. Meeting
                # in the node's own value is what makes the chain monotone:
                # without it a later round can move the stamp SIDEWAYS between
                # two incomparable types and the loop need never settle.
                my $declared = _declared_slot_type($node);
                my $result   = $want;
                for my $src ($declared, $node->stamp) {
                    next unless defined $src && $src ne 'Unknown';
                    $result = Chalk::Grammar::Perl::TypeLibrary::meet_types($result, $src);
                    last unless defined $result;
                }

                # `None` means the declaration and the use cannot both hold.
                # That is a COERCION SITE, not a type here -- leave it for the
                # pass that materialises coercions rather than stamping a bottom.
                next if !defined $result || $result eq 'None' || $result eq 'Unknown';

                # ...and store only on an actual move. That is the other half
                # of the proof: a strictly descending chain in a lattice of
                # finite height must reach quiescence, so `last unless $changed`
                # below is the real termination argument. $ROUNDS is a belt.
                my $prev = $node->stamp;
                next if defined $prev && $prev eq $result;

                $node->set_stamp($result);
                $changed++;
                $stamped++;
            }
        }

        last unless $changed;

        die "BackwardInference did not reach a fixpoint in $ROUNDS rounds; "
          . "this means a stamp is moving repeatedly rather than settling, "
          . "and inference would otherwise be silently truncated"
            if $round == $ROUNDS;
    }

    return $stamped;
}

1;
