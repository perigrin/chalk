# ABOUTME: IR Phi node for merging values at CFG join points (Sea of Nodes).
# ABOUTME: Holds a region reference and supports set_backedge for loop back-edge wiring.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node) {
    field $region :param :reader;

    method operation() { 'Phi' }

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
