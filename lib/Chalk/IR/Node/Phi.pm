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
    # the backend then guesses from the inputs (_is_memory_phi).
    field $memory :param :reader = undef;

    method operation() { 'Phi' }
    method staleness_kind() { 'opaque' }

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
