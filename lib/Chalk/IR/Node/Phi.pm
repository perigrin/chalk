# ABOUTME: IR Phi node for merging values at CFG join points (Sea of Nodes).
# ABOUTME: Holds a region reference and supports set_backedge for loop back-edge wiring.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Value) {
    field $region :param :reader;

    # WHICH PREDECESSOR EACH INCOMING VALUE ARRIVES FROM.
    #
    # inputs[i] pairs with predecessors[i]: the value in slot i flows in along
    # that control edge. This is LLVM's shape -- `addIncoming(Value*,
    # BasicBlock*)` stores the block explicitly per value -- and LLVM chose it
    # because predecessor ORDER is not stable.
    #
    # Chalk is in exactly that situation. Its two producers build a Region's
    # control inputs differently: the hand-written frontend passes the arms'
    # Projs (Actions.pm:2600, :2727), while perl5-son passes each arm's CURRENT
    # control, which is the arm's last effect whenever the arm has one. So a
    # Region input identifies the arm only sometimes, and recovering the
    # pairing from it took three successive backend fixes, each a wider search
    # -- the second of which shipped an INVERTED merge in both polarities.
    #
    # Recording it here rather than fixing the Region is deliberate: a Region
    # input is ALSO the control-chain link (what ran last on that path, so the
    # walk from Return reaches every effect), and substituting the Proj severs
    # the effects behind it -- measured, it dropped a Print off the chain. See
    # docs/research/2026-08-18-region-input-carries-two-jobs.md.
    #
    # OPTIONAL, and stays optional. Both producers must be migrated before any
    # consumer can require it, and a LOOP Phi pairs with the loop's entry and
    # back edges rather than with a predecessor list. Absent reads as "not
    # recorded", never as "no predecessors".
    field $predecessors :param :reader = undef;

    # Whether this Phi merges MEMORY versions rather than a value, when the
    # producer said: B::SoN flags its memory Phis. Undef is "not said", and
    # is_memory then reads it from the inputs.
    field $memory :param :reader = undef;

    method operation() { 'Phi' }
    method staleness_kind() { 'opaque' }

    # is_memory -> true for a MEMORY PHI: one merging memory versions (MemStart,
    # an element store, ...), not values. It is a scheduling token: the read
    # that consumes it loads the merged heap. Told from a value phi by its
    # inputs being memory nodes; the producer's flag (memory) settles the
    # cases the inputs alone cannot.
    method is_memory($seen = {}) {
        return 0 if $seen->{ refaddr($self) }++;   # a loop's phis reach each other
        my $inputs = $self->inputs // [];
        return 0 unless $inputs->@*;
        for my $in ($inputs->@*) {
            next unless blessed($in);
            return 1 if $in->operation eq 'MemStart';
            # an element store: an Assign whose lhs is a Subscript -- or a field,
            # or a shared file lexical, each a location stored through memory
            if ($in->operation eq 'Assign') {
                return 1 if grep { blessed($_) && $_->operation eq 'Subscript' }
                                 $in->inputs->@*;
                my $lhs = $in->inputs->[0];
                return 1 if blessed($lhs) && ( $lhs->operation eq 'FieldAccess'
                    || ( $lhs->operation eq 'PadAccess' && $lhs->is_location )
                    || ( $lhs->operation eq 'PostfixDeref' && ($lhs->sigil // '') eq '$' ) );
            }
            # a list assignment the producer merges as memory: its value is a List
            # no arm can flatten (`($lo, $u) = ...` in each arm, then a push)
            return 1 if $in->operation eq 'Assign' && ( $in->stamp // '' ) eq 'List' && $memory;  # static type
            # a package scalar's store
            return 1 if $in->operation eq 'EntryWrite';
            # a direct call: an inlined sub may store any of those
            # ...or a method call, which runs one (taking the producer's flag
            # wholesale instead let an arm walk that cycles through, pvm 124)
            return 1 if $in->operation eq 'Call' && ($in->dispatch_kind // '') =~ /\A(?:direct|method)\z/
                && !( defined $memory && !$memory );
            # ...or a builtin that versions memory (a push, a sort that runs code),
            # on a phi the producer says is memory (a value phi may merge a
            # sort's result).
            return 1 if $in->operation eq 'Call' && ( $in->dispatch_kind // '' ) eq 'builtin'
                && $memory;
            # a memory phi of a nested structure
            return 1 if $in->operation eq 'Phi' && $in->is_memory($seen);
        }
        return 0;
    }

    # NOT in the content hash, for the same reason control_in is not: it is a
    # per-use decoration recording where a value came from, not part of what
    # value this node IS. Two structurally identical Phis must still hash-cons.
    method content_hash() {
        return join('|', 'Phi', "region=" . $region->id(), $self->_serialize_inputs());
    }

    method set_backedge($value) {
        my $old = $self->inputs()->[1];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[1] = $value;
        $value->add_consumer($self) if defined $value;
    }
}
